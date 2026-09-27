using System.Security.Claims;
using Darumen.Shared.Auth;
using Microsoft.AspNetCore.Http;

namespace Darumen.Tests.Access;

/// <summary>Записи аудита, которые пишет само приложение, укладываются в схему journal.audit (method — varchar(10)):
/// иначе пачка вставки падает целиком и теряются и соседние записи.</summary>
public sealed class AuditRecordTests
{
    [Fact]
    public void Explicit_audit_entry_keeps_http_method_and_puts_action_into_detail()
    {
        var queue = new AuditQueue();
        var context = new DefaultHttpContext();
        context.Request.Method = HttpMethods.Put;
        context.Request.Path = "/api/v1/admin/roles/regulator/permissions";
        context.User = new ClaimsPrincipal(new ClaimsIdentity(
            [new Claim(DarumenClaims.Name, "admin1"), new Claim(ClaimTypes.Role, Roles.Admin), new Claim(DarumenClaims.MoCode, "028B")], "test"));

        Assert.True(queue.Record(context, "role_permissions", "regulator {\"worklist.view\":\"all\"}"));
        Assert.True(queue.Reader.TryRead(out var entry));
        Assert.Equal("PUT", entry!.Method);
        Assert.True(entry.Method.Length <= 10);
        Assert.Equal("/api/v1/admin/roles/regulator/permissions", entry.Path);
        Assert.Equal("028B", entry.MoCode);
        Assert.StartsWith("role_permissions: ", entry.Detail);
    }
}
