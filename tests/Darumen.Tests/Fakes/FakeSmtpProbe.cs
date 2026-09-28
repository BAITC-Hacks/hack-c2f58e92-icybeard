using Darumen.Modules.Access.Status;

namespace Darumen.Tests.Fakes;

/// <summary>Проба SMTP без сети: Reachable — ответ пробы, Throws — проба падает (статус всё равно отвечает 200),
/// Calls и Last — сколько раз и куда пробовали подключиться.</summary>
public sealed class FakeSmtpProbe : ISmtpProbe
{
    private int _calls;

    public bool Reachable { get; set; } = true;

    public bool Throws { get; set; }

    public int Calls => Volatile.Read(ref _calls);

    public (string Host, int Port)? Last { get; private set; }

    public Task<bool> CanConnectAsync(string host, int port, TimeSpan timeout)
    {
        Interlocked.Increment(ref _calls);
        Last = (host, port);
        return Throws ? throw new InvalidOperationException("probe failure") : Task.FromResult(Reachable);
    }
}
