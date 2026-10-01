import 'package:flutter/material.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../theme/tokens.dart';
import 'collapsible_section.dart';
import 'doctor/decision_card.dart';
import 'doctor/hospital_card.dart';
import 'doctor/past_referrals.dart';
import 'doctor/route_action.dart';
import 'doctor/route_header.dart';
import 'doctor/transfer_card.dart';
import 'format.dart';
import 'origin_tag.dart';
import 'route/checklist_groups.dart';
import 'route/route_journal.dart';
import 'route/stage_list.dart';
import 'status_chip.dart';

/// Тело «Маршрута пациента» для врача (веб W-Patient), одной колонкой: шапка (пациент, приоритет, статус, больница,
/// факты) → решение «Оставить или перевести», если сервер разрешил `keep`/`redirect`, иначе карточка «Перевод» →
/// «Текущая больница» (прогноз, риск отказа, что сделать, факторы) → этапы маршрута → журнал «Решения и запросы»
/// голосом персонала → «Анализы» → прошлые направления → сноска о синтетическом маршруте. Решение выше прогноза:
/// главное действие врача — на первом экране телефона. Действия выполняет экран ([onAction]).
class DoctorRouteView extends StatelessWidget {
  const DoctorRouteView({
    super.key,
    required this.route,
    required this.onAction,
    this.busy = false,
    this.acting,
    this.regionNames = const {},
    this.onRecordVisit,
    this.onAssistant,
    this.onOpenIncoming,
  });

  final PatientRoute route;
  final DoctorRouteActionHandler onAction;

  /// Действие в полёте: все кнопки решений выключены.
  final bool busy;

  /// Код действия в полёте (индикатор на его кнопке).
  final String? acting;
  final Map<String, String> regionNames;

  /// Скрайб этого пациента; null — кнопки «Записать приём» нет.
  final VoidCallback? onRecordVisit;

  /// Ассистент для нового направления; null — ссылки нет.
  final VoidCallback? onAssistant;

  /// Вкладка «Входящие» для принимающей стороны.
  final VoidCallback? onOpenIncoming;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final decide = route.can(RouteCodes.actionKeep) || route.can(RouteCodes.actionRedirect);
    final current = route.timeline.where((stage) => stage.status == RouteCodes.current).firstOrNull;
    final done = route.timeline.where((stage) => stage.status == RouteCodes.done).length;
    final expired = route.expiredChecklistCount;
    const gap = SizedBox(height: AppSpacing.md);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PatientRouteHeader(route: route, onRecordVisit: onRecordVisit),
        if (decide) ...[
          gap,
          DecisionCard(route: route, onAction: onAction, busy: busy, acting: acting, regionNames: regionNames, onAssistant: onAssistant),
        ] else if (route.progress != null) ...[
          gap,
          TransferCard(route: route, onAction: onAction, busy: busy, acting: acting, onOpenIncoming: onOpenIncoming),
        ],
        gap,
        CurrentHospitalCard(route: route),
        if (route.timeline.isNotEmpty) ...[
          gap,
          CollapsibleSection(
            title: s.routeStagesTitle,
            summary: current?.title ?? s.routeStagesCount(route.timeline.length, done),
            origin: Origin.formula,
            child: StageList(stages: route.timeline),
          ),
        ],
        gap,
        CollapsibleSection(
          title: s.routeJournalHeading,
          summary: '${route.journal.length}',
          initiallyExpanded: true,
          child: RouteJournal(entries: route.journal, voice: RouteVoice.staff),
        ),
        if (route.checklist.isNotEmpty) ...[
          gap,
          CollapsibleSection(
            title: s.checklistSection,
            summary: s.routeChecklistSummary(expired, route.validChecklistCount),
            summaryTone: expired > 0 ? StatusTone.danger : null,
            origin: Origin.formula,
            child: ChecklistGroups(items: route.checklist, standard: route.standard),
          ),
        ],
        if (route.history.isNotEmpty) ...[gap, PastReferralsSection(history: route.history)],
        const SizedBox(height: AppSpacing.lg),
        Text(
          [if (route.basis.trim().isNotEmpty) route.basis.trim(), s.patientRouteSynthetic(routeDate(route.asOf))].join(' · '),
          style: theme.textTheme.labelSmall,
        ),
      ],
    );
  }
}
