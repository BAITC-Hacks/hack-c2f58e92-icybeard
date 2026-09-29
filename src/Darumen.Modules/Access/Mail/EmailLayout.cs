using System.Net;

namespace Darumen.Modules.Access.Mail;

/// <summary>Каркас писем по доске mail-new («синяя гамма», handoff/tokens.css): холст #F5F6F8, белая карточка с
/// радиусом 20, текст #1B2440, кнопка-pill #2F6FE4 с белым текстом, Manrope/system-ui. Таблицы и инлайн-стили — для почтовых клиентов.</summary>
internal static class EmailLayout
{
    private const string Surface = "#F5F6F8";
    private const string Card = "#FFFFFF";
    private const string Ink = "#1B2440";
    private const string Muted = "#48536D";
    private const string Hairline = "#E1E8F5";
    private const string Accent = "#2F6FE4";
    private const string Font = "Manrope, system-ui, -apple-system, 'Segoe UI', Roboto, Arial, sans-serif";

    public static string E(string? value) => WebUtility.HtmlEncode(value ?? string.Empty);

    public static string Paragraph(string html) =>
        $"<p style=\"margin:0 0 16px;font-size:14px;line-height:1.55;color:{Ink};\">{html}</p>";

    public static string Note(string html) =>
        $"<p style=\"margin:16px 0 0;font-size:13px;line-height:1.5;color:{Muted};\">{html}</p>";

    public static string Button(string url, string label) =>
        $"<table role=\"presentation\" cellpadding=\"0\" cellspacing=\"0\" style=\"margin:8px 0 8px;\"><tr><td style=\"border-radius:999px;background:{Accent};\">" +
        $"<a href=\"{E(url)}\" style=\"display:inline-block;padding:14px 24px;font-family:{Font};font-size:14px;font-weight:700;color:#FFFFFF;" +
        $"text-decoration:none;border-radius:999px;\">{E(label)}</a></td></tr></table>";

    public static string Code(string code) =>
        $"<div style=\"margin:8px 0 16px;padding:18px 24px;background:#F4F7FD;border-radius:14px;font-size:32px;font-weight:800;" +
        $"letter-spacing:10px;text-align:center;color:{Ink};\">{E(code)}</div>";

    /// <summary>Строки «подпись — значение» (организация, роль, номер заявки).</summary>
    public static string Facts(params (string Label, string? Value)[] rows) =>
        "<table role=\"presentation\" width=\"100%\" cellpadding=\"0\" cellspacing=\"0\" style=\"margin:0 0 16px;\">" +
        string.Concat(rows.Where(r => !string.IsNullOrWhiteSpace(r.Value)).Select(r =>
            $"<tr><td style=\"padding:8px 0;border-bottom:1px solid {Hairline};font-size:13px;color:{Muted};\">{E(r.Label)}</td>" +
            $"<td style=\"padding:8px 0;border-bottom:1px solid {Hairline};font-size:14px;color:{Ink};text-align:right;\">{E(r.Value)}</td></tr>")) +
        "</table>";

    public static string Page(string title, string preheader, string body) =>
        $"""
        <!doctype html>
        <html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{E(title)}</title></head>
        <body style="margin:0;padding:0;background:{Surface};font-family:{Font};color:{Ink};">
        <span style="display:none;max-height:0;overflow:hidden;opacity:0;">{E(preheader)}</span>
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:{Surface};padding:32px 16px;">
        <tr><td align="center">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;">
        <tr><td style="padding:0 4px 16px;font-size:16px;font-weight:800;color:{Ink};">Darumen Health</td></tr>
        <tr><td style="background:{Card};border-radius:20px;padding:32px 28px;">
        <h1 style="margin:0 0 16px;font-size:20px;line-height:1.3;font-weight:800;color:{Ink};">{E(title)}</h1>
        {body}
        </td></tr>
        <tr><td style="padding:16px 4px 0;font-size:12px;line-height:1.5;color:{Muted};">Письмо отправлено автоматически, отвечать на него не нужно. Darumen Health — сервис маршрутов и сроков ожидания для системы здравоохранения Казахстана.</td></tr>
        </table>
        </td></tr></table>
        </body></html>
        """;
}
