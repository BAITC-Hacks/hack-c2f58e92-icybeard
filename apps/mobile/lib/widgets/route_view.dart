import 'package:flutter/material.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'app_card.dart';
import 'format.dart';
import 'org_name.dart';
import 'origin_tag.dart';
import 'route_sections.dart';
import 'route_timeline.dart';
import 'signal_card.dart';
import 'stage_stepper.dart';
import 'status_chip.dart';

/// Тело «Мой путь» гражданина: hero-карточка (этап k из n, чип стадии, «до N дн. до госпитализации», строка
/// «Половина — a дн., 9 из 10 — до b дн.», организация), карточка этапов (полосы + строки 56 px), вопрос «Вы ещё
/// ждёте?», ответ врача карточкой-сигналом (пока не нажато «Понятно») или «Что сейчас», свёрнутые секции и подвал.
/// Кнопка «Понятно» живёт в нижней зоне экрана.
class RouteView extends StatelessWidget {
  const RouteView({super.key, required this.route, this.onSignal, this.onRequest, this.seenDecisionId, this.onOpenAnswer});

  final PatientRoute route;

  /// Ответ на «Вы ещё ждёте?» (still_waiting | treated_elsewhere | withdraw).
  final void Function(String kind)? onSignal;

  /// Попросить врача рассмотреть организацию из «Где быстрее».
  final void Function(Alternative alternative)? onRequest;

  /// Решение, которое гражданин уже закрыл кнопкой «Понятно»: карточка-сигнал не повторяется.
  final String? seenDecisionId;

  /// Тап по карточке-сигналу «Врач предложил …».
  final VoidCallback? onOpenAnswer;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final answer = route.latestDecision;
    final unseen = answer != null && answer.decisionId != seenDecisionId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HeroCard(route: route),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xs),
          child: Column(
            children: [
              StageStepper(stages: route.timeline, compact: true),
              const SizedBox(height: AppSpacing.sm),
              RouteTimeline(stages: route.timeline),
            ],
          ),
        ),
        if (route.validationDue && onSignal != null) ...[const SizedBox(height: AppSpacing.md), _Validation(onSignal: onSignal!)],
        const SizedBox(height: AppSpacing.md),
        if (unseen) _DoctorAnswer(decision: answer, onTap: onOpenAnswer) else _WhatNowCard(route: route),
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
      return StatusChip(s.requestPending, tone: StatusTone.neutral);
    }
    return TextButton(onPressed: open != null ? null : () => onRequest!(alternative), child: Text(s.requestConsider));
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.route});

  final PatientRoute route;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final f = route.forecast;
    final ordered = [...route.timeline]..sort((a, b) => a.order.compareTo(b.order));
    final step = ordered.indexWhere((x) => x.status == RouteCodes.current) + 1;
    final hero = s.heroUntil(days(f.p90Days));
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardLabel(
            step > 0 ? s.stageOf(step, ordered.length) : s.stagesSection,
            trailing: StatusChip(s.stageLabel(route.stage), tone: route.stage == RouteCodes.dateAssigned ? StatusTone.ok : StatusTone.neutral),
          ),
          const SizedBox(height: AppSpacing.md),
          HeroNumberInline(value: hero.$1, unit: hero.$2),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              OriginTag(f.fromModel ? Origin.ml : Origin.formula),
              const SizedBox(width: 10),
              Expanded(child: Text(s.forecastLine(days(f.p50Days), days(f.p90Days)), style: theme.textTheme.bodySmall?.merge(AppType.numeric), maxLines: 2)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          OrgName(route.organization.moName, prefix: '${route.organization.profileName} · ', maxLines: 2, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Hero-число с единицей в одну строку (без label — он в CardLabel выше).
class HeroNumberInline extends StatelessWidget {
  const HeroNumberInline({super.key, required this.value, required this.unit});

  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(
          child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: theme.textTheme.displayLarge?.merge(AppType.numeric))),
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(child: Text(unit, style: theme.textTheme.bodySmall?.copyWith(fontSize: 17), maxLines: 2)),
      ],
    );
  }
}

/// Вопрос «Вы ещё ждёте?» тремя кнопками: primary «Да, жду», остальные — secondary.
class _Validation extends StatelessWidget {
  const _Validation({required this.onSignal});

  final void Function(String kind) onSignal;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    return AppCard(
      padding: AppCard.plain,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s.validationTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(s.validationBody, style: theme.textTheme.bodySmall),
          const SizedBox(height: AppSpacing.md),
          FilledButton(onPressed: () => onSignal(RouteCodes.stillWaiting), child: Text(s.validationStill)),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(onPressed: () => onSignal(RouteCodes.treatedElsewhere), child: Text(s.validationTreated)),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(onPressed: () => onSignal(RouteCodes.withdraw), child: Text(s.validationWithdraw)),
        ],
      ),
    );
  }
}

/// Ответ врача карточкой-сигналом: «Врач предложил Достар Мед · «ожидание короче» · 26.09.2026 00:26 →».
class _DoctorAnswer extends StatelessWidget {
  const _DoctorAnswer({required this.decision, this.onTap});

  final RouteDecision decision;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final reason = decision.reason;
    return SignalCard(
      title: decision.kind == RouteCodes.redirect ? s.doctorProposed(shortOrgName(decision.toMoName)) : s.doctorKept,
      subtitle: [if (reason != null && reason.isNotEmpty) '«$reason»', dateTimeShort(decision.recordedAt)].join(' · '),
      onTap: decision.kind == RouteCodes.redirect ? onTap : null,
    );
  }
}

/// «Что сейчас»: следующий этап и норма срока; при назначенной дате — «Дата назначена 31.03.2025»; чип «ждёт
/// ответа врача», пока открыт запрос.
class _WhatNowCard extends StatelessWidget {
  const _WhatNowCard({required this.route});

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
    return AppCard(
      padding: AppCard.plain,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(s.whatNow, style: theme.textTheme.titleMedium)),
              if (route.openRequest != null) StatusChip(s.awaitingDoctor, tone: StatusTone.neutral),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(title, style: theme.textTheme.row.merge(AppType.numeric)),
          if (norm != null && norm.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(norm, style: theme.textTheme.bodySmall, maxLines: 3, overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }
}
