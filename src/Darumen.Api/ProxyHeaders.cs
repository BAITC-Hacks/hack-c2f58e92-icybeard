using Microsoft.AspNetCore.HttpOverrides;

namespace Darumen.Api;

/// <summary>Адрес клиента за прокси стенда: хостовый Caddy (TLS) → nginx контейнера web → api. Caddy ставит X-Forwarded-For
/// с адресом клиента (входящий заголовок от клиента он не пропускает), nginx дописывает адрес, с которого пришёл Caddy, —
/// шлюз docker-сети. Доверяем только loopback и частным сетям docker (ForwardedHeaders:KnownNetworks) и проходим не больше
/// ForwardedHeaders:ForwardLimit звеньев справа налево: RemoteIpAddress становится адресом клиента, а не nginx, и общий
/// лимит частоты для анонимных запросов считается на клиента, а не на весь стенд.
/// Инвариант (проверено на стенде 28.09.2026): хостовый Caddy v2.11 без trusted_proxies, блок dc.jurek.kz — простой
/// reverse_proxy, поэтому входящий от клиента X-Forwarded-For Caddy отбрасывает и пишет настоящий адрес. Если перед Caddy
/// появится CDN или в Caddyfile — trusted_proxies, пересчитайте ForwardLimit, иначе клиент сможет подставить свой адрес.
/// Доверие по частным сетям означает, что любой контейнер docker-сети может назвать себя прокси: API наружу не
/// публикуется (снаружи виден только web на 127.0.0.1:5173), поэтому это принятое ограничение.</summary>
public static class ProxyHeaders
{
    public const string Section = "ForwardedHeaders";

    /// <summary>Два звена: nginx и шлюз docker, через который приходит Caddy.</summary>
    private const int DefaultForwardLimit = 2;

    private static readonly string[] PrivateNetworks = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "fc00::/7"];

    public static IServiceCollection AddDarumenForwardedHeaders(this IServiceCollection services, IConfiguration configuration)
    {
        var section = configuration.GetSection(Section);
        var networks = section.GetSection("KnownNetworks").Get<string[]>() is { Length: > 0 } configured ? configured : PrivateNetworks;
        var forwardLimit = Math.Max(1, section.GetValue<int?>("ForwardLimit") ?? DefaultForwardLimit);
        // неверный CIDR в конфигурации — ошибка запуска, а не молча недоверенный прокси
        var parsed = networks.Select(n => System.Net.IPNetwork.Parse(n.Trim())).ToArray();

        services.Configure<ForwardedHeadersOptions>(options =>
        {
            options.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
            options.ForwardLimit = forwardLimit;
            foreach (var network in parsed)
            {
                options.KnownIPNetworks.Add(network); // loopback из значений по умолчанию остаётся
            }
        });
        return services;
    }
}
