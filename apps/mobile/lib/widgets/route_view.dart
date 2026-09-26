import 'package:flutter/material.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../theme/typography.dart';
import 'format.dart';
import 'org_name.dart';
import 'origin_tag.dart';
import 'route_sections.dart';
import 'stage_stepper.dart';
import 'status_chip.dart';

/// Тело «Мой путь» гражданина: стадия крупно и одна строка прогноза, горизонтальный степпер, организация строкой,
/// карточка «Что сейчас» (валидация ожидания тремя вариантами, ответ врача с «Понятно» или следующий этап),
/// свёрнутые секции с итогом и подвал. Первый экран — без прокрутки.
class RouteView extends StatelessWidget {
  const RouteView({super.key, required this.route, this.onSignal, this.onRequest, this.onAcknowledge, this.seenDecisionId});

  final PatientRoute route;

  /// Ответ на «Вы ещё ждёте?» (still_waiting | treated_elsewhere | withdraw).
  final void Function(String kind)? onSignal;

  /// Попросить врача рассмотреть организацию из «Где быстрее».
  final void Function(Alternative alternative)? onRequest;

  /// «Понятно» под ответом врача — карточка больше не повторяется.
  final VoidCallback? onAcknowledge;
  final String? seenDecisionId;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final f = route.forecast;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.stageLabel(route.stage), style: theme.textTheme.headlineSmall),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            Expanded(child: Text('${s.nineOfTenShort(days(f.p90Days))} · ${s.halfShort(days(f.p50Days))}', style: theme.textTheme.bodyMedium?.merge(AppType.numeric))),
            const SizedBox(width: AppSpacing.sm),
            OriginTag(f.fromModel ? Origin.ml : Origin.formula),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        StageStepper(stages: route.timeline),
        const SizedBox(height: AppSpacing.md),
        OrgName(route.organization.moName, prefix: '${route.organization.profileName} · ', maxLines: 2),
        const SizedBox(height: AppSpacing.lg),
        _WhatNowCard(route: route, onSignal: onSignal, onAcknowledge: onAcknowledge, seenDecisionId: seenDecisionId),
        const SizedBox(height: AppSpacing.md),
        ChecklistSection(route: route),
        const SizedBox(height: AppSpacing.sm),
        FasterSection(route: route, trailing: (a) => _requestAction(s, a), note: onRequest == null ? null : s.redirectOnlyDoctor),
        const SizedBox(height: AppSpacing.sm),
        ForecastDetailsSection(route: route),
        const SizedBox(height: AppSpacing.sm),
        SignalsSection(route: route),
        const SizedBox(height: AppSpacing.sm),
        HistorySection(route: route),
        const SizedBox(height: AppSpacing.lg),
        Text('${s.routeSynthetic(dateShort(route.asOf))} · ${s.standardShort}', style: theme.textTheme.labelSmall),
      ],
    );
  }

  /// «Попросить» у альтернативы; по уже запрошенной организации — чип «запрос отправлен», остальные кнопки
  /// заблокированы, пока врач не ответил.
  Widget? _requestAction(S s, Alternative alternative) {
    if (onRequest == null) {
      return null;
    }
    final open = route.openRequest;
    if (open?.toMoCode == alternative.moCode) {
      return StatusChip(s.requestPending, tone: StatusTone.accent);
    }
    return TextButton(onPressed: open != null ? null : () => onRequest!(alternative), child: Text(s.requestConsider));
  }
}

class _WhatNowCard extends StatelessWidget {
  const _WhatNowCard({required this.route, this.onSignal, this.onAcknowledge, this.seenDecisionId});

  final PatientRoute route;
  final void Function(String kind)? onSignal;
  final VoidCallback? onAcknowledge;
  final String? seenDecisionId;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final answer = route.latestDecision;
    final unseenAnswer = answer != null && onAcknowledge != null && answer.decisionId != seenDecisionId;
    final Widget body;
    if (route.validationDue && onSignal != null) {
      body = _Validation(onSignal: onSignal!);
    } else if (unseenAnswer) {
      body = _DoctorAnswer(decision: answer, onAcknowledge: onAcknowledge!);
    } else {
      body = _NextStep(route: route);
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(route.validationDue && onSignal != null ? s.validationTitle : unseenAnswer ? s.doctorAnswerTitle : s.whatNow, style: theme.textTheme.titleMedium)),
                if (route.openRequest != null && !unseenAnswer) StatusChip(s.awaitingDoctor, tone: StatusTone.accent),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            body,
          ],
        ),
      ),
    );
  }
}

/// Вопрос «Вы ещё ждёте?» тремя вариантами-карточками.
class _Validation extends StatelessWidget {
  const _Validation({required this.onSignal});

  final void Function(String kind) onSignal;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(s.validationBody, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: AppSpacing.md),
        _OptionCard(label: s.validationStill, icon: Icons.check_circle_outline, primary: true, onTap: () => onSignal(RouteCodes.stillWaiting)),
        const SizedBox(height: AppSpacing.sm),
        _OptionCard(label: s.validationTreated, icon: Icons.local_hospital_outlined, onTap: () => onSignal(RouteCodes.treatedElsewhere)),
        const SizedBox(height: AppSpacing.sm),
        _OptionCard(label: s.validationWithdraw, icon: Icons.close, onTap: () => onSignal(RouteCodes.withdraw)),
      ],
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({required this.label, required this.icon, required this.onTap, this.primary = false});

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          decoration: BoxDecoration(
            color: primary ? colors.accentSoft : colors.card,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: primary ? colors.accent : colors.hairline),
          ),
          child: Row(
            children: [
              Icon(icon, color: primary ? colors.accent : colors.muted),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: Text(label, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: primary ? FontWeight.w600 : FontWeight.w400))),
            ],
          ),
        ),
      ),
    );
  }
}

class _DoctorAnswer extends StatelessWidget {
  const _DoctorAnswer({required this.decision, required this.onAcknowledge});

  final RouteDecision decision;
  final VoidCallback onAcknowledge;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final reason = decision.reason;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(decision.kind == RouteCodes.redirect ? s.doctorProposed(shortOrgName(decision.toMoName)) : s.doctorKept, style: theme.textTheme.bodyLarge),
        if (reason != null && reason.isNotEmpty) ...[const SizedBox(height: AppSpacing.xs), Text('«$reason»', style: theme.textTheme.bodySmall)],
        const SizedBox(height: AppSpacing.xs),
        Text(dateTimeShort(decision.recordedAt), style: theme.textTheme.labelSmall?.merge(AppType.numeric)),
        const SizedBox(height: AppSpacing.md),
        FilledButton.tonal(onPressed: onAcknowledge, child: Text(s.gotIt)),
      ],
    );
  }
}

/// Следующий этап и норма срока; при назначенной дате — «Дата назначена 31.03.2025».
class _NextStep extends StatelessWidget {
  const _NextStep({required this.route});

  final PatientRoute route;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final next = route.nextStage;
    final planned = route.dates.plannedAt;
    final String title;
    String? norm;
    if (route.stage == RouteCodes.dateAssigned && planned != null) {
      title = s.dateAssignedOn(dateShort(planned));
      norm = next?.norm;
    } else if (next != null) {
      title = s.nextStage(next.title);
      norm = next.norm ?? (route.stage == RouteCodes.waitlisted ? s.waitingForDate : null);
    } else {
      title = s.stageLabel(route.stage);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.bodyLarge?.merge(AppType.numeric)),
        if (norm != null && norm.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(norm, style: theme.textTheme.bodySmall, maxLines: 3, overflow: TextOverflow.ellipsis),
        ],
      ],
    );
  }
}
