using System.Net;
using System.Net.Sockets;

namespace Darumen.Modules.Access.Status;

/// <summary>TCP connect к host:port почтового сервера без SMTP-диалога и без учётных данных: только «сервер слушает порт».</summary>
public sealed class TcpSmtpProbe : ISmtpProbe
{
    public async Task<bool> CanConnectAsync(string host, int port, TimeSpan timeout)
    {
        if (port is <= IPEndPoint.MinPort or > IPEndPoint.MaxPort)
        {
            return false;
        }

        using var deadline = new CancellationTokenSource(timeout);
        using var client = new TcpClient();
        try
        {
            await client.ConnectAsync(host, port, deadline.Token);
            return true;
        }
        catch (Exception exception) when (exception is SocketException or OperationCanceledException or IOException or ArgumentException)
        {
            return false;
        }
    }
}
