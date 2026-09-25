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
  const RouteView({super.key, required this.route, this.doctorMode = false, this.onRedirect, this.onSignal, this.onRequest, this.onKeep});

  final PatientRoute route;
  final bool doctorMode;
  final void Function(Alternative alternative)? onRedirect;

  /// Гражданин: ответ на «Вы ещё ждёте?» (still_waiting | treated_elsewhere | withdraw).
  final void Function(String kind)? onSignal;

  /// Гражданин: попросить врача рассмотреть организацию из списка «где быстрее».
  final void Function(Alternative alternative)? onRequest;

  /// Врач: оставить в текущей организации с причиной — ответ на сигнал пациента.
  final VoidCallback? onKeep;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final forecastOrigin = route.forecast.fromModel ? Origin.ml : Origin.formula;
    final target = route.targetBenchmark;
    final doctor = route.doctor;
    final entries = _entries(s);
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
        if (doctorMode && route.openSignal != null) ...[
          const SizedBox(height: AppSpacing.md),
          _SignalBanner(route: route, onRedirect: onRedirect, onKeep: onKeep),
        ],
        if (!doctorMode && route.validationDue && onSignal != null) ...[
          const SizedBox(height: AppSpacing.md),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.validationTitle, style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text(s.validationBody, style: theme.textTheme.bodySmall),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton(onPressed: () => onSignal!(RouteCodes.stillWaiting), child: Text(s.validationStill)),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton(onPressed: () => onSignal!(RouteCodes.treatedElsewhere), child: Text(s.validationTreated)),
                  const SizedBox(height: AppSpacing.xs),
                  TextButton(onPressed: () => onSignal!(RouteCodes.withdraw), child: Text(s.validationWithdraw)),
                ],
              ),
            ),
          ),
        ],
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
                    trailing: _alternativeAction(s, alternative),
                  ),
              ],
            ),
          ),
          if (!doctorMode) ...[const SizedBox(height: AppSpacing.xs), Text(s.redirectOnlyDoctor, style: theme.textTheme.labelSmall)],
        ],
        if (entries.isNotEmpty) ...[
          SectionTitle(s.signalsSection),
          Card(
            child: Column(
              children: [
                for (final entry in entries)
                  ListTile(
                    leading: Icon(entry.icon, color: colors.accent),
                    title: Text(entry.title),
                    subtitle: Text(entry.subtitle),
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

  /// Кнопка у альтернативы: врач — «Направить сюда»; гражданин — «Попросить», а если запрос по этой организации уже
  /// открыт — чип «запрос отправлен».
  Widget? _alternativeAction(S s, Alternative alternative) {
    if (doctorMode) {
      return onRedirect == null ? null : TextButton(onPressed: () => onRedirect!(alternative), child: Text(s.redirectHere));
    }
    if (onRequest == null) {
      return null;
    }
    if (route.openRequest?.toMoCode == alternative.moCode) {
      return StatusChip(s.requestPending, tone: StatusTone.accent);
    }
    return TextButton(onPressed: () => onRequest!(alternative), child: Text(s.requestConsider));
  }

  /// Решения врача и сигналы гражданина одной лентой, свежие первыми (ISO-даты сравниваются как строки).
  List<_Entry> _entries(S s) {
    final rows = <_Entry>[
      for (final d in route.decisions)
        _Entry(
          d.recordedAt,
          d.kind == RouteCodes.redirect ? s.doctorProposed(d.toMoName) : s.doctorKept,
          [dateTimeShort(d.recordedAt), if (d.reason != null && d.reason!.isNotEmpty) d.reason!].join(' · '),
          d.kind == RouteCodes.redirect ? Icons.alt_route : Icons.check_circle_outline,
        ),
      for (final x in route.signals)
        _Entry(
          x.recordedAt,
          doctorMode ? s.patientSignalText(x.kind, x.toMoName) : s.signalText(x.kind, x.toMoName),
          [dateTimeShort(x.recordedAt), if (x.comment != null && x.comment!.isNotEmpty) x.comment!, if (x.open) s.awaitingDoctor].join(' · '),
          Icons.record_voice_over_outlined,
        ),
    ];
    rows.sort((a, b) => b.at.compareTo(a.at));
    return rows;
  }

  static String _flagLabel(S s, String flag) => switch (flag) {
        'stuck_over_30' => s.flagOver30,
        'refusal_risk' => s.flagRefusalRisk,
        'faster_alternative' => s.flagFasterAlt,
        'patient_signal' => s.flagPatientSignal,
        _ => flag,
      };

  static StatusTone _flagTone(String flag) => switch (flag) {
        'refusal_risk' => StatusTone.danger,
        'stuck_over_30' => StatusTone.warn,
        _ => StatusTone.accent,
      };
}

class _Entry {
  const _Entry(this.at, this.title, this.subtitle, this.icon);

  final String at;
  final String title;
  final String subtitle;
  final IconData icon;
}

/// Баннер врача: открытый сигнал пациента с двумя действиями — «Направить сюда» (если просимая организация есть
/// среди альтернатив) и «Оставить» с причиной. Оба пишут решение в журнал и закрывают сигнал.
class _SignalBanner extends StatelessWidget {
  const _SignalBanner({required this.route, this.onRedirect, this.onKeep});

  final PatientRoute route;
  final void Function(Alternative alternative)? onRedirect;
  final VoidCallback? onKeep;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final signal = route.openSignal!;
    final requested = route.alternatives.where((a) => a.moCode == signal.toMoCode).firstOrNull;
    return Card(
      color: colors.accentSoft,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.record_voice_over_outlined, color: colors.accent),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(s.patientSignalText(signal.kind, signal.toMoName), style: theme.textTheme.titleSmall)),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              [dateTimeShort(signal.recordedAt), if (signal.comment != null && signal.comment!.isNotEmpty) '«${signal.comment}»'].join(' · '),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                if (requested != null && onRedirect != null) ...[
                  Expanded(child: FilledButton(onPressed: () => onRedirect!(requested), child: Text(s.redirectHere))),
                  const SizedBox(width: AppSpacing.sm),
                ],
                if (onKeep != null) Expanded(child: OutlinedButton(onPressed: onKeep, child: Text(s.keepHere))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
