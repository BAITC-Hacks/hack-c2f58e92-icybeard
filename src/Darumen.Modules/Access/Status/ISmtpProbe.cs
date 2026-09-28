namespace Darumen.Modules.Access.Status;

/// <summary>Принимает ли почтовый сервер TCP-соединение. Не бросает: false — не подключились за отведённое время.</summary>
public interface ISmtpProbe
{
    Task<bool> CanConnectAsync(string host, int port, TimeSpan timeout);
}
