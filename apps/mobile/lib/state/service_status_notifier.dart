import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../api/service_status.dart';

/// Статус внешних сервисов (`GET /public/service-status`) для всего приложения: грузится при запуске ([start]),
/// при возвращении приложения на передний план и каждые [interval] (5 минут), пока приложение на экране; в фоне
/// опрос остановлен. Сбой запроса или таймаут — [ServiceStatus.fallback]: про почту ничего не утверждаем, push,
/// SMS и eGov недоступны. Баннер «почтовый сервер недоступен» закрывается до конца сеанса приложения.
class ServiceStatusNotifier extends ChangeNotifier with WidgetsBindingObserver {
  ServiceStatusNotifier({required Future<ServiceStatus> Function() fetch, this.interval = defaultInterval, this.timeout = defaultTimeout}) : _fetch = fetch;

  static const defaultInterval = Duration(minutes: 5);

  /// С запасом: при холодном старте первый кадр занимает изолят, и ответ, уже пришедший по сети, может ждать
  /// обработки дольше короткого таймаута. Долгое ожидание ничего не портит — до ответа действует тот же фолбэк.
  static const defaultTimeout = Duration(seconds: 20);

  final Future<ServiceStatus> Function() _fetch;

  /// Период опроса, пока приложение на переднем плане.
  final Duration interval;

  /// Сколько ждать ответа, прежде чем считать запрос неудачным.
  final Duration timeout;

  ServiceStatus _status = ServiceStatus.fallback;
  bool _emailBannerDismissed = false;
  bool _started = false;
  bool _disposed = false;
  Timer? _timer;
  Future<void>? _inFlight;

  ServiceStatus get status => _status;

  /// Баннер в shell'ах: почта точно не работает (не «неизвестно») и пользователь его не закрыл.
  bool get showEmailBanner => _status.email.isDown && !_emailBannerDismissed;

  /// Статус из дерева виджетов; без провайдера (тест отдельного экрана) — [ServiceStatus.fallback].
  static ServiceStatus watch(BuildContext context) => context.watch<ServiceStatusNotifier?>()?.status ?? ServiceStatus.fallback;

  /// Первая загрузка, опрос и подписка на жизненный цикл приложения; повторный вызов ничего не делает.
  void start() {
    if (_started || _disposed) {
      return;
    }
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    unawaited(refresh());
    _schedule();
  }

  /// Перечитывает статус; параллельные вызовы ждут один и тот же запрос.
  Future<void> refresh() => _inFlight ??= _load().whenComplete(() => _inFlight = null);

  void dismissEmailBanner() {
    if (_emailBannerDismissed) {
      return;
    }
    _emailBannerDismissed = true;
    notifyListeners();
  }

  Future<void> _load() async {
    ServiceStatus next;
    try {
      next = await _fetch().timeout(timeout);
    } on Exception {
      // эндпоинта ещё нет на стенде (404), сеть, таймаут или не JSON — честный фолбэк, без баннера о почте
      next = ServiceStatus.fallback;
    } catch (error, stack) {
      // ошибка в коде клиента, а не сбой сервиса: фолбэк тот же, но ошибка видна в логах и тестах
      FlutterError.reportError(FlutterErrorDetails(exception: error, stack: stack, library: 'service status'));
      next = ServiceStatus.fallback;
    }
    if (_disposed || next == _status) {
      return;
    }
    _status = next;
    notifyListeners();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => unawaited(refresh()));
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // из фона (опрос был остановлен) — сразу перечитать; из inactive (шторка, системный диалог) — продолжить
        if (_timer == null) {
          unawaited(refresh());
          _schedule();
        }
      case AppLifecycleState.hidden || AppLifecycleState.paused || AppLifecycleState.detached:
        _stop();
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _stop();
    if (_started) {
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }
}
