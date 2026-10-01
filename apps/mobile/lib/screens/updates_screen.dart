import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/citizen_notifications_notifier.dart';
import '../state/citizen_route_controller.dart';
import '../state/service_status_notifier.dart';
import '../widgets/app_card.dart';
import '../widgets/citizen/citizen_route_rules.dart';
import '../widgets/citizen/notification_tile.dart';
import '../widgets/darumen_mark.dart';
import '../widgets/empty_state.dart';
import '../widgets/notice_card.dart';
import '../widgets/section.dart';
import '../widgets/skeleton.dart';
import '../widgets/state_view.dart';

/// «Уведомления» гражданина — колокольчик сервера (`GET /route/me/notifications`, F13) из общего
/// [CitizenNotificationsNotifier] (опрос раз в минуту на переднем плане, сразу после действий и при возвращении в
/// приложение; счётчик на вкладке — тот же). Только то, что сделали другие на маршруте, напоминание об анализах и
/// запросы записи приёма — в порядке сервера (сначала «нужен ответ», затем новые, Q10); сверху «новых: N». Тап
/// отмечает непрочитанное прочитанным и открывает «Мой путь», а памятку — сразу в читалке (Q9). Внизу — честная
/// заметка, пока push-сервис не подключён. Без колокольчика в дереве (экран вне `AppScope`) — пустой список.
class UpdatesScreen extends StatelessWidget {
  const UpdatesScreen({super.key});

  /// Тап по уведомлению: отметка «прочитано» идёт в фоне (переход её не ждёт); памятке нужен список памяток
  /// маршрута — если «Мой путь» ещё не загружался, он загружается до перехода.
  static Future<void> _open(BuildContext context, CitizenNotification item) async {
    final bell = context.read<CitizenNotificationsNotifier?>();
    final route = context.read<CitizenRouteController?>();
    final router = GoRouter.of(context);
    if (!item.read && bell != null) {
      unawaited(bell.markRead(item.id));
    }
    if (item.kind == RouteCodes.notificationScribeLeaflet && route != null) {
      await route.ensureLoaded();
    }
    router.go(notificationPath(item, route?.leaflets ?? const []));
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final bell = context.watch<CitizenNotificationsNotifier?>();
    final push = ServiceStatusNotifier.watch(context).push;
    final unread = bell?.unread ?? 0;
    final items = bell?.items ?? const <CitizenNotification>[];
    final waiting = bell != null && bell.notifications == null;
    return PageScaffold(
      title: s.updatesTitle,
      leading: const DarumenMark(size: 28),
      onRefresh: bell?.refresh,
      children: [
        if (unread > 0) Text(s.bellUnread(unread), style: Theme.of(context).textTheme.labelSmall),
        if (waiting && bell.error != null)
          ErrorState(error: bell.error!, onRetry: bell.refresh)
        else if (waiting && bell.active)
          const CardSkeleton(height: 360)
        else if (items.isEmpty)
          EmptyState(icon: Icons.notifications_none, title: s.bellEmpty)
        else
          AppCard(
            padding: AppCard.list,
            child: Column(
              children: [
                for (final (i, item) in items.indexed)
                  NotificationTile(item: item, last: i == items.length - 1, onTap: () => _open(context, item)),
              ],
            ),
          ),
        if (!push.isUp) NoticeCard(icon: Icons.info_outline, body: s.pushDownNote(push.reason)),
      ],
    );
  }
}
