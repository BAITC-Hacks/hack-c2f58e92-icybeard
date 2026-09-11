using Darumen.Api;
using Darumen.Migrations;
using Darumen.Modules.Analytics;
using Darumen.Modules.Insight;
using Darumen.Modules.Intake;
using Darumen.Modules.Journal;
using Darumen.Modules.Medicines;
using Darumen.Modules.Queue;
using Darumen.Modules.RefData;
using Darumen.Modules.Simulation;
using Darumen.Shared;
using Darumen.Shared.Auth;
using Darumen.Shared.Data;
using Darumen.Shared.Messaging;
using Darumen.Shared.Modules;
using Microsoft.EntityFrameworkCore;
using Scalar.AspNetCore;

DotEnv.Load(); // ключи из .env в корне репозитория без сторонних пакетов

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddOpenApi();
builder.Services.AddHealthChecks();
builder.Services.AddOutputCache();
builder.Services.AddReverseProxy().LoadFromConfig(builder.Configuration.GetSection("ReverseProxy"));
builder.Services.AddCors(options => options.AddDefaultPolicy(policy =>
{
    var origins = builder.Configuration.GetSection("Cors:Origins").Get<string[]>() ?? [];
    if (origins.Length == 0)
    {
        policy.SetIsOriginAllowed(_ => true); // разработка: Flutter web и Vite на любых локальных портах
    }
    else
    {
        policy.WithOrigins(origins);
    }

    policy.AllowAnyHeader().AllowAnyMethod().WithExposedHeaders("Location");
}));
builder.Services.AddDarumenCore(builder.Configuration);
builder.Services.AddDarumenDbContext<DarumenDbContext>(builder.Configuration, options => options.UseNpgsql(builder.Configuration.PostgresConnection()));
builder.Host.AddDarumenMessaging(builder.Configuration, opts => opts.Discovery.IncludeAssembly(typeof(IntakeModule).Assembly));
builder.Services.AddHostedService<MigrationHostedService>();
builder.Services.AddDarumenModules(
    builder.Configuration,
    new QueueModule(),
    new AnalyticsModule(),
    new SimulationModule(),
    new JournalModule(),
    new RefDataModule(),
    new IntakeModule(),
    new MedicinesModule(),
    new InsightModule());

var app = builder.Build();

app.UseExceptionHandler();
app.UseStatusCodePages();
app.UseCors();
app.UseAuthentication();
app.UseAuthorization();
app.UseMiddleware<AuditMiddleware>();
app.UseOutputCache();

app.MapOpenApi();
app.MapScalarApiReference(options => options.WithTitle("Darumen Health API"));
app.MapHealthChecks("/health");

var v1 = app.MapGroup("/api/v1");
v1.MapGet("/", () => Results.Ok(new { name = "Darumen Health", version = "0.2.0" }))
  .WithName("Root");
v1.MapDarumenModules();
app.MapReverseProxy(); // Python-сервисы за тем же хостом: скрайб /api/v1/scribe/*

app.Run();

// Нужно для WebApplicationFactory в тестах.
public partial class Program;
