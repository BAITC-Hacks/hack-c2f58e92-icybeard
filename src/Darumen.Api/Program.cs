using Darumen.Api;
using Darumen.Migrations;
using Darumen.Modules.Analytics;
using Darumen.Modules.Intake;
using Darumen.Modules.Journal;
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

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddOpenApi();
builder.Services.AddHealthChecks();
builder.Services.AddOutputCache();
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
    new IntakeModule());

var app = builder.Build();

app.UseExceptionHandler();
app.UseStatusCodePages();
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

app.Run();

// Нужно для WebApplicationFactory в тестах.
public partial class Program;
