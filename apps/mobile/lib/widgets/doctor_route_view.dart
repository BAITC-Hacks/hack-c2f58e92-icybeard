import 'package:flutter/material.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import 'collapsible_section.dart';
import 'explanation_card.dart';
import 'format.dart';
import 'kpi_tile.dart';
import 'org_name.dart';
import 'origin_tag.dart';
import 'route_sections.dart';
import 'section.dart';
import 'stage_stepper.dart';
import 'status_chip.dart';

/// Тело «Маршрут пациента» для врача: подстрока «профиль · организация», панель врача первой (чип стадии и
/// степпер, приоритет и флаги, следующий шаг одной фразой), карточка открытого сигнала с полем причины, прогноз
/// тремя плитками [ML] и «Почему так» свёрнуто, свёрнутые секции. Риск отказа показывается только здесь.
class DoctorRouteView extends StatelessWidget {
  const DoctorRouteView({super.key, required this.route, this.busy = false, this.onRedirect, this.onKeep});

  final PatientRoute route;
  final bool busy;

  /// Перенаправление: с причиной из карточки сигнала или без неё (экран спросит листом).
  final void Function(Alternative alternative, {String? reason})? onRedirect;

  /// «Оставить» с причиной — ответ на сигнал пациента.
  final void Function(String reason)? onKeep;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final doctor = route.doctor;
    final f = route.forecast;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OrgName(route.organization.moName, prefix: '${route.organization.profileName} · ', maxLines: 2),
        const SizedBox(height: AppSpacing.md),
        _DoctorPanel(route: route),
        if (route.openSignal != null) ...[
          const SizedBox(height: AppSpacing.md),
          _SignalCard(route: route, busy: busy, onRedirect: onRedirect, onKeep: onKeep),
        ],
        SectionTitle(s.forecastSection, origin: f.fromModel ? Origin.ml : Origin.formula),
        KpiRow(
          children: [
            KpiTile(value: days(f.p50Days), label: s.kpiHalfWaits),
            KpiTile(value: days(f.p90Days), label: s.kpiNineOfTen),
            KpiTile(
              value: doctor == null ? pct(f.pWithin30Days) : (doctor.refusalOrgInTraining ? pct(doctor.pRefusal) : s.refusalAboveAverage),
              label: doctor == null ? s.kpiWithin30 : s.riskRefusalLabel,
            ),
          ],
        ),
        if (!f.fromModel) ...[const SizedBox(height: AppSpacing.xs), Text(s.modelUnavailableNote, style: theme.textTheme.labelSmall)],
        if (doctor != null && !doctor.refusalOrgInTraining) ...[const SizedBox(height: AppSpacing.xs), Text(s.refusalOrgUnknownNote, style: theme.textTheme.labelSmall)],
        if (doctor?.shap != null) ...[
          const SizedBox(height: AppSpacing.sm),
          CollapsibleSection(
            title: s.whySo,
            summary: '${doctor!.shap!.factors.length}',
            child: FactorList(explanation: doctor.shap!, model: f.model),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        ChecklistSection(route: route),
        const SizedBox(height: AppSpacing.sm),
        FasterSection(
          route: route,
          showRisk: true,
          trailing: (a) => onRedirect == null ? null : TextButton(onPressed: busy ? null : () => onRedirect!(a), child: Text(s.referButton)),
        ),
        const SizedBox(height: AppSpacing.sm),
        StagesSection(route: route),
        const SizedBox(height: AppSpacing.sm),
        SignalsSection(route: route, doctorMode: true),
        const SizedBox(height: AppSpacing.sm),
        HistorySection(route: route),
        const SizedBox(height: AppSpacing.lg),
        Text(route.basis, style: theme.textTheme.labelSmall),
      ],
    );
  }
}

class _DoctorPanel extends StatelessWidget {
  const _DoctorPanel({required this.route});

  final PatientRoute route;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final doctor = route.doctor;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Align(alignment: Alignment.centerLeft, child: StatusChip(s.stageLabel(route.stage), tone: route.stage == RouteCodes.dateAssigned ? StatusTone.accent : StatusTone.neutral))),
                if (doctor != null) StatusChip('${s.priorityLabel} ${doctor.priority}', tone: StatusTone.accent),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            StageStepper(stages: route.timeline),
            if (doctor != null && doctor.riskFlags.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Wrap(spacing: AppSpacing.xs, runSpacing: AppSpacing.xs, children: [for (final flag in doctor.riskFlags) StatusChip(s.flagShort(flag), tone: _flagTone(flag))]),
            ],
            if (doctor != null) ...[
              const SizedBox(height: AppSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.arrow_forward, size: 18, color: colors.accent),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text('${s.nextActionLabel}: ${s.nextActionText(doctor.nextActionCode, doctor.nextAction)}', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static StatusTone _flagTone(String flag) => switch (flag) {
        'refusal_risk' => StatusTone.danger,
        'stuck_over_30' => StatusTone.warn,
        _ => StatusTone.accent,
      };
}

/// Открытый сигнал пациента: «Пациент просит Достар Мед», комментарий, поле причины и два действия — оба пишут
/// решение в журнал и закрывают сигнал.
class _SignalCard extends StatefulWidget {
  const _SignalCard({required this.route, required this.busy, this.onRedirect, this.onKeep});

  final PatientRoute route;
  final bool busy;
  final void Function(Alternative alternative, {String? reason})? onRedirect;
  final void Function(String reason)? onKeep;

  @override
  State<_SignalCard> createState() => _SignalCardState();
}

class _SignalCardState extends State<_SignalCard> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final signal = widget.route.openSignal!;
    final requested = widget.route.alternatives.where((a) => a.moCode == signal.toMoCode).firstOrNull;
    final title = signal.kind == RouteCodes.requestRedirect
        ? s.patientAsksTitle(shortOrgName(signal.toMoName ?? signal.toMoCode ?? ''))
        : s.patientSignalText(signal.kind, null);
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
                Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              [dateTimeShort(signal.recordedAt), if (signal.comment != null && signal.comment!.isNotEmpty) '«${signal.comment}»'].join(' · '),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _reason,
              builder: (_, value, _) {
                final canAct = !widget.busy && value.text.trim().isNotEmpty;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(controller: _reason, maxLines: 2, decoration: InputDecoration(labelText: s.keepReasonLabel)),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        if (requested != null && widget.onRedirect != null) ...[
                          Expanded(child: FilledButton(onPressed: canAct ? () => widget.onRedirect!(requested, reason: value.text.trim()) : null, child: Text(s.redirectHere))),
                          const SizedBox(width: AppSpacing.sm),
                        ],
                        if (widget.onKeep != null)
                          Expanded(child: OutlinedButton(onPressed: canAct ? () => widget.onKeep!(value.text.trim()) : null, child: Text(s.keepHere))),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
