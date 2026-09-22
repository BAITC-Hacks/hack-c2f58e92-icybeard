using System.Reflection;
using ClosedXML.Excel;
using Darumen.Contracts.V1;
using Darumen.Modules.Analytics;
using Darumen.Modules.Journal;
using Darumen.Modules.Queue;
using Darumen.Shared.Options;
using Microsoft.Extensions.Options;
using QuestPDF.Drawing;
using QuestPDF.Fluent;
using QuestPDF.Helpers;
using QuestPDF.Infrastructure;

namespace Darumen.Modules.Insight;

/// <summary>Отчёт «Индекс доступности за месяц» в PDF (QuestPDF) и Excel (ClosedXML), плюс (5.5) четыре
/// дополнительных раздела для того же месяца/профиля: перегруженные организации, прогнозы, открытые сигналы
/// аномалий и решения, записанные в журнале за месяц. Данные — те же витрины, что на карте регионов и в insight-чате;
/// ничего не пересчитывается.</summary>
public sealed class InsightReportService(
    IAnalyticsRepository analytics,
    IQueueStateRepository queue,
    IDecisionRepository decisions,
    LoadForecasting.LoadForecastingClient forecasting,
    IOptions<ModelServicesOptions> modelServices)
{
    private const string FontFamily = "DejaVu Sans";
    private static bool _fontsReady;

    /// <summary>Сколько наименее доступных регионов (по индексу за выбранный месяц) получают раздел «Прогнозы».
    /// Прогноз по всем регионам сразу — 20 gRPC-вызовов на один отчёт, слишком тяжело для синхронной генерации
    /// PDF/Excel; регионы с самым низким индексом — ровно те, что интересны лицу, принимающему решение.</summary>
    private const int ForecastRegionCount = 5;

    private const int OverloadedLimit = 30;

    private const int OpenAnomaliesLimit = 50;

    /// <summary>QuestPDF без системных шрифтов: регистрируем встроенный DejaVu Sans (кириллица).</summary>
    private static void EnsureFonts()
    {
        if (_fontsReady)
        {
            return;
        }

        QuestPDF.Settings.License = LicenseType.Community;
        using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("Darumen.Modules.Insight.Fonts.DejaVuSans.ttf")
            ?? throw new InvalidOperationException("встроенный шрифт DejaVuSans.ttf не найден");
        FontManager.RegisterFontWithCustomName(FontFamily, stream);
        _fontsReady = true;
    }

    public sealed record Report(byte[] Content, string ContentType, string FileName);

    /// <summary>Прогноз одного региона для раздела «Прогнозы»; null-значение точек означает, что для
    /// пары регион/профиль ещё нет обученной модели (gRPC вернул ошибку) — строка пропускается, а не валит отчёт.</summary>
    private sealed record ForecastRow(IndexItemDto Region, IReadOnlyList<ForecastPointDto>? Points);

    public async Task<Report?> BuildAsync(string? month, string? profileCode, string format, string lang, CancellationToken ct)
    {
        var months = await analytics.IndexMonthsAsync(ct);
        if (months.Count == 0)
        {
            return null;
        }

        var chosen = string.IsNullOrWhiteSpace(month) ? months[^1] : month;
        if (!months.Contains(chosen))
        {
            return null;
        }

        var profile = string.IsNullOrWhiteSpace(profileCode) ? AnalyticsEndpoints.AllProfiles : profileCode;
        var items = await analytics.IndexAsync(chosen, profile, lang, ct);

        var overloaded = await queue.OverloadedAsync(null, profile == AnalyticsEndpoints.AllProfiles ? null : profile, OverloadedLimit, ct);
        var openAnomalies = (await analytics.AnomaliesAsync(new AnomalyFilter(null, null, null, AnomalyStatuses.Open), 1, OpenAnomaliesLimit, ct)).Items;
        var forecasts = await ForecastsAsync(items, profile, ct);
        var monthDecisions = await DecisionsForMonthAsync(chosen, ct);

        return format switch
        {
            "xlsx" => new Report(
                Excel(chosen, profile, items, overloaded, forecasts, openAnomalies, monthDecisions),
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                $"darumen-index-{chosen}.xlsx"),
            _ => new Report(
                Pdf(chosen, profile, items, overloaded, forecasts, openAnomalies, monthDecisions),
                "application/pdf", $"darumen-index-{chosen}.pdf"),
        };
    }

    /// <summary>Прогноз потока admissions_monthly для ForecastRegionCount регионов с наименьшим индексом
    /// доступности (items уже отсортированы по возрастанию индекса — item.Rank 1 = наименее доступный).
    /// Вызывает тот же gRPC-клиент напрямую (как InsightTools.ForecastAsync), а не ForecastService: там ответ
    /// завёрнут в IResult, из которого пришлось бы вытаскивать типизированный результат — а этот путь уже
    /// проверен существующим кодом инструментов insight-чата.</summary>
    private async Task<IReadOnlyList<ForecastRow>> ForecastsAsync(IReadOnlyList<IndexItemDto> items, string profile, CancellationToken ct)
    {
        var regions = items.OrderBy(i => i.IndexValue).Take(ForecastRegionCount).ToList();
        var rows = new List<ForecastRow>();
        foreach (var region in regions)
        {
            var request = new ForecastRequest { StreamId = "admissions_monthly", Horizon = 3 };
            request.Entity["region_kato"] = region.RegionKato;
            request.Entity["profile_code"] = profile;
            try
            {
                var response = await forecasting.ForecastAsync(request, deadline: DateTime.UtcNow.AddSeconds(modelServices.Value.TimeoutSeconds), cancellationToken: ct);
                rows.Add(new ForecastRow(region, response.Points.Select(p => new ForecastPointDto(p.Period, p.Yhat, p.Lo, p.Hi)).ToList()));
            }
            catch (Grpc.Core.RpcException)
            {
                // для региона/профиля ещё нет обученной модели — строка просто не попадает в отчёт
                rows.Add(new ForecastRow(region, null));
            }
        }

        return rows;
    }

    /// <summary>Решения журнала, записанные в течение выбранного месяца. IDecisionRepository.ListAsync не умеет
    /// фильтровать по дате (только actor/subject), а расширять публичный интерфейс/SQL модуля Journal ради одного
    /// отчёта — лишний риск для непроверенного изменения; вместо этого читаем существующим методом достаточно
    /// большую страницу и фильтруем по RecordedAt на стороне отчёта. Для объёма решений одного месяца в этой
    /// системе этого достаточно; для действительно большого архива решений потребовался бы отдельный метод с
    /// диапазоном дат на уровне SQL.</summary>
    private async Task<IReadOnlyList<DecisionDto>> DecisionsForMonthAsync(string month, CancellationToken ct)
    {
        var from = DateOnly.ParseExact(month + "-01", "yyyy-MM-dd");
        var to = from.AddMonths(1);
        var page = await decisions.ListAsync(null, null, null, 1, 5000, ct);
        return page.Items
            .Where(d => d.RecordedAt.UtcDateTime >= from.ToDateTime(TimeOnly.MinValue) && d.RecordedAt.UtcDateTime < to.ToDateTime(TimeOnly.MinValue))
            .ToList();
    }

    private static byte[] Excel(
        string month, string profile, IReadOnlyList<IndexItemDto> items, IReadOnlyList<OverloadedOrganizationDto> overloaded,
        IReadOnlyList<ForecastRow> forecasts, IReadOnlyList<AnomalyDto> openAnomalies, IReadOnlyList<DecisionDto> monthDecisions)
    {
        using var workbook = new XLWorkbook();
        var sheet = workbook.Worksheets.Add("Индекс доступности");
        sheet.Cell(1, 1).Value = $"Индекс доступности плановой госпитализации · {month} · профиль {profile}";
        sheet.Cell(1, 1).Style.Font.SetBold();
        string[] headers = ["Место", "Регион", "КАТО", "Индекс", "Доля > 30 дней", "p90, дн.", "Госпитализаций"];
        for (var c = 0; c < headers.Length; c++)
        {
            sheet.Cell(3, c + 1).Value = headers[c];
            sheet.Cell(3, c + 1).Style.Font.SetBold();
        }

        for (var r = 0; r < items.Count; r++)
        {
            var item = items[r];
            sheet.Cell(4 + r, 1).Value = item.Rank;
            sheet.Cell(4 + r, 2).Value = item.Name;
            sheet.Cell(4 + r, 3).Value = item.RegionKato;
            sheet.Cell(4 + r, 4).Value = Math.Round(item.IndexValue, 1);
            sheet.Cell(4 + r, 5).Value = Math.Round(item.ShareOver30, 3);
            sheet.Cell(4 + r, 5).Style.NumberFormat.Format = "0.0%";
            sheet.Cell(4 + r, 6).Value = Math.Round(item.P90Days, 0);
            sheet.Cell(4 + r, 7).Value = item.N;
        }

        sheet.Cell(5 + items.Count, 1).Value =
            "Индекс = 100 − среднее перцентильных рангов по доле ожидания дольше 30 дней и p90 внутри месяца и профиля. " +
            "Источник: направления ИС БГ, I квартал 2025 (ashyq.data.gov.kz). Строки с числом госпитализаций меньше 5 подавлены.";
        sheet.Columns().AdjustToContents();

        ExcelOverloaded(workbook, overloaded);
        ExcelForecasts(workbook, month, forecasts);
        ExcelAnomalies(workbook, openAnomalies);
        ExcelDecisions(workbook, month, monthDecisions);

        using var output = new MemoryStream();
        workbook.SaveAs(output);
        return output.ToArray();
    }

    private static void ExcelOverloaded(XLWorkbook workbook, IReadOnlyList<OverloadedOrganizationDto> overloaded)
    {
        var sheet = workbook.Worksheets.Add("Перегруженные организации");
        sheet.Cell(1, 1).Value = "Перегруженные организации (нагрузка 4 недели / пропускная способность > 1)";
        sheet.Cell(1, 1).Style.Font.SetBold();
        string[] headers = ["МО", "КАТО", "Профиль", "Нагрузка", "В очереди", "p90 очереди, дн.", "Отказы, 4 нед."];
        for (var c = 0; c < headers.Length; c++)
        {
            sheet.Cell(3, c + 1).Value = headers[c];
            sheet.Cell(3, c + 1).Style.Font.SetBold();
        }

        for (var r = 0; r < overloaded.Count; r++)
        {
            var o = overloaded[r];
            sheet.Cell(4 + r, 1).Value = o.Name;
            sheet.Cell(4 + r, 2).Value = o.RegionKato;
            sheet.Cell(4 + r, 3).Value = o.ProfileCode;
            sheet.Cell(4 + r, 4).Value = o.Load is null ? "—" : Math.Round(o.Load.Value, 2).ToString();
            sheet.Cell(4 + r, 5).Value = o.QueueLen;
            sheet.Cell(4 + r, 6).Value = o.QueueAgeP90 is null ? "—" : Math.Round(o.QueueAgeP90.Value, 0).ToString();
            sheet.Cell(4 + r, 7).Value = o.RefusalRate4w is null ? "—" : o.RefusalRate4w.Value.ToString("0.0%");
        }

        sheet.Cell(5 + overloaded.Count, 1).Value =
            "Нагрузка = (зарегистрировано за 4 недели / 28) / пропускная способность в день. Организация также считается " +
            "перегруженной, если поток есть, а пропускная способность равна нулю. Без ограничения по региону/профилю, " +
            "первые по стране, отсортированы по убыванию нагрузки.";
        sheet.Columns().AdjustToContents();
    }

    private static void ExcelForecasts(XLWorkbook workbook, string month, IReadOnlyList<ForecastRow> forecasts)
    {
        var sheet = workbook.Worksheets.Add("Прогнозы");
        sheet.Cell(1, 1).Value = $"Прогноз госпитализаций (admissions_monthly) на 3 месяца после {month}";
        sheet.Cell(1, 1).Style.Font.SetBold();
        string[] headers = ["Регион", "КАТО", "Период", "Прогноз", "Нижняя граница", "Верхняя граница"];
        for (var c = 0; c < headers.Length; c++)
        {
            sheet.Cell(3, c + 1).Value = headers[c];
            sheet.Cell(3, c + 1).Style.Font.SetBold();
        }

        var r = 4;
        foreach (var row in forecasts)
        {
            if (row.Points is null)
            {
                continue;
            }

            foreach (var point in row.Points)
            {
                sheet.Cell(r, 1).Value = row.Region.Name;
                sheet.Cell(r, 2).Value = row.Region.RegionKato;
                sheet.Cell(r, 3).Value = point.Period;
                sheet.Cell(r, 4).Value = Math.Round(point.Yhat, 0);
                sheet.Cell(r, 5).Value = Math.Round(point.Lo, 0);
                sheet.Cell(r, 6).Value = Math.Round(point.Hi, 0);
                r++;
            }
        }

        var skipped = forecasts.Count(f => f.Points is null);
        sheet.Cell(r + 1, 1).Value = skipped == 0
            ? $"Показаны {ForecastRegionCount} регионов с наименьшим индексом доступности за {month}."
            : $"Показаны {ForecastRegionCount} регионов с наименьшим индексом доступности за {month}; для {skipped} из них модель ещё не обучена — исключены.";
        sheet.Columns().AdjustToContents();
    }

    private static void ExcelAnomalies(XLWorkbook workbook, IReadOnlyList<AnomalyDto> anomalies)
    {
        var sheet = workbook.Worksheets.Add("Открытые сигналы");
        sheet.Cell(1, 1).Value = $"Открытые сигналы аномалий на дату формирования отчёта ({DateTime.UtcNow:yyyy-MM-dd})";
        sheet.Cell(1, 1).Style.Font.SetBold();
        string[] headers = ["Поток", "Регион", "МО", "Период", "Тяжесть", "Наблюдение", "Ожидание", "Score"];
        for (var c = 0; c < headers.Length; c++)
        {
            sheet.Cell(3, c + 1).Value = headers[c];
            sheet.Cell(3, c + 1).Style.Font.SetBold();
        }

        for (var r = 0; r < anomalies.Count; r++)
        {
            var a = anomalies[r];
            sheet.Cell(4 + r, 1).Value = a.StreamId;
            sheet.Cell(4 + r, 2).Value = a.RegionKato ?? "—";
            sheet.Cell(4 + r, 3).Value = a.MoCode ?? "—";
            sheet.Cell(4 + r, 4).Value = a.Period;
            sheet.Cell(4 + r, 5).Value = a.Severity;
            sheet.Cell(4 + r, 6).Value = Math.Round(a.Observed, 1);
            sheet.Cell(4 + r, 7).Value = Math.Round(a.Expected, 1);
            sheet.Cell(4 + r, 8).Value = Math.Round(a.Score, 2);
        }

        sheet.Cell(5 + anomalies.Count, 1).Value =
            "Снимок на дату формирования отчёта, не привязан к выбранному месяцу: сигнал, открытый в прошлом месяце и " +
            $"всё ещё не закрытый, здесь и остаётся. Показаны первые {OpenAnomaliesLimit} по периоду и |score| (как в /analytics/anomalies).";
        sheet.Columns().AdjustToContents();
    }

    private static void ExcelDecisions(XLWorkbook workbook, string month, IReadOnlyList<DecisionDto> monthDecisions)
    {
        var sheet = workbook.Worksheets.Add("Решения за месяц");
        sheet.Cell(1, 1).Value = $"Решения, записанные в журнале за {month}";
        sheet.Cell(1, 1).Style.Font.SetBold();
        string[] headers = ["Дата", "Актор", "Роль", "Тема", "ID темы", "Причина"];
        for (var c = 0; c < headers.Length; c++)
        {
            sheet.Cell(3, c + 1).Value = headers[c];
            sheet.Cell(3, c + 1).Style.Font.SetBold();
        }

        for (var r = 0; r < monthDecisions.Count; r++)
        {
            var d = monthDecisions[r];
            sheet.Cell(4 + r, 1).Value = d.RecordedAt.UtcDateTime.ToString("yyyy-MM-dd HH:mm");
            sheet.Cell(4 + r, 2).Value = d.Actor;
            sheet.Cell(4 + r, 3).Value = d.Role;
            sheet.Cell(4 + r, 4).Value = d.Subject;
            sheet.Cell(4 + r, 5).Value = d.SubjectId;
            sheet.Cell(4 + r, 6).Value = d.Reason ?? "—";
        }

        sheet.Cell(5 + monthDecisions.Count, 1).Value = $"Все решения из journal.decisions с recorded_at внутри {month} (UTC), по всем акторам и темам.";
        sheet.Columns().AdjustToContents();
    }

    private static byte[] Pdf(
        string month, string profile, IReadOnlyList<IndexItemDto> items, IReadOnlyList<OverloadedOrganizationDto> overloaded,
        IReadOnlyList<ForecastRow> forecasts, IReadOnlyList<AnomalyDto> openAnomalies, IReadOnlyList<DecisionDto> monthDecisions)
    {
        EnsureFonts();
        return Document.Create(document =>
        {
            document.Page(page =>
            {
                page.Size(PageSizes.A4);
                page.Margin(36);
                page.DefaultTextStyle(style => style.FontFamily(FontFamily).FontSize(9.5f));

                page.Header().Column(header =>
                {
                    header.Item().Text("Darumen Health · Индекс доступности плановой госпитализации").Bold().FontSize(14);
                    header.Item().PaddingTop(2).Text($"Месяц {month} · профиль {profile} · {items.Count} регионов").FontColor(Colors.Grey.Darken1);
                    header.Item().PaddingVertical(6).LineHorizontal(0.8f);
                });

                page.Content().PaddingTop(6).Table(table =>
                {
                    table.ColumnsDefinition(columns =>
                    {
                        columns.ConstantColumn(38);
                        columns.RelativeColumn(4);
                        columns.ConstantColumn(44);
                        columns.ConstantColumn(52);
                        columns.ConstantColumn(78);
                        columns.ConstantColumn(56);
                        columns.ConstantColumn(84);
                    });
                    table.Header(h =>
                    {
                        foreach (var title in new[] { "Место", "Регион", "КАТО", "Индекс", "Доля > 30 дн.", "p90, дн.", "Госпитализаций" })
                        {
                            h.Cell().Background(Colors.Grey.Lighten3).Padding(4).Text(title).Bold();
                        }
                    });
                    foreach (var item in items)
                    {
                        table.Cell().BorderBottom(0.4f).BorderColor(Colors.Grey.Lighten2).Padding(4).Text(item.Rank.ToString());
                        table.Cell().BorderBottom(0.4f).BorderColor(Colors.Grey.Lighten2).Padding(4).Text(item.Name);
                        table.Cell().BorderBottom(0.4f).BorderColor(Colors.Grey.Lighten2).Padding(4).Text(item.RegionKato);
                        table.Cell().BorderBottom(0.4f).BorderColor(Colors.Grey.Lighten2).Padding(4).Text($"{item.IndexValue:F1}");
                        table.Cell().BorderBottom(0.4f).BorderColor(Colors.Grey.Lighten2).Padding(4).Text($"{item.ShareOver30:P1}");
                        table.Cell().BorderBottom(0.4f).BorderColor(Colors.Grey.Lighten2).Padding(4).Text($"{item.P90Days:F0}");
                        table.Cell().BorderBottom(0.4f).BorderColor(Colors.Grey.Lighten2).Padding(4).Text(item.N.ToString("N0"));
                    }
                });

                page.Footer().Column(footer =>
                {
                    footer.Item().PaddingTop(6).Text(
                            "Индекс = 100 − среднее перцентильных рангов по доле ожидания дольше 30 дней и p90 внутри месяца и профиля (расчёт по формуле). " +
                            "Источник: направления ИС БГ, I квартал 2025, ashyq.data.gov.kz; строки с числом госпитализаций меньше 5 подавлены.")
                        .FontSize(7.5f).FontColor(Colors.Grey.Darken1);
                    footer.Item().PaddingTop(2).Text(text =>
                    {
                        text.DefaultTextStyle(style => style.FontSize(7.5f).FontColor(Colors.Grey.Darken1));
                        text.Span($"Сформировано {DateTime.UtcNow:yyyy-MM-dd HH:mm} UTC · dc.jurek.kz · страница ");
                        text.CurrentPageNumber();
                        text.Span(" из ");
                        text.TotalPages();
                    });
                });
            });

            PdfOverloadedPage(document, month, profile, overloaded);
            PdfForecastsPage(document, month, forecasts);
            PdfAnomaliesPage(document, openAnomalies);
            PdfDecisionsPage(document, month, monthDecisions);
        }).GeneratePdf();
    }

    private static void PdfHeader(PageDescriptor page, string title, string subtitle)
    {
        page.Size(PageSizes.A4);
        page.Margin(36);
        page.DefaultTextStyle(style => style.FontFamily(FontFamily).FontSize(9.5f));
        page.Header().Column(header =>
        {
            header.Item().Text(title).Bold().FontSize(14);
            header.Item().PaddingTop(2).Text(subtitle).FontColor(Colors.Grey.Darken1);
            header.Item().PaddingVertical(6).LineHorizontal(0.8f);
        });
    }

    private static void PdfFooter(PageDescriptor page, string note)
    {
        page.Footer().Column(footer =>
        {
            footer.Item().PaddingTop(6).Text(note).FontSize(7.5f).FontColor(Colors.Grey.Darken1);
            footer.Item().PaddingTop(2).Text(text =>
            {
                text.DefaultTextStyle(style => style.FontSize(7.5f).FontColor(Colors.Grey.Darken1));
                text.Span($"Сформировано {DateTime.UtcNow:yyyy-MM-dd HH:mm} UTC · dc.jurek.kz · страница ");
                text.CurrentPageNumber();
                text.Span(" из ");
                text.TotalPages();
            });
        });
    }

    private static void PdfOverloadedPage(IDocumentContainer document, string month, string profile, IReadOnlyList<OverloadedOrganizationDto> overloaded)
    {
        document.Page(page =>
        {
            PdfHeader(page, "Darumen Health · Перегруженные организации", $"Месяц {month} · профиль {profile} · {overloaded.Count} организаций");
            page.Content().PaddingTop(6).Table(table =>
            {
                table.ColumnsDefinition(columns =>
                {
                    columns.RelativeColumn(4);
                    columns.ConstantColumn(44);
                    columns.ConstantColumn(56);
                    columns.ConstantColumn(64);
                    columns.ConstantColumn(56);
                    columns.ConstantColumn(72);
                    columns.ConstantColumn(64);
                });
                table.Header(h =>
                {
                    foreach (var title in new[] { "МО", "КАТО", "Профиль", "Нагрузка", "В очереди", "p90 очереди, дн.", "Отказы, 4 нед." })
                    {
                        h.Cell().Background(Colors.Grey.Lighten3).Padding(4).Text(title).Bold();
                    }
                });
                foreach (var o in overloaded)
                {
                    table.Cell().BorderBottom(0.4f).BorderColor(Colors.Grey.Lighten2).Padding(4).Text(o.Name);
                    table.Cell().BorderBottom(0.4f).BorderColor(Colors.Grey.Lighten2).Padding(4).Text(o.RegionKato);
                    table.Cell().BorderBottom(0.4f).BorderColor(Colors.Grey.Lighten2).Padding(4).Text(o.ProfileCode);
                    table.Cell().BorderBottom(0.4f).BorderColor(Colors.Grey.Lighten2).Padding(4).Text(o.Load is null ? "—" : $"{o.Load.Value:F2}");
                    table.Cell().BorderBottom(0.4f).BorderColor(Colors.Grey.Lighten2).Padding(4).Text(o.QueueLen.ToString("N0"));
                    table.Cell().BorderBottom(0.4f).BorderColor(Colors.Grey.Lighten2).Padding(4).Text(o.QueueAgeP90 is null ? "—" : $"{o.QueueAgeP90.Value:F0}");
                    table.Cell().BorderBottom(0.4f).BorderColor(Colors.Grey.Lighten2).Padding(4).Text(o.RefusalRate4w is null ? "—" : $"{o.RefusalRate4w.Value:P1}");
                }
            });
            PdfFooter(page,
                "Нагрузка = (зарегистрировано за 4 недели / 28) / пропускная способность в день; также перегружена организация с потоком " +
                "и нулевой пропускной способностью. Без ограничения по региону/профилю, первые по стране, отсортированы по убыванию нагрузки.");
        });
    }

    private static void PdfForecastsPage(IDocumentContainer document, string month, IReadOnlyList<ForecastRow> forecasts)
    {
        document.Page(page =>
        {
            PdfHeader(page, "Darumen Health · Прогнозы", $"admissions_monthly, горизонт 3 месяца после {month} · {ForecastRegionCount} наименее доступных региона");
            page.Content().PaddingTop(6).Table(table =>
            {
                table.ColumnsDefinition(columns =>
                {
                    columns.RelativeColumn(3);
                    columns.ConstantColumn(44);
                    columns.ConstantColumn(64);
                    columns.ConstantColumn(64);
                    columns.ConstantColumn(64);
                    columns.ConstantColumn(64);
                });
                table.Header(h =>
                {
                    foreach (var title in new[] { "Регион", "КАТО", "Период", "Прогноз", "Нижн. граница", "Верхн. граница" })
                    {
                        h.Cell().Background(Colors.Grey.Lighten3).Padding(4).Text(title).Bold();
                    }
                });
                foreach (var row in forecasts)
                {
                    if (row.Points is null)
                    {
                        continue;
                    }

                    foreach (var point in row.Points)
                    {
                        table.Cell().BorderBottom(0.4f).BorderColor(Colors.Grey.Lighten2).Padding(4).Text(row.Region.Name);
                        table.Cell().BorderBottom(0.4f).BorderColor(Colors.Grey.Lighten2).Padding(4).Text(row.Region.RegionKato);
                        table.Cell().BorderBottom(0.4f).BorderColor(Colors.Grey.Lighten2).Padding(4).Text(point.Period);
                        table.Cell().BorderBottom(0.4f).BorderColor(Colors.Grey.Lighten2).Padding(4).Text($"{point.Yhat:F0}");
                        table.Cell().BorderBottom(0.4f).BorderColor(Colors.Grey.Lighten2).Padding(4).Text($"{point.Lo:F0}");
                        table.Cell().BorderBottom(0.4f).BorderColor(Colors.Grey.Lighten2).Padding(4).Text($"{point.Hi:F0}");
                    }
                }
            });
            var skipped = forecasts.Count(f => f.Points is null);
            PdfFooter(page, skipped == 0
                ? $"Показаны {ForecastRegionCount} регионов с наименьшим индексом доступности за {month}."
                : $"Показаны {ForecastRegionCount} регионов с наименьшим индексом доступности за {month}; для {skipped} из них модель ещё не обучена — исключены.");
        });
    }

    private static void PdfAnomaliesPage(IDocumentContainer document, IReadOnlyList<AnomalyDto> anomalies)
    {
        document.Page(page =>
        {
            PdfHeader(page, "Darumen Health · Открытые сигналы", $"На дату формирования отчёта {DateTime.UtcNow:yyyy-MM-dd} · {anomalies.Count} сигналов");
            page.Content().PaddingTop(6).Table(table =>
            {
                table.ColumnsDefinition(columns =>
                {
                    columns.RelativeColumn(3);
                    columns.ConstantColumn(44);
                    columns.ConstantColumn(56);
                    columns.ConstantColumn(56);
                    columns.ConstantColumn(56);
                    columns.ConstantColumn(64);
                    columns.ConstantColumn(64);
                    columns.ConstantColumn(48);
                });
                table.Header(h =>
                {
                    foreach (var title in new[] { "Поток", "Регион", "МО", "Период", "Тяжесть", "Наблюдение", "Ожидание", "Score" })
                    {
                        h.Cell().Background(Colors.Grey.Lighten3).Padding(4).Text(title).Bold();
                    }
                });
                foreach (var a in anomalies)
                {
                    table.Cell().BorderBottom(0.4f).BorderColor(Colors.Grey.Lighten2).Padding(4).Text(a.StreamId);
                    table.Cell().BorderBottom(0.4f).BorderColor(Colors.Grey.Lighten2).Padding(4).Text(a.RegionKato ?? "—");
                    table.Cell().BorderBottom(0.4f).BorderColor(Colors.Grey.Lighten2).Padding(4).Text(a.MoCode ?? "—");
                    table.Cell().BorderBottom(0.4f).BorderColor(Colors.Grey.Lighten2).Padding(4).Text(a.Period);
                    table.Cell().BorderBottom(0.4f).BorderColor(Colors.Grey.Lighten2).Padding(4).Text(a.Severity);
                    table.Cell().BorderBottom(0.4f).BorderColor(Colors.Grey.Lighten2).Padding(4).Text($"{a.Observed:F1}");
                    table.Cell().BorderBottom(0.4f).BorderColor(Colors.Grey.Lighten2).Padding(4).Text($"{a.Expected:F1}");
                    table.Cell().BorderBottom(0.4f).BorderColor(Colors.Grey.Lighten2).Padding(4).Text($"{a.Score:F2}");
                }
            });
            PdfFooter(page,
                "Снимок на дату формирования отчёта, не привязан к выбранному месяцу: сигнал, открытый ранее и всё ещё не закрытый, " +
                $"здесь и остаётся. Показаны первые {OpenAnomaliesLimit} по периоду и |score| (как в /analytics/anomalies).");
        });
    }

    private static void PdfDecisionsPage(IDocumentContainer document, string month, IReadOnlyList<DecisionDto> monthDecisions)
    {
        document.Page(page =>
        {
            PdfHeader(page, "Darumen Health · Решения за месяц", $"Журнал решений · {month} · {monthDecisions.Count} записей");
            page.Content().PaddingTop(6).Table(table =>
            {
                table.ColumnsDefinition(columns =>
                {
                    columns.ConstantColumn(80);
                    columns.RelativeColumn(2);
                    columns.ConstantColumn(64);
                    columns.RelativeColumn(2);
                    columns.ConstantColumn(64);
                    columns.RelativeColumn(3);
                });
                table.Header(h =>
                {
                    foreach (var title in new[] { "Дата", "Актор", "Роль", "Тема", "ID темы", "Причина" })
                    {
                        h.Cell().Background(Colors.Grey.Lighten3).Padding(4).Text(title).Bold();
                    }
                });
                foreach (var d in monthDecisions)
                {
                    table.Cell().BorderBottom(0.4f).BorderColor(Colors.Grey.Lighten2).Padding(4).Text(d.RecordedAt.UtcDateTime.ToString("yyyy-MM-dd HH:mm"));
                    table.Cell().BorderBottom(0.4f).BorderColor(Colors.Grey.Lighten2).Padding(4).Text(d.Actor);
                    table.Cell().BorderBottom(0.4f).BorderColor(Colors.Grey.Lighten2).Padding(4).Text(d.Role);
                    table.Cell().BorderBottom(0.4f).BorderColor(Colors.Grey.Lighten2).Padding(4).Text(d.Subject);
                    table.Cell().BorderBottom(0.4f).BorderColor(Colors.Grey.Lighten2).Padding(4).Text(d.SubjectId);
                    table.Cell().BorderBottom(0.4f).BorderColor(Colors.Grey.Lighten2).Padding(4).Text(d.Reason ?? "—");
                }
            });
            PdfFooter(page, $"Все решения из journal.decisions с recorded_at внутри {month} (UTC), по всем акторам и темам.");
        });
    }
}
