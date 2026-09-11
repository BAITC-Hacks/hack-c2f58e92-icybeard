using Darumen.Api;
using Darumen.Modules.Insight;
using Microsoft.Extensions.Options;

namespace Darumen.Tests;

public sealed class InsightFactoryTests
{
    [Fact]
    public void Deepseek_is_the_default_and_needs_its_key()
    {
        var options = Options.Create(new InsightOptions());
        Assert.Equal("deepseek", options.Value.Provider);
        Assert.Equal("DEEPSEEK_API_KEY", LlmChatClientFactory.KeyVariable(options.Value.Provider));
        Assert.Equal("ANTHROPIC_API_KEY", LlmChatClientFactory.KeyVariable("anthropic"));
        var withoutKey = new LlmChatClientFactory(Options.Create(new InsightOptions { ApiKey = null }));
        var saved = Environment.GetEnvironmentVariable("DEEPSEEK_API_KEY");
        Environment.SetEnvironmentVariable("DEEPSEEK_API_KEY", null);
        try
        {
            Assert.Null(withoutKey.Create());
        }
        finally
        {
            Environment.SetEnvironmentVariable("DEEPSEEK_API_KEY", saved);
        }

        var withKey = new LlmChatClientFactory(Options.Create(new InsightOptions { ApiKey = "sk-test", Provider = "deepseek" }));
        Assert.NotNull(withKey.Create()); // клиент строится без обращения к сети
    }

    [Fact]
    public void DotEnv_sets_missing_variables_only()
    {
        var directory = Directory.CreateTempSubdirectory();
        File.WriteAllText(Path.Combine(directory.FullName, ".env"), "# comment\nDARUMEN_TEST_A=one\nDARUMEN_TEST_B=\"two\"\nDARUMEN_TEST_EMPTY=\n");
        Environment.SetEnvironmentVariable("DARUMEN_TEST_A", "preset");
        try
        {
            Assert.NotNull(DotEnv.Load(directory.FullName));
            Assert.Equal("preset", Environment.GetEnvironmentVariable("DARUMEN_TEST_A"));
            Assert.Equal("two", Environment.GetEnvironmentVariable("DARUMEN_TEST_B"));
            Assert.True(string.IsNullOrEmpty(Environment.GetEnvironmentVariable("DARUMEN_TEST_EMPTY")));
        }
        finally
        {
            Environment.SetEnvironmentVariable("DARUMEN_TEST_A", null);
            Environment.SetEnvironmentVariable("DARUMEN_TEST_B", null);
            directory.Delete(true);
        }
    }
}
