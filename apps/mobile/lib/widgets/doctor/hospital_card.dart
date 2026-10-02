import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../l10n/strings.dart';
import '../../theme/tokens.dart';
import '../../theme/tones.dart';
import '../../theme/typography.dart';
import '../app_card.dart';
import '../format.dart';
import '../inline_disclosure.dart';
import '../origin_tag.dart';
import '../route/forecast_factors.dart';
import '../status_chip.dart';
import 'fact_grid.dart';

/// Карточка «Текущая больница» маршрута пациента (веб `hospital-card`): метка происхождения прогноза, сроки «половина
/// пациентов ждёт не больше» и «9 из 10 …» с «≈», ожидаемая дата и риск отказа — процентом или словами (три полосы),
/// если больницы не было в обучении модели, красным выше 20 %; «Что сделать» — полный следующий шаг и обоснование;
/// раскрывашка «Из чего сложился прогноз» с факторами комплекта маршрута; ориентир Минздрава с источником.
class CurrentHospitalCard extends StatelessWidget {
  const CurrentHospitalCard({super.key, required this.route});

  final PatientRoute route;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final forecast = route.forecast;
    final doctor = route.doctor;
    final todo = doctor == null ? '' : s.worklistNextFull(doctor.nextActionCode, fallback: doctor.nextAction);
    final factors = forecastFactors(doctor?.shap?.factors ?? const [], s, profileName: route.organization.profileName);
    final target = route.targetBenchmark;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardLabel(s.patientRouteCurrentHospital, trailing: OriginTag(originModelOrRule(forecast.fromModel))),
          const SizedBox(height: AppSpacing.sm),
          FactGrid(facts: [
            RouteFact(s.patientRouteHalf, '${approxDays(forecast.p50Days)} ${s.daysUnit}'),
            RouteFact(s.patientRouteNinety, '${approxDays(forecast.p90Days)} ${s.daysUnit}'),
            RouteFact(s.patientRouteExpected, routeDate(route.dates.expectedAt)),
            if (doctor != null)
              RouteFact(
                s.patientRouteRefusal,
                doctor.refusalOrgInTraining ? pct(doctor.pRefusal) : refusalWords(s, doctor.pRefusal),
                tone: refusalHigh(doctor.pRefusal) ? StatusTone.danger : null,
              ),
          ]),
          if (todo.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            CardLabel(s.patientRouteTodo),
            const SizedBox(height: AppSpacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(child: Text('•  ', style: theme.textTheme.row)),
                Expanded(child: Text(todo, style: theme.textTheme.row)),
              ],
            ),
            if (doctor!.explanation.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: '${s.patientRouteBasis}: ', style: TextStyle(color: colors.muted)),
                  TextSpan(text: doctor.explanation),
                ]),
                style: theme.textTheme.bodySmall?.merge(AppType.numeric),
              ),
            ],
          ],
          if (factors.isNotEmpty)
            InlineDisclosure(title: s.factorsTitle, child: ForecastFactorList(items: factors, lead: s.factorsLead, note: s.factorsNote)),
          if (target != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(s.benchmarkSentence(days(target.value)), style: theme.textTheme.row),
            InlineDisclosure(
              title: s.sourceLabel,
              style: DisclosureStyle.quiet,
              divider: false,
              child: Text(target.source, style: theme.textTheme.labelSmall),
            ),
          ],
        ],
      ),
    );
  }
}
