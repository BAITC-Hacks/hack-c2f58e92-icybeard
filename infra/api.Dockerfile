FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY Darumen.slnx ./
COPY src/ src/
COPY tests/ tests/
COPY proto/ proto/
RUN dotnet publish src/Darumen.Api/Darumen.Api.csproj -c Release -o /app

FROM mcr.microsoft.com/dotnet/aspnet:10.0
WORKDIR /app
COPY --from=build /app .
EXPOSE 8000
ENTRYPOINT ["dotnet", "Darumen.Api.dll"]
