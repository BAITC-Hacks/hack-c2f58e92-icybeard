using Darumen.Shared.Api;

namespace Darumen.Modules.Public;

/// <summary>Правила советов по прогнозу. Только бытовые предупреждения в духе гидрометслужбы: вода и тень в жару,
/// тёплая одежда в мороз, зонт и скользкие дороги, крем от солнца. Ничего о болезнях и лечении (ТЗ §11).</summary>
public static class WeatherTips
{
    public const double HeatFrom = 30;
    public const double FrostBelow = -15;
    public const double StrongWindFrom = 50;
    public const int RainProbabilityFrom = 60;
    public const double UvFrom = 6;

    public static IReadOnlyList<WeatherTipDto> For(IReadOnlyList<WeatherDayDto> days, string lang)
    {
        var kk = lang == Locale.Kk;
        var tips = new List<WeatherTipDto>();
        for (var i = 0; i < Math.Min(days.Count, 2); i++)
        {
            var d = days[i];
            if (d.TMax >= HeatFrom)
            {
                tips.Add(new("heat", i, kk
                    ? $"Ыстық {R(d.TMax)} °C дейін: су ішіңіз, 12–16 аралығында күннен қорғаныңыз, балалар мен қарттарды көлеңкеде ұстаңыз."
                    : $"Жара до {R(d.TMax)} °C: пейте воду, избегайте солнца с 12 до 16, детей и пожилых держите в тени."));
            }

            if (d.TMin <= FrostBelow)
            {
                tips.Add(new("frost", i, kk
                    ? $"Аяз {R(d.TMin)} °C дейін: жылы киініңіз, далада болу уақытын қысқартыңыз."
                    : $"Мороз до {R(d.TMin)} °C: одевайтесь теплее и сокращайте время на улице."));
            }

            if (d.WindMax >= StrongWindFrom)
            {
                tips.Add(new("wind", i, kk
                    ? $"Қатты жел {R(d.WindMax)} км/сағ дейін: ағаштар мен жарнама қалқандарының жанында абай болыңыз."
                    : $"Сильный ветер до {R(d.WindMax)} км/ч: осторожнее рядом с деревьями и рекламными щитами."));
            }

            if (d.Code == "snow")
            {
                tips.Add(new("snow", i, kk ? "Қар: жол тайғақ, табаны сырғанамайтын аяқ киім киіңіз." : "Снег: скользко, обувь с нескользящей подошвой."));
            }
            else if (d.Code == "thunder")
            {
                tips.Add(new("thunder", i, kk ? "Найзағай: ашық жерде қалмаңыз, төбенің астында күтіңіз." : "Гроза: не оставайтесь на открытом месте, переждите под крышей."));
            }
            else if (d.PrecipitationProbability >= RainProbabilityFrom || d.Code == "rain")
            {
                tips.Add(new("rain", i, kk
                    ? $"Жаңбыр ықтималдығы {d.PrecipitationProbability} %: қолшатыр алыңыз, жолдар тайғақ."
                    : $"Вероятен дождь ({d.PrecipitationProbability} %): возьмите зонт, на дорогах скользко."));
            }

            if (d.Code == "fog")
            {
                tips.Add(new("fog", i, kk ? "Тұман: жолда жылдамдықты азайтыңыз, жаяу жүргіншілерге шағылыстырғыш керек." : "Туман: снижайте скорость на дороге, пешеходам нужны светоотражатели."));
            }

            if (d.UvIndex >= UvFrom)
            {
                tips.Add(new("uv", i, kk
                    ? $"УК-индекс {R(d.UvIndex)}: күннен қорғайтын крем мен бас киім."
                    : $"УФ-индекс {R(d.UvIndex)}: солнцезащитный крем и головной убор."));
            }
        }

        if (tips.Count == 0 && days.Count > 0)
        {
            tips.Add(new("fine", 0, kk ? "Ауа райы тыныш, ескертулер жоқ." : "Погода спокойная, предупреждений нет."));
        }

        return tips;
    }

    /// <summary>Код WMO → шесть слов для иконки: clear, cloudy, fog, rain, snow, thunder.</summary>
    public static string CodeWord(int wmo) => wmo switch
    {
        0 => "clear",
        >= 1 and <= 3 => "cloudy",
        45 or 48 => "fog",
        >= 51 and <= 67 or >= 80 and <= 82 => "rain",
        >= 71 and <= 77 or 85 or 86 => "snow",
        >= 95 => "thunder",
        _ => "cloudy",
    };

    private static string R(double v) => Math.Round(v).ToString("0");
}
