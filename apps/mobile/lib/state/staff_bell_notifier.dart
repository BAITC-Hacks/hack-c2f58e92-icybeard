import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import 'session.dart';
import 'session_poller.dart';

/// Колокольчик персонала своей больницы — `GET /journal/notifications/bell?moCode=` (§3.8): переводы в мою больницу,
/// ждущие подтверждения приёма; мои направления, которые подтвердили или по которым выписали; действия пациентов
/// моей больницы. Опрос раз в минуту на переднем плане и сразу при возвращении из фона (Q-15); после действий
/// принимающей больницы экран входящих зовёт [refresh]. Работает только при `worklist.view` и своей организации
/// (`Session.moCode`), как в вебе: у администратора без больницы колокольчика нет. Смена пользователя или организации
/// сбрасывает данные. Над приложением один экземпляр (`AppScope`): вкладка «Входящие» показывает
/// [pendingIncomingCount], кнопка-колокольчик рабочего списка — [totalUnread], экран `/doctor/notifications` — списки.
class StaffBellNotifier extends SessionPoller<NotificationBell> {
  StaffBellNotifier({required super.session, super.interval, super.timeout});

  /// Период опроса (Q-15).
  static const defaultInterval = SessionPoller.defaultInterval;

  /// Виды для [markRead] — то же, что `RouteCodes.bell*`.
  static const referralConfirmed = RouteCodes.bellReferralConfirmed;
  static const referralDischarged = RouteCodes.bellReferralDischarged;
  static const patientSignal = RouteCodes.bellPatientSignal;

  /// Ответ целиком; null — не загружен или колокольчик неактивен.
  NotificationBell? get bell => data;

  /// Переводы в мою больницу, ждущие подтверждения приёма — счётчик на вкладке «Входящие».
  int get pendingIncomingCount => data?.pendingIncomingCount ?? 0;

  /// Мои направления, подтверждённые принимающей больницей (непрочитанные).
  List<SentReferralConfirmation> get unreadConfirmations => data?.unreadConfirmations ?? const [];

  /// Мои направления, по которым пациента выписали с эпикризом (непрочитанные).
  List<DischargeReady> get unreadDischarges => data?.unreadDischarges ?? const [];

  /// Действия пациентов моей больницы за 30 дней (непрочитанные).
  List<PatientEvent> get patientSignals => data?.patientSignals ?? const [];

  /// Число на кнопке-колокольчике: ждущие подтверждения плюс все непрочитанные пункты.
  int get totalUnread => data?.totalUnread ?? 0;

  /// Счётчик для вкладки «Входящие» из дерева виджетов; без провайдера — 0.
  static int pendingIncomingOf(BuildContext context) => context.select<StaffBellNotifier?, int>((b) => b?.pendingIncomingCount ?? 0);

  /// Колокольчик из дерева виджетов: положен ли он пользователю и сколько на нём; без провайдера — `(false, 0)`.
  static ({bool active, int unread}) watchBell(BuildContext context) =>
      context.select<StaffBellNotifier?, ({bool active, int unread})>((b) => (active: b?.active ?? false, unread: b?.totalUnread ?? 0));

  @override
  bool eligible(Session session) => session.isAuthenticated && session.can(Perm.worklistView) && session.moCode != null;

  @override
  Object? scopeOf(Session session) => (session.username, session.moCode);

  @override
  Future<NotificationBell> fetch(Session session) => session.api.doctorBell(moCode: session.moCode);

  /// Отметить пункт прочитанным: [kind] — [referralConfirmed] (id — `decisionId`), [referralDischarged] (`decisionId`)
  /// или [patientSignal] (`id` события). Пункт исчезает сразу, затем `POST …/bell/{kind}/{id}/read` и перечитывание.
  /// Не бросает: сбой остаётся в [error], список возвращает перечитывание.
  Future<void> markRead(String kind, String id) async {
    if (!active) {
      return;
    }
    final current = data;
    if (current != null) {
      replaceData(NotificationBell(
        pendingIncomingCount: current.pendingIncomingCount,
        unreadConfirmations: kind == referralConfirmed ? List.unmodifiable(current.unreadConfirmations.where((c) => c.decisionId != id)) : current.unreadConfirmations,
        unreadDischarges: kind == referralDischarged ? List.unmodifiable(current.unreadDischarges.where((d) => d.decisionId != id)) : current.unreadDischarges,
        patientSignals: kind == patientSignal ? List.unmodifiable(current.patientSignals.where((s) => s.id != id)) : current.patientSignals,
      ));
    }
    Object? failure;
    try {
      await session.api.markBellRead(kind, id);
    } on Exception catch (e) {
      failure = e;
    }
    await refresh();
    if (failure != null) {
      recordError(failure);
    }
  }
}
