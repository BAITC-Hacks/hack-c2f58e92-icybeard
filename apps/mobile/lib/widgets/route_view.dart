import 'package:flutter/material.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../theme/typography.dart';
import 'checklist_tile.dart';
import 'explanation_card.dart';
import 'format.dart';
import 'kpi_tile.dart';
import 'origin_tag.dart';
import 'route_timeline.dart';
import 'section.dart';
import 'status_chip.dart';

/// Общее тело маршрута для гражданина («Мой путь») и врача («Маршрут пациента»). Разделы: организация и стадия,
/// прогноз с ориентиром МЗ РК, этапы Стандарта, анализы со сроками, где быстрее, решения врача, история.
/// В режиме врача добавляется служебная панель (приоритет, флаги, риск отказа, факторы) и кнопки «Направить сюда».
class RouteView extends StatelessWidget {
  const RouteView({super.key, required this.route, this.doctorMode = false, this.onRedirect});

  final PatientRoute route;
  final bool doctorMode;
  final void Function(Alternative alternative)? onRedirect;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final forecastOrigin = route.forecast.fromModel ? Origin.ml : Origin.formula;
    final target = route.targetBenchmark;
    final doctor = route.doctor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(route.synthetic ? s.routeSynthetic(dateShort(route.asOf)) : s.asOfLabel(dateShort(route.asOf)), style: theme.textTheme.labelSmall),
        const SizedBox(height: AppSpacing.md),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(route.organization.profileName, style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(route.organization.moName, style: theme.textTheme.bodySmall),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusChip(s.stageLabel(route.stage), tone: route.stage == RouteCodes.dateAssigned ? StatusTone.accent : StatusTone.neutral, icon: Icons.circle),
                    Text(
                      route.dates.plannedAt != null
                          ? '${s.planLabel}: ${dateShort(route.dates.plannedAt)}'
                          : '${s.registeredAtLabel} ${dateShort(route.dates.registeredAt)} · ${s.waitingFor(route.daysWaiting)}',
                      style: theme.textTheme.bodySmall?.merge(AppType.numeric),
                    ),
                  ],
                ),
                if (doctor != null) ...[
                  const Divider(height: AppSpacing.xl),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      StatusChip('${s.priorityLabel} ${doctor.priority}', tone: StatusTone.accent),
                      for (final flag in doctor.riskFlags) StatusChip(_flagLabel(s, flag), tone: _flagTone(flag)),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text('${s.nextActionLabel}: ${s.nextActionText(doctor.nextActionCode, doctor.nextAction)}', style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ),
        SectionTitle(s.forecastSection, origin: forecastOrigin),
        KpiRow(
          children: [
            KpiTile(value: days(route.forecast.p50Days), label: s.kpiHalfWaits),
            KpiTile(value: days(route.forecast.p90Days), label: s.kpiNineOfTen),
            if (doctor != null)
              KpiTile(value: doctor.refusalOrgInTraining ? pct(doctor.pRefusal) : s.refusalAboveAverage, label: s.riskRefusalLabel)
            else
              KpiTile(value: pct(route.forecast.pWithin30Days), label: s.kpiWithin30),
          ],
        ),
        if (target != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(child: Text(s.benchmarkLine(days(target.value), target.source), style: theme.textTheme.bodySmall)),
              const SizedBox(width: AppSpacing.sm),
              const OriginTag(Origin.formula),
            ],
          ),
        ],
        if (doctor?.shap != null) ...[
          const SizedBox(height: AppSpacing.md),
          ExplanationCard(explanation: doctor!.shap!, model: route.forecast.model),
        ],
        SectionTitle(s.stagesSection, origin: Origin.formula),
        RouteTimeline(stages: route.timeline),
        const SizedBox(height: AppSpacing.xs),
        Text(s.stagesSource, style: theme.textTheme.labelSmall),
        if (route.checklist.isNotEmpty) ...[
          SectionTitle(s.checklistSection, origin: Origin.formula),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
              child: Column(children: [for (final item in route.checklist) ChecklistTile(item)]),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(s.checklistNote, style: theme.textTheme.labelSmall),
        ],
        if (route.alternatives.isNotEmpty) ...[
          SectionTitle(s.fasterSection, origin: Origin.ml),
          Card(
            child: Column(
              children: [
                for (final alternative in route.alternatives)
                  ListTile(
                    title: Text(alternative.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '≈ ${days(alternative.p50Days)} ${s.daysUnit}'
                      '${alternative.distanceKm > 0 ? ' · ${alternative.distanceKm.round()} ${s.kmUnit}' : ''}'
                      '${alternative.isNeighborRegion ? ' · ${s.externalBenchmark}' : ''}',
                      style: theme.textTheme.bodySmall?.merge(AppType.numeric),
                    ),
                    trailing: doctorMode && onRedirect != null
                        ? TextButton(onPressed: () => onRedirect!(alternative), child: Text(s.redirectHere))
                        : null,
                  ),
              ],
            ),
          ),
          if (!doctorMode) ...[const SizedBox(height: AppSpacing.xs), Text(s.redirectOnlyDoctor, style: theme.textTheme.labelSmall)],
        ],
        if (route.decisions.isNotEmpty) ...[
          SectionTitle(s.decisionsSection),
          Card(
            child: Column(
              children: [
                for (final decision in route.decisions)
                  ListTile(
                    leading: Icon(decision.kind == RouteCodes.redirect ? Icons.alt_route : Icons.check_circle_outline, color: colors.accent),
                    title: Text(decision.kind == RouteCodes.redirect ? s.doctorProposed(decision.toMoName) : s.doctorKept),
                    subtitle: Text(
                      [dateTimeShort(decision.recordedAt), if (decision.reason != null && decision.reason!.isNotEmpty) decision.reason!].join(' · '),
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (route.history.isNotEmpty) ...[
          SectionTitle(s.historySection),
          Card(
            child: Column(
              children: [
                for (final item in route.history)
                  ListTile(
                    title: Text('${dateShort(item.registeredAt).substring(6)} · ${item.profileName}', maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(item.moName, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        StatusChip(
                          item.outcome == RouteCodes.refused ? s.outcomeRefused : s.outcomeHospitalized,
                          tone: item.outcome == RouteCodes.refused ? StatusTone.danger : StatusTone.ok,
                        ),
                        Text(s.waitedDays(item.waitDays), style: theme.textTheme.labelSmall?.merge(AppType.numeric)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Text(route.basis, style: theme.textTheme.labelSmall),
      ],
    );
  }

  static String _flagLabel(S s, String flag) => switch (flag) {
        'stuck_over_30' => s.flagOver30,
        'refusal_risk' => s.flagRefusalRisk,
        'faster_alternative' => s.flagFasterAlt,
        _ => flag,
      };

  static StatusTone _flagTone(String flag) => switch (flag) {
        'refusal_risk' => StatusTone.danger,
        'stuck_over_30' => StatusTone.warn,
        _ => StatusTone.accent,
      };
}
