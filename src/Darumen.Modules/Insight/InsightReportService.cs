using System.Reflection;
using ClosedXML.Excel;
using Darumen.Modules.Analytics;
using QuestPDF.Drawing;
using QuestPDF.Fluent;
using QuestPDF.Helpers;
using QuestPDF.Infrastructure;

namespace Darumen.Modules.Insight;

/// <summary>Отчёт «Индекс доступности за месяц» в PDF (QuestPDF) и Excel (ClosedXML).
/// Данные — те же витрины, что на карте регионов; ничего не пересчитывается.</summary>
public sealed class InsightReportService(IAnalyticsRepository analytics)
{
    private const string FontFamily = "DejaVu Sans";
    private static bool _fontsReady;

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
        return format switch
        {
            "xlsx" => new Report(Excel(chosen, profile, items), "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                $"darumen-index-{chosen}.xlsx"),
            _ => new Report(Pdf(chosen, profile, items), "application/pdf", $"darumen-index-{chosen}.pdf"),
        };
    }

    private static byte[] Excel(string month, string profile, IReadOnlyList<IndexItemDto> items)
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
        using var output = new MemoryStream();
        workbook.SaveAs(output);
        return output.ToArray();
    }

    private static byte[] Pdf(string month, string profile, IReadOnlyList<IndexItemDto> items)
    {
        EnsureFonts();
        return Document.Create(document => document.Page(page =>
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
        })).GeneratePdf();
    }
}
