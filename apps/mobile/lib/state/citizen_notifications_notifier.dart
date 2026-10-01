import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import 'session.dart';
import 'session_poller.dart';

/// Колокольчик гражданина — `GET /route/me/notifications` (§3.7): что другие сделали на его маршруте, напоминания об
/// анализах и запросы записи приёма. Опрос раз в минуту на переднем плане, сразу при возвращении из фона и после
/// каждого действия гражданина ([refresh] из `CitizenRouteController`); push нет (Q22). Работает только для роли
/// `citizen` с `route.own` (решение API 9, как `useNotificationBell.ts` в вебе): врач без организации в гражданском
/// кабинете колокольчик не опрашивает. Каждый запрос — с регионом сессии; смена пользователя или региона сбрасывает
/// ленту и перечитывает её. Над приложением один экземпляр (`AppScope`), вкладка «Уведомления» показывает [unread],
/// экран `/updates` — [items] в порядке сервера.
class CitizenNotificationsNotifier extends SessionPoller<CitizenNotifications> {
  CitizenNotificationsNotifier({required super.session, super.interval, super.timeout, this.onNewItems});

  /// Период опроса (Q22).
  static const defaultInterval = SessionPoller.defaultInterval;

  /// Вызывается, когда очередной ответ принёс пункт с новым id (не при первой загрузке): на маршруте что-то
  /// случилось — `AppScope` перечитывает маршрут гражданина, чтобы карточка действия появилась без pull-to-refresh.
  final VoidCallback? onNewItems;

  /// Лента целиком; null — не загружена или колокольчик неактивен.
  CitizenNotifications? get notifications => data;

  /// Непрочитанных — счётчик на вкладке «Уведомления».
  int get unread => data?.unread ?? 0;

  /// Пункты в порядке сервера: сначала «нужен ответ», затем новые.
  List<CitizenNotification> get items => data?.items ?? const [];

  /// Счётчик для вкладки из дерева виджетов; без провайдера (тест отдельного экрана) — 0.
  static int unreadOf(BuildContext context) => context.select<CitizenNotificationsNotifier?, int>((n) => n?.unread ?? 0);

  @override
  bool eligible(Session session) => session.isAuthenticated && session.primaryRoleKey == 'citizen' && session.can(Perm.routeOwn);

  @override
  Object? scopeOf(Session session) => (session.username, session.region);

  @override
  Future<CitizenNotifications> fetch(Session session) => session.api.routeNotifications(regionKato: session.region);

  @override
  void onLoaded(CitizenNotifications? previous, CitizenNotifications next) {
    if (previous == null || onNewItems == null) {
      return;
    }
    final seen = {for (final item in previous.items) item.id};
    if (next.items.any((item) => !seen.contains(item.id))) {
      onNewItems!();
    }
  }

  /// Отметить пункт прочитанным: счётчик и пункт меняются сразу, затем `POST …/{id}/read` и перечитывание ленты.
  /// Не бросает: сбой отметки остаётся в [error] (истину возвращает перечитывание), переход по пункту не ждёт сеть.
  Future<void> markRead(String id) async {
    if (!active) {
      return;
    }
    final current = data;
    if (current != null && current.items.any((item) => item.id == id && !item.read)) {
      replaceData(CitizenNotifications(
        unread: max(0, current.unread - 1),
        items: List.unmodifiable(current.items.map((item) => item.id == id ? _asRead(item) : item)),
      ));
    }
    Object? failure;
    try {
      await session.api.markRouteNotificationRead(id, regionKato: session.region);
    } on Exception catch (e) {
      failure = e;
    }
    await refresh();
    if (failure != null) {
      recordError(failure);
    }
  }

  static CitizenNotification _asRead(CitizenNotification item) => CitizenNotification(
        id: item.id,
        kind: item.kind,
        at: item.at,
        moName: item.moName,
        plannedAt: item.plannedAt,
        reason: item.reason,
        needsAction: item.needsAction,
        read: true,
        count: item.count,
      );
}
