import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'citizen_notifications_notifier.dart';
import 'citizen_route_controller.dart';
import 'service_status_notifier.dart';
import 'session.dart';
import 'session_poller.dart';
import 'staff_bell_notifier.dart';

/// Держатели состояния приложения над роутером и обоими shell'ами (и над листами и диалогами, которые открываются
/// на корневом навигаторе): [Session], [ServiceStatusNotifier], [CitizenRouteController],
/// [CitizenNotificationsNotifier], [StaffBellNotifier]. Создаёт их один раз, связывает и освобождает вместе с собой:
/// - после действия гражданина колокольчик гражданина перечитывается сразу;
/// - колокольчик гражданина принёс новый пункт — маршрут перечитывается (если экран его уже просил), чтобы карточка
///   действия появилась на главной и в «Моём пути» без pull-to-refresh;
/// - колокольчики сами включаются и выключаются по сессии (роль, организация, регион), опрос — раз в [pollInterval]
///   на переднем плане.
/// Экраны берут их через `context.watch<…>()` / `context.read<…>()`. Тот же виджет оборачивает экран в тестах
/// (`test/support/harness.dart`), поэтому таймеры опроса гаснут вместе с деревом.
class AppScope extends StatefulWidget {
  const AppScope({super.key, required this.session, required this.child, this.pollInterval = SessionPoller.defaultInterval, this.serviceStatus});

  /// Сессия создаётся в `main` (или тестом) и не освобождается здесь.
  final Session session;
  final Widget child;

  /// Период опроса колокольчиков на переднем плане (Q22, Q-15).
  final Duration pollInterval;

  /// Готовый статус сервисов (тесты); null — свой, с опросом `GET /public/service-status`.
  final ServiceStatusNotifier? serviceStatus;

  @override
  State<AppScope> createState() => _AppScopeState();
}

class _AppScopeState extends State<AppScope> {
  late final ServiceStatusNotifier _status = widget.serviceStatus ?? (ServiceStatusNotifier(fetch: widget.session.api.serviceStatus)..start());
  late final CitizenNotificationsNotifier _notifications = CitizenNotificationsNotifier(
    session: widget.session,
    interval: widget.pollInterval,
    onNewItems: () {
      if (_route.requested) {
        unawaited(_route.load());
      }
    },
  );
  late final CitizenRouteController _route = CitizenRouteController(session: widget.session, afterAction: () => unawaited(_notifications.refresh()));
  late final StaffBellNotifier _bell = StaffBellNotifier(session: widget.session, interval: widget.pollInterval);

  @override
  void initState() {
    super.initState();
    _notifications.start();
    _bell.start();
  }

  @override
  void dispose() {
    _route.dispose();
    _notifications.dispose();
    _bell.dispose();
    if (widget.serviceStatus == null) {
      _status.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MultiProvider(
        providers: [
          ChangeNotifierProvider<Session>.value(value: widget.session),
          ChangeNotifierProvider<ServiceStatusNotifier>.value(value: _status),
          ChangeNotifierProvider<CitizenRouteController>.value(value: _route),
          ChangeNotifierProvider<CitizenNotificationsNotifier>.value(value: _notifications),
          ChangeNotifierProvider<StaffBellNotifier>.value(value: _bell),
        ],
        child: widget.child,
      );
}
