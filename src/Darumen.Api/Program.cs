using Scalar.AspNetCore;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddOpenApi();
builder.Services.AddHealthChecks();
builder.Services.AddProblemDetails();

var app = builder.Build();

app.UseExceptionHandler();
app.UseStatusCodePages();

app.MapOpenApi();
app.MapScalarApiReference(options => options.WithTitle("Darumen Health API"));
app.MapHealthChecks("/health");

var v1 = app.MapGroup("/api/v1");
v1.MapGet("/", () => Results.Ok(new { name = "Darumen Health", version = "0.1.0" }))
  .WithName("Root");

app.Run();

// Нужно для WebApplicationFactory в тестах.
public partial class Program;
