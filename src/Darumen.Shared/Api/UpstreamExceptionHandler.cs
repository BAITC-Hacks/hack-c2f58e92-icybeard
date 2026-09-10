using System.Net.Sockets;
using Grpc.Core;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;
using Npgsql;

namespace Darumen.Shared.Api;

/// <summary>Ошибки сервисов моделей и хранилища превращаются в problem+json, а не в 500.</summary>
public sealed class UpstreamExceptionHandler(IProblemDetailsService problems, ILogger<UpstreamExceptionHandler> logger) : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(HttpContext httpContext, Exception exception, CancellationToken cancellationToken)
    {
        var (status, title, detail) = exception switch
        {
            RpcException rpc => rpc.StatusCode switch
            {
                StatusCode.InvalidArgument => (StatusCodes.Status422UnprocessableEntity, "Некорректный запрос к модели", rpc.Status.Detail),
                StatusCode.NotFound => (StatusCodes.Status404NotFound, "Не найдено", rpc.Status.Detail),
                StatusCode.Unavailable or StatusCode.DeadlineExceeded => (StatusCodes.Status503ServiceUnavailable, "Сервис моделей недоступен", "Повторите запрос позже"),
                _ => (StatusCodes.Status502BadGateway, "Ошибка сервиса моделей", rpc.Status.Detail),
            },
            NpgsqlException or SocketException => (StatusCodes.Status503ServiceUnavailable, "Хранилище недоступно", "Повторите запрос позже"),
            _ => (0, string.Empty, string.Empty),
        };

        if (status == 0)
        {
            return false;
        }

        if (status >= StatusCodes.Status500InternalServerError)
        {
            logger.LogWarning(exception, "Upstream failure mapped to {Status}", status);
        }

        httpContext.Response.StatusCode = status;
        return await problems.TryWriteAsync(new ProblemDetailsContext
        {
            HttpContext = httpContext,
            ProblemDetails = new() { Status = status, Title = title, Detail = detail },
        });
    }
}
