import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../l10n/strings.dart';
import '../../theme/tokens.dart';
import '../app_card.dart';
import '../format.dart';
import '../hero_number.dart';
import '../inline_disclosure.dart';
import '../origin_tag.dart';

/// «Прогноз» (RouteCitizenView.vue, блок D; решение Q1): сначала фраза «Половина пациентов в этой очереди ждёт
/// госпитализации не больше», потом «≈ p50 дн.», ниже «9 из 10 пациентов ждут не больше p90 дн.» и — если сервер
/// прислал долю — «… попадают в больницу в течение 30 дней.»; метка «прогноз модели» / «расчёт по правилу».
/// Ориентир Минздрава — фразой с меткой правила и свёрнутым «Источник». Скрыт после подтверждённого перевода (Q18).
class RouteForecastCard extends StatelessWidget {
  const RouteForecastCard({super.key, required this.route});

  final PatientRoute route;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final f = route.forecast;
    final target = route.targetBenchmark;
    final within30 = f.pWithin30Days;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardLabel(s.forecastLabel, trailing: OriginTag(originModelOrRule(f.fromModel))),
          const SizedBox(height: AppSpacing.md),
          HeroNumber(
            lead: s.myForecastLead,
            value: approxDays(f.p50Days),
            unit: s.daysUnit,
            line: [s.myForecastNine(days(f.p90Days)), if (within30 != null) s.myForecastWithin30(pct(within30))].join('\n'),
          ),
          if (target != null) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [Text(s.benchmarkSentence(days(target.value)), style: theme.textTheme.bodySmall), const OriginTag(Origin.formula)],
            ),
            InlineDisclosure(
              title: s.sourceLabel,
              style: DisclosureStyle.quiet,
              child: Text(s.myBenchmarkSource(target.source), style: theme.textTheme.labelSmall),
            ),
          ],
        ],
      ),
    );
  }
}
