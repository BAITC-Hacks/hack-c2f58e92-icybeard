import 'package:flutter/material.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../theme/typography.dart';
import 'alternative_row.dart';
import 'checklist_tile.dart';
import 'collapsible_section.dart';
import 'format.dart';
import 'kpi_tile.dart';
import 'org_name.dart';
import 'origin_tag.dart';
import 'route_timeline.dart';
import 'status_chip.dart';

/// Свёрнутые секции маршрута, общие для «Мой путь» (гражданин) и «Маршрут пациента» (врач). Каждая — строка с
/// итогом, раскрывается по тапу; метка происхождения одна на секцию.
class ChecklistSection extends StatelessWidget {
  const ChecklistSection({super.key, required this.route});

  final PatientRoute route;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    if (route.checklist.isEmpty) {
      return const SizedBox.shrink();
    }
    return CollapsibleSection(
      title: s.checklistSection,
      summary: s.checklistSummary(route.expiredChecklistCount, route.validChecklistCount),
      origin: Origin.formula,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in route.checklist) ChecklistTile(item),
          const SizedBox(height: AppSpacing.xs),
          Text(s.checklistNote, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class FasterSection extends StatelessWidget {
  const FasterSection({super.key, required this.route, required this.trailing, this.showRisk = false, this.note});

  final PatientRoute route;
  final Widget? Function(Alternative alternative) trailing;
  final bool showRisk;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final first = route.alternatives.firstOrNull;
    return CollapsibleSection(
      title: s.fasterSection,
      summary: first == null ? s.noQueuesInRegion : s.fasterSummary(shortOrgName(first.name), days(first.p50Days)),
      origin: Origin.ml,
      padded: false,
      child: first == null
          ? Padding(padding: const EdgeInsets.all(AppSpacing.lg), child: Text(s.noQueuesInRegion, style: theme.textTheme.bodySmall))
          : Column(
              children: [
                for (final (i, alternative) in route.alternatives.indexed) ...[
                  if (i > 0) const Divider(),
                  AlternativeRow(alternative: alternative, showRisk: showRisk, trailing: trailing(alternative)),
                ],
                if (note != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xs, AppSpacing.lg, AppSpacing.md),
                    child: Align(alignment: Alignment.centerLeft, child: Text(note!, style: theme.textTheme.labelSmall)),
                  ),
              ],
            ),
    );
  }
}

class ForecastDetailsSection extends StatelessWidget {
  const ForecastDetailsSection({super.key, required this.route});

  final PatientRoute route;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final f = route.forecast;
    final target = route.targetBenchmark;
    final model = f.model;
    return CollapsibleSection(
      title: s.forecastDetails,
      summary: '${days(f.p50Days)} / ${days(f.p90Days)} ${s.daysUnit}',
      origin: f.fromModel ? Origin.ml : Origin.formula,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KpiRow(
            children: [
              KpiTile(value: days(f.p50Days), label: s.kpiHalfWaits),
              KpiTile(value: days(f.p90Days), label: s.kpiNineOfTen),
              KpiTile(value: pct(f.pWithin30Days), label: s.kpiWithin30),
            ],
          ),
          if (!f.fromModel) ...[const SizedBox(height: AppSpacing.sm), Text(s.modelUnavailableNote, style: theme.textTheme.labelSmall)],
          if (target != null) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(child: Text(s.benchmarkShort(days(target.value)), style: theme.textTheme.bodySmall?.merge(AppType.numeric))),
                const SizedBox(width: AppSpacing.sm),
                const OriginTag(Origin.formula),
              ],
            ),
          ],
          if (model != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(s.modelTrained(model.name, model.version, model.trainedThrough), style: theme.textTheme.labelSmall),
          ],
        ],
      ),
    );
  }
}

/// Решения врача и сигналы гражданина одной лентой, свежие первыми (ISO-даты сравниваются как строки).
class SignalsSection extends StatelessWidget {
  const SignalsSection({super.key, required this.route, this.doctorMode = false});

  final PatientRoute route;
  final bool doctorMode;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final colors = AppPalette.of(context);
    final rows = _entries(s);
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }
    return CollapsibleSection(
      title: s.signalsSection,
      summary: '${rows.length}',
      padded: false,
      child: Column(
        children: [
          for (final (i, entry) in rows.indexed) ...[
            if (i > 0) const Divider(),
            ListTile(
              leading: Icon(entry.icon, color: colors.accent),
              title: Text(entry.title, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(entry.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
          ],
        ],
      ),
    );
  }

  List<_Entry> _entries(S s) {
    final rows = <_Entry>[
      for (final d in route.decisions)
        _Entry(
          d.recordedAt,
          d.kind == RouteCodes.redirect ? s.doctorProposed(shortOrgName(d.toMoName)) : s.doctorKept,
          [dateTimeShort(d.recordedAt), if (d.reason != null && d.reason!.isNotEmpty) '«${d.reason}»'].join(' · '),
          d.kind == RouteCodes.redirect ? Icons.alt_route : Icons.check_circle_outline,
        ),
      for (final x in route.signals)
        _Entry(
          x.recordedAt,
          doctorMode
              ? s.patientSignalText(x.kind, x.toMoName == null ? null : shortOrgName(x.toMoName!))
              : s.signalText(x.kind, x.toMoName == null ? null : shortOrgName(x.toMoName!)),
          [dateTimeShort(x.recordedAt), if (x.comment != null && x.comment!.isNotEmpty) '«${x.comment}»', if (x.open) s.awaitingDoctor].join(' · '),
          Icons.record_voice_over_outlined,
        ),
    ];
    rows.sort((a, b) => b.at.compareTo(a.at));
    return rows;
  }
}

class _Entry {
  const _Entry(this.at, this.title, this.subtitle, this.icon);

  final String at;
  final String title;
  final String subtitle;
  final IconData icon;
}

class HistorySection extends StatelessWidget {
  const HistorySection({super.key, required this.route});

  final PatientRoute route;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    if (route.history.isEmpty) {
      return const SizedBox.shrink();
    }
    return CollapsibleSection(
      title: s.pastReferrals,
      summary: '${route.history.length}',
      padded: false,
      child: Column(
        children: [
          for (final (i, item) in route.history.indexed) ...[
            if (i > 0) const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${dateShort(item.registeredAt)} · ${item.profileName}', style: theme.textTheme.bodyMedium?.merge(AppType.numeric), maxLines: 2, overflow: TextOverflow.ellipsis),
                        OrgName(item.moName, maxLines: 1),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      StatusChip(
                        item.outcome == RouteCodes.refused ? s.outcomeRefused : s.outcomeHospitalized,
                        tone: item.outcome == RouteCodes.refused ? StatusTone.danger : StatusTone.ok,
                      ),
                      Text(s.waitedDays(item.waitDays), style: theme.textTheme.labelSmall?.merge(AppType.numeric)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Этапы вертикальной лентой (врач): свёрнуто, итог — текущая стадия.
class StagesSection extends StatelessWidget {
  const StagesSection({super.key, required this.route});

  final PatientRoute route;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    return CollapsibleSection(
      title: s.stagesSection,
      summary: s.stageLabel(route.stage),
      origin: Origin.formula,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RouteTimeline(stages: route.timeline),
          const SizedBox(height: AppSpacing.sm),
          Text(s.stagesSource, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}
