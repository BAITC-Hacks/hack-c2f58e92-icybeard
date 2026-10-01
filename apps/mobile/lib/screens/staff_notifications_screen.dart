import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/session.dart';
import '../state/staff_bell_notifier.dart';
import '../widgets/app_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_box.dart';
import '../widgets/format.dart';
import '../widgets/incoming/incoming_links.dart';
import '../widgets/incoming/staff_bell_row.dart';
import '../widgets/route/route_journal.dart';
import '../widgets/section.dart';
import '../widgets/skeleton.dart';
import '../widgets/state_view.dart';

/// Уведомления персонала — `/doctor/notifications` вне вкладок (Q-1), открывается кнопкой-колокольчиком рабочего
/// списка (`push`: «назад» возвращает к списку). Данные — [StaffBellNotifier] над приложением (опрос раз в минуту, при
/// открытии — сразу), как поповер колокольчика веба, но целым экраном:
/// - «Ожидают подтверждения: N» → вкладка «Входящие»;
/// - «Направление в {больница} подтверждено» и «Пациент выписан из {больница}, эпикриз готов» с текстом эпикриза
///   прямо в пункте → маршрут пациента (Q-7: на входящих отправителю смотреть нечего);
/// - события пациентов моей больницы (запросы, ответ на перевод, ответ на запрос записи приёма) с комментарием →
///   маршрут пациента; ответ на запрос записи приёма — скрайб этого пациента, как в вебе, если скрайб пользователю
///   доступен (`scribe.use`).
/// Нажатие отмечает пункт прочитанным (он сразу исчезает, счётчики следуют) и уходит на экран через `go`. Без
/// провайдера или без колокольчика (администратор без больницы) — «Новых уведомлений нет».
class StaffNotificationsScreen extends StatefulWidget {
  const StaffNotificationsScreen({super.key});

  @override
  State<StaffNotificationsScreen> createState() => _StaffNotificationsScreenState();
}

class _StaffNotificationsScreenState extends State<StaffNotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // свежий список при открытии: последний опрос мог быть минуту назад
    unawaited(context.read<StaffBellNotifier?>()?.refresh());
  }

  /// Отметить прочитанным (не ждём: пункт исчезает сразу, сбой остаётся в колокольчике) и открыть [target].
  void _open(StaffBellNotifier bell, String kind, String id, String target) {
    unawaited(bell.markRead(kind, id));
    context.go(target);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final bell = context.watch<StaffBellNotifier?>();
    return PageScaffold(
      title: s.bellTitle,
      onRefresh: bell != null && bell.active ? bell.refresh : null,
      children: bell == null || !bell.active ? [_empty(s)] : _content(s, bell),
    );
  }

  Widget _empty(S s) => EmptyState(icon: Icons.notifications_none, title: s.bellEmpty);

  /// Первая загрузка — скелетон, её сбой — ошибка с «Повторить»; дальше пункты (или «Новых уведомлений нет») и, если
  /// последний опрос или отметка прочтения не удались, ошибка над ними — показанные данные остаются.
  List<Widget> _content(S s, StaffBellNotifier bell) {
    final data = bell.bell;
    final error = bell.error;
    if (data == null) {
      return [if (error != null) ErrorState(error: error, onRetry: bell.refresh) else const CardSkeleton(height: 200)];
    }
    final total = data.totalUnread;
    return [
      if (total > 0) Text(s.bellUnread(total), style: Theme.of(context).textTheme.bodySmall),
      if (error != null) ErrorBox(error: error, onRetry: bell.refresh),
      if (total == 0) _empty(s) else AppCard(padding: AppCard.list, child: Column(children: _rows(s, bell, data))),
    ];
  }

  /// Пункты в порядке веба: ждут подтверждения, подтверждения, выписки, события пациентов (серверный порядок).
  List<Widget> _rows(S s, StaffBellNotifier bell, NotificationBell data) {
    final scribe = context.read<Session>().can(Perm.scribeUse);
    final rows = <Widget Function(bool last)>[
      if (data.pendingIncomingCount > 0)
        (last) => StaffBellRow(
              key: const ValueKey('bell-pending'),
              icon: Icons.move_to_inbox_outlined,
              title: s.bellPendingIncoming(data.pendingIncomingCount),
              onTap: () => context.go(incomingPath),
              last: last,
            ),
      for (final c in data.unreadConfirmations)
        (last) => StaffBellRow(
              key: ValueKey('bell-confirmed-${c.decisionId}'),
              icon: Icons.check_circle_outline,
              title: s.staffBellConfirmed(shortOrgName(c.toMoName)),
              meta: '${c.patientRef} · ${journalMoment(c.confirmedAt)}',
              onTap: () => _open(bell, StaffBellNotifier.referralConfirmed, c.decisionId, patientRoutePath(c.patientRef)),
              last: last,
            ),
      for (final d in data.unreadDischarges)
        (last) => StaffBellRow(
              key: ValueKey('bell-discharged-${d.decisionId}'),
              icon: Icons.assignment_turned_in_outlined,
              title: s.staffBellDischarged(shortOrgName(d.fromMoName)),
              summaryLabel: s.incomingDischargeTitle,
              summary: d.summary,
              meta: '${d.patientRef} · ${journalMoment(d.dischargedAt)}',
              onTap: () => _open(bell, StaffBellNotifier.referralDischarged, d.decisionId, patientRoutePath(d.patientRef)),
              last: last,
            ),
      for (final e in data.patientSignals)
        (last) => StaffBellRow(
              key: ValueKey('bell-event-${e.id}'),
              icon: _eventIcon(e.kind),
              title: s.staffBellPatientEvent(e.kind, ref: e.patientRef, org: shortOrgName(e.moName)),
              comment: e.comment,
              meta: journalMoment(e.at),
              onTap: () => _open(bell, StaffBellNotifier.patientSignal, e.id, _eventTarget(e, scribe: scribe)),
              last: last,
            ),
    ];
    return [for (final (i, row) in rows.indexed) row(i == rows.length - 1)];
  }
}

/// Куда ведёт событие пациента: ответ на запрос записи приёма — скрайб этого пациента (если он доступен), остальное —
/// маршрут пациента.
String _eventTarget(PatientEvent event, {required bool scribe}) =>
    scribe && event.kind.startsWith('scribe_') ? patientScribePath(event.patientRef) : patientRoutePath(event.patientRef);

/// Значок события пациента — Material-аналоги значков веба (`PATIENT_ICONS`); незнакомое — человек.
IconData _eventIcon(String kind) => switch (kind) {
      'request' => Icons.swap_horiz,
      'prefer_current' => Icons.home_outlined,
      'still_waiting' => Icons.schedule,
      'withdraw' || 'consent_declined' => Icons.cancel_outlined,
      'treated_elsewhere' => Icons.apartment,
      'consent_accepted' => Icons.check_circle_outline,
      'scribe_granted' || 'scribe_declined' || 'scribe_withdrawn' => Icons.mic_none,
      _ => Icons.person_outline,
    };
