FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY Darumen.slnx ./
COPY src/ src/
COPY tests/ tests/
COPY proto/ proto/
RUN dotnet publish src/Darumen.Api/Darumen.Api.csproj -c Release -o /app

FROM mcr.microsoft.com/dotnet/aspnet:10.0
# libgssapi-krb5-2 — Npgsql пробует Kerberos при старте и без библиотеки пишет ошибку в лог;
# curl — для healthcheck в docker-compose.prod.yml (в образе aspnet его нет)
RUN apt-get update && apt-get install -y --no-install-recommends libgssapi-krb5-2 curl && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /app .
EXPOSE 8000
ENTRYPOINT ["dotnet", "Darumen.Api.dll"]
