using System.Net;

namespace Darumen.Tests;

/// <summary>5.5: расширенный отчёт — индекс + перегруженные организации + прогнозы + открытые сигналы + решения
/// за месяц, в PDF и Excel. Проверяем только форму ответа (заголовки, непустое тело), как и для остальных
/// бинарных отчётов в этом проекте — байты PDF/Excel here не парсятся.</summary>
public sealed class InsightReportTests(TestApp app) : IClassFixture<TestApp>
{
    [Fact]
    public async Task Pdf_report_is_generated_with_all_sections_worth_of_data()
    {
        var response = await app.CreateClient("regulator").GetAsync("/api/v1/insight/reports?format=pdf");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("application/pdf", response.Content.Headers.ContentType!.MediaType);
        var bytes = await response.Content.ReadAsByteArrayAsync();
        Assert.True(bytes.Length > 0);
        // прогноз тянется через тот же gRPC-клиент, что и insight-чат: подтверждаем, что отчёт действительно его вызвал
        Assert.NotNull(app.Forecast.LastRequest);
        Assert.Equal("admissions_monthly", app.Forecast.LastRequest!.StreamId);
    }

    [Fact]
    public async Task Excel_report_is_generated_for_the_chosen_month_and_profile()
    {
        var response = await app.CreateClient("regulator").GetAsync("/api/v1/insight/reports?format=xlsx&month=2025-02&profileCode=381");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", response.Content.Headers.ContentType!.MediaType);
        var bytes = await response.Content.ReadAsByteArrayAsync();
        Assert.True(bytes.Length > 0);
    }

    [Fact]
    public async Task Report_is_404_when_month_is_outside_the_available_index()
    {
        var response = await app.CreateClient("regulator").GetAsync("/api/v1/insight/reports?format=pdf&month=2099-01");
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }
}
