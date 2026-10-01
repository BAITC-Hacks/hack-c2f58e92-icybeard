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

/// <summary>Отчёт «Доступность плановой госпитализации за месяц» в PDF (QuestPDF) и Excel (ClosedXML): пять разделов
/// (регионы, перегруженные больницы, прогноз, необычные отклонения, решения за месяц). Отчёт читают руководители,
/// поэтому вместо кодов — названия (регионы, профили, больницы, роли), вместо p90/score/актора — слова, у каждого
/// раздела — короткое пояснение. Данные — те же витрины, что на карте регионов; ничего не пересчитывается.</summary>
public sealed class InsightReportService(
    IAnalyticsRepository analytics,
    IQueueStateRepository queue,
    IDecisionRepository decisions,
    LoadForecasting.LoadForecastingClient forecasting,
    IOptions<ModelServicesOptions> modelServices,
    Darumen.Modules.RefData.IRefDataRepository refData)
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
        var names = await NamesAsync(lang, ct);

        var sections = Sections(chosen, profile, names, items, overloaded, forecasts, openAnomalies, monthDecisions);
        return format switch
        {
            "xlsx" => new Report(Excel(sections), "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", $"darumen-otchet-{chosen}.xlsx"),
            _ => new Report(Pdf(sections), "application/pdf", $"darumen-otchet-{chosen}.pdf"),
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
        // события записи приёма (согласие, сессия, памятка) — служебные, не управленческие решения
        return page.Items
            .Where(d => d.Subject != Darumen.Shared.Api.DecisionSubjects.Scribe)
            .Where(d => d.RecordedAt.UtcDateTime >= from.ToDateTime(TimeOnly.MinValue) && d.RecordedAt.UtcDateTime < to.ToDateTime(TimeOnly.MinValue))
            .ToList();
    }

    /// <summary>Один раздел отчёта: одинаково рисуется листом Excel и страницей PDF.</summary>
    private sealed record Section(string Sheet, string Title, string Subtitle, string[] Headers, float[] Widths, IReadOnlyList<string[]> Rows, string Note);

    private sealed record Names(
        IReadOnlyDictionary<string, string> Regions, IReadOnlyDictionary<string, string> Profiles, IReadOnlyDictionary<string, string> Organizations)
    {
        public string Region(string? kato) => kato is not null && Regions.TryGetValue(kato, out var n) ? n : kato ?? "—";
        public string Profile(string? code) => code is null || code == AnalyticsEndpoints.AllProfiles ? "все профили" : Profiles.TryGetValue(code, out var n) ? n : code;
        public string Organization(string? moCode) => moCode is not null && Organizations.TryGetValue(moCode, out var n) ? n : moCode ?? "—";
    }

    private async Task<Names> NamesAsync(string lang, CancellationToken ct)
    {
        var regions = (await refData.RegionsAsync(lang, ct)).ToDictionary(r => r.RegionKato, r => r.Name);
        var profiles = (await refData.ProfilesAsync(ct)).GroupBy(p => p.ProfileCode).ToDictionary(g => g.Key, g => g.First().Name);
        var organizations = (await refData.OrganizationsAsync(null, null, null, 10000, ct)).GroupBy(o => o.MoCode).ToDictionary(g => g.Key, g => g.First().Name);
        return new Names(regions, profiles, organizations);
    }

    private static readonly string[] MonthNames = ["январь", "февраль", "март", "апрель", "май", "июнь", "июль", "август", "сентябрь", "октябрь", "ноябрь", "декабрь"];

    /// <summary>«2025-03» → «март 2025»; другие форматы периода — как есть.</summary>
    private static string MonthText(string period) =>
        period.Length >= 7 && int.TryParse(period[..4], out var year) && int.TryParse(period[5..7], out var m) && m is >= 1 and <= 12
            ? period.Length == 7 ? $"{MonthNames[m - 1]} {year}" : $"{period[8..10]}.{period[5..7]}.{year}"
            : period;

    private static readonly System.Globalization.CultureInfo Ru = System.Globalization.CultureInfo.GetCultureInfo("ru-RU");

    private static string Num(double value, int digits = 0) => value.ToString("N" + digits, Ru);

    private static string Pct(double? share) => share is null ? "—" : (share.Value * 100).ToString("0", Ru) + " %";

    private static string StreamText(string streamId) => streamId switch
    {
        "admissions_monthly" => "Госпитализации",
        "er_visits_daily" => "Приёмный покой",
        "vac_monthly" => "Вакцинация",
        "rx_weekly" => "Обеспеченные рецепты",
        "onco_monthly" => "Онкология, впервые выявленные",
        "queue_daily" => "Очередь на госпитализацию",
        "lab_estimate_monthly" => "Лаборатории (оценка)",
        _ => streamId,
    };

    private static string SeverityText(string severity) => severity switch
    {
        "critical" => "высокая",
        "warning" => "средняя",
        _ => severity,
    };

    private static string RoleText(string role) => role switch
    {
        "citizen" => "пациент",
        "doctor" => "врач",
        "org_admin" => "главврач",
        "regulator" => "Минздрав",
        "steward" => "специалист по данным",
        "auditor" => "аудитор",
        "admin" => "администратор",
        _ => role,
    };

    private static string SubjectText(string subject) => subject switch
    {
        "referral" => "направление пациента",
        "anomaly" => "сигнал об отклонении",
        "route" => "маршрут пациента",
        "scenario" => "сценарий симулятора",
        "role_permissions" => "права роли",
        "user_access" => "доступ пользователя",
        "doctor_verification" => "проверка квалификации врача",
        "org_application" => "заявка больницы на подключение",
        _ => subject,
    };

    /// <summary>Отклонение словами: «больше обычного в 2,1 раза», «меньше обычного на 40 %», «нет при обычных 17».</summary>
    private static string DeviationText(double observed, double expected)
    {
        if (expected <= 0)
        {
            return observed > 0 ? "появилось при обычном нуле" : "—";
        }

        if (observed <= 0)
        {
            return "ни одного вместо обычных " + Num(expected);
        }

        var ratio = observed / expected;
        return ratio >= 1.5 ? $"больше обычного в {ratio.ToString("0.0", Ru)} раза"
            : ratio >= 1 ? $"больше обычного на {((ratio - 1) * 100).ToString("0", Ru)} %"
            : $"меньше обычного на {((1 - ratio) * 100).ToString("0", Ru)} %";
    }

    private static IReadOnlyList<Section> Sections(
        string month, string profile, Names names, IReadOnlyList<IndexItemDto> items, IReadOnlyList<OverloadedOrganizationDto> overloaded,
        IReadOnlyList<ForecastRow> forecasts, IReadOnlyList<AnomalyDto> anomalies, IReadOnlyList<DecisionDto> monthDecisions)
    {
        var period = MonthText(month);
        var profileText = names.Profile(profile);
        var skipped = forecasts.Count(f => f.Points is null);
        return
        [
            new Section(
                "Доступность по регионам",
                "Доступность плановой госпитализации по регионам",
                $"{period} · профиль: {profileText} · регионов: {items.Count}",
                ["Место", "Регион", "Индекс доступности (0–100)", "Ждут дольше 30 дней", "9 из 10 пациентов ждут не дольше, дн.", "Госпитализаций"],
                [0.6f, 3f, 1.4f, 1.3f, 1.6f, 1.3f],
                items.Select(i => new[] { i.Rank.ToString(Ru), i.Name, Num(i.IndexValue), Pct(i.ShareOver30), Num(i.P90Days), Num(i.N) }).ToList(),
                "Индекс сравнивает регионы между собой: чем больше пациентов ждут дольше 30 дней, чем дольше ждут 9 из 10 пациентов и чем больше отказов, " +
                "тем ниже индекс. 100 — самый доступный регион за месяц. Данные: направления на плановую госпитализацию (ИС БГ), " +
                "I квартал 2025. Регионы, где за месяц меньше 20 исходов (госпитализаций и отказов), не показаны."),
            new Section(
                "Перегруженные больницы",
                "Перегруженные больницы",
                $"{period} · профиль: {profileText} · больниц: {overloaded.Count}",
                ["Больница", "Регион", "Профиль коек", "Направлений больше, чем госпитализаций", "В очереди", "9 из 10 ждут не дольше, дн.", "Отказов за 4 недели"],
                [3f, 1.6f, 2f, 1.4f, 0.9f, 1.2f, 1f],
                overloaded.Select(o => new[]
                {
                    o.Name, names.Region(o.RegionKato), names.Profile(o.ProfileCode),
                    o.Load is null ? "госпитализаций нет" : $"в {o.Load.Value.ToString("0.0", Ru)} раза",
                    Num(o.QueueLen), o.QueueAgeP90 is null ? "—" : Num(o.QueueAgeP90.Value), Pct(o.RefusalRate4w),
                }).ToList(),
                "Больница перегружена, если направлений к ней приходит больше, чем она успевает госпитализировать, — очередь растёт. " +
                $"Показаны до {OverloadedLimit} самых загруженных больниц страны (данные за последние 4 недели)."),
            new Section(
                "Прогноз госпитализаций",
                "Прогноз плановых госпитализаций на 3 месяца",
                $"после месяца «{period}» · профиль: {profileText} · {ForecastRegionCount} регионов с самой низкой доступностью",
                ["Регион", "Месяц", "Ожидается госпитализаций", "Не меньше", "Не больше"],
                [3f, 1.4f, 1.6f, 1.1f, 1.1f],
                forecasts.Where(f => f.Points is not null)
                    .SelectMany(f => f.Points!.Select(p => new[] { f.Region.Name, MonthText(p.Period), Num(p.Yhat), Num(p.Lo), Num(p.Hi) }))
                    .ToList(),
                "Прогноз модели. «Не меньше» и «не больше» — диапазон, в который с высокой вероятностью попадёт фактическое число." +
                (skipped == 0 ? string.Empty : $" Для регионов без достаточной истории ({skipped}) прогноз не строился.")),
            new Section(
                "Необычные отклонения",
                "Необычные отклонения (открытые сигналы)",
                $"на {DateTime.UtcNow:dd.MM.yyyy} · сигналов: {anomalies.Count}",
                ["Что", "Регион", "Больница", "Дата", "Важность", "Было", "Обычно", "Отклонение"],
                [1.6f, 1.6f, 2.2f, 0.9f, 0.8f, 0.7f, 0.8f, 1.8f],
                anomalies.Select(a => new[]
                {
                    StreamText(a.StreamId), names.Region(a.RegionKato), a.MoCode is null ? "—" : names.Organization(a.MoCode), MonthText(a.Period),
                    SeverityText(a.Severity), Num(a.Observed), Num(a.Expected), DeviationText(a.Observed, a.Expected),
                }).ToList(),
                "Сигнал — день или месяц, когда пациентов было заметно больше или меньше, чем обычно ожидает модель. " +
                "«Было» — фактическое число, «Обычно» — сколько ожидалось. Показаны открытые сигналы на дату отчёта " +
                $"(до {OpenAnomaliesLimit}, сначала самые сильные); их нужно проверить и подтвердить или отметить ложными."),
            new Section(
                "Решения за месяц",
                "Решения, записанные в журнале",
                $"{period} · записей: {monthDecisions.Count}",
                ["Дата", "Кто", "Роль", "Что решали", "Комментарий"],
                [1.2f, 2f, 1.2f, 2f, 3f],
                monthDecisions.Select(d => new[]
                {
                    d.RecordedAt.UtcDateTime.ToString("dd.MM.yyyy HH:mm", Ru), d.Actor, RoleText(d.Role), SubjectText(d.Subject), d.Reason ?? "—",
                }).ToList(),
                "Все решения, которые сотрудники записали в журнал за месяц: по направлениям, сигналам, сценариям и доступу."),
        ];
    }

    private static byte[] Excel(IReadOnlyList<Section> sections)
    {
        using var workbook = new XLWorkbook();
        foreach (var section in sections)
        {
            var sheet = workbook.Worksheets.Add(section.Sheet);
            sheet.Cell(1, 1).Value = section.Title;
            sheet.Cell(1, 1).Style.Font.SetBold().Font.SetFontSize(14);
            sheet.Cell(2, 1).Value = section.Subtitle;
            sheet.Cell(2, 1).Style.Font.SetFontColor(XLColor.Gray);
            for (var c = 0; c < section.Headers.Length; c++)
            {
                var cell = sheet.Cell(4, c + 1);
                cell.Value = section.Headers[c];
                cell.Style.Font.SetBold().Fill.SetBackgroundColor(XLColor.FromHtml("#EEF1F6")).Alignment.SetWrapText(true).Alignment.SetVertical(XLAlignmentVerticalValues.Top);
            }

            for (var r = 0; r < section.Rows.Count; r++)
            {
                for (var c = 0; c < section.Headers.Length; c++)
                {
                    sheet.Cell(5 + r, c + 1).Value = section.Rows[r][c];
                }
            }

            if (section.Rows.Count == 0)
            {
                sheet.Cell(5, 1).Value = "Нет данных за этот период.";
            }

            var noteRow = 6 + Math.Max(section.Rows.Count, 1);
            sheet.Cell(noteRow, 1).Value = section.Note;
            sheet.Cell(noteRow, 1).Style.Font.SetItalic().Font.SetFontColor(XLColor.Gray);
            for (var c = 0; c < section.Headers.Length; c++)
            {
                sheet.Column(c + 1).Width = Math.Clamp(section.Widths[c] * 14, 10, 60);
            }

            sheet.Row(4).Height = 32;
            sheet.SheetView.FreezeRows(4);
        }

        using var output = new MemoryStream();
        workbook.SaveAs(output);
        return output.ToArray();
    }

    private static byte[] Pdf(IReadOnlyList<Section> sections)
    {
        EnsureFonts();
        return Document.Create(document =>
        {
            foreach (var section in sections)
            {
                document.Page(page =>
                {
                    page.Size(PageSizes.A4.Landscape());
                    page.Margin(32);
                    page.DefaultTextStyle(style => style.FontFamily(FontFamily).FontSize(10));
                    page.Header().Column(header =>
                    {
                        header.Item().Text("Darumen Health").FontSize(9).FontColor(Colors.Grey.Darken1);
                        header.Item().PaddingTop(2).Text(section.Title).Bold().FontSize(16);
                        header.Item().PaddingTop(2).Text(section.Subtitle).FontColor(Colors.Grey.Darken1);
                        header.Item().PaddingVertical(8).LineHorizontal(0.8f).LineColor(Colors.Grey.Lighten2);
                    });
                    page.Content().Column(content =>
                    {
                        content.Item().PaddingBottom(8).Text(section.Note).FontSize(9).FontColor(Colors.Grey.Darken2);
                        if (section.Rows.Count == 0)
                        {
                            content.Item().PaddingTop(8).Text("Нет данных за этот период.").FontColor(Colors.Grey.Darken1);
                            return;
                        }

                        content.Item().Table(table =>
                        {
                            table.ColumnsDefinition(columns =>
                            {
                                foreach (var width in section.Widths)
                                {
                                    columns.RelativeColumn(width);
                                }
                            });
                            table.Header(h =>
                            {
                                foreach (var title in section.Headers)
                                {
                                    h.Cell().Background(Colors.Grey.Lighten4).PaddingVertical(6).PaddingHorizontal(5).Text(title).Bold().FontSize(9);
                                }
                            });
                            foreach (var row in section.Rows)
                            {
                                foreach (var value in row)
                                {
                                    table.Cell().BorderBottom(0.4f).BorderColor(Colors.Grey.Lighten2).PaddingVertical(5).PaddingHorizontal(5).Text(value);
                                }
                            }
                        });
                    });
                    page.Footer().AlignRight().Text(text =>
                    {
                        text.DefaultTextStyle(style => style.FontSize(8).FontColor(Colors.Grey.Darken1));
                        text.Span($"Сформировано {DateTime.UtcNow:dd.MM.yyyy HH:mm} (UTC) · страница ");
                        text.CurrentPageNumber();
                        text.Span(" из ");
                        text.TotalPages();
                    });
                });
            }
        }).GeneratePdf();
    }
}
