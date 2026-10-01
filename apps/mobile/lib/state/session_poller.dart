import 'dart:async';

import 'package:flutter/widgets.dart';

import 'session.dart';

/// Опрос сервера на переднем плане для данных вошедшего пользователя (колокольчики гражданина и персонала): push нет,
/// поэтому сервер опрашивается раз в [interval] (60 с — Q22, Q-15), пока приложение на экране; в фоне опрос
/// остановлен, при возвращении из фона — сразу перечитать. Подкласс задаёт, кому опрос положен ([eligible]), от чего
/// зависят данные ([scopeOf]: пользователь, регион, организация — смена сбрасывает данные и перечитывает их) и сам
/// запрос ([fetch]).
///
/// Жизненный цикл явный: [start] подписывается на сессию и жизненный цикл приложения, [stop] отписывается и сбрасывает
/// данные, [dispose] гасит таймер и подписки. Без [start] нет ни запросов, ни таймеров, поэтому виджет-тесты не ждут
/// таймеров: держатель либо не запущен, либо освобождается вместе с деревом (`AppScope`).
///
/// Ошибки: сбой сети или ответ ≥ 400 оставляет последние данные и пишется в [error]; ошибка кода клиента (не
/// `Exception`) ещё и сообщается через `FlutterError.reportError`, чтобы не выглядеть как «сервер недоступен».
/// Ответ запроса, начатого до смены области или до [refresh], отбрасывается.
abstract class SessionPoller<T> extends ChangeNotifier with WidgetsBindingObserver {
  SessionPoller({required this.session, this.interval = defaultInterval, this.timeout = defaultTimeout});

  /// Период опроса на переднем плане (Q22, Q-15).
  static const defaultInterval = Duration(seconds: 60);

  /// Сколько ждать ответа, прежде чем считать запрос неудачным (иначе зависший запрос остановил бы опрос).
  static const defaultTimeout = Duration(seconds: 20);

  final Session session;
  final Duration interval;
  final Duration timeout;

  T? _data;
  Object? _error;
  bool _started = false;
  bool _active = false;
  bool _disposed = false;
  bool _foreground = true;
  Object? _scope;
  int _generation = 0;
  Timer? _timer;
  Future<void>? _inFlight;

  /// Последние полученные данные; null — ещё не загружены или опрос неактивен.
  T? get data => _data;

  /// Последняя ошибка опроса или отметки прочтения; null после успешной загрузки.
  Object? get error => _error;

  /// Опрос идёт: держатель запущен и пользователю он положен.
  bool get active => _active;

  /// Запрос в полёте.
  bool get loading => _inFlight != null;

  /// Кому положен опрос — проверяется при каждом изменении сессии.
  @protected
  bool eligible(Session session);

  /// Область данных: при её смене данные сбрасываются и перечитываются. Сравнивается через `==` (удобна запись).
  @protected
  Object? scopeOf(Session session);

  @protected
  Future<T> fetch(Session session);

  /// Хук после успешной загрузки до уведомления слушателей; [previous] — данные этой же области до загрузки
  /// (null — первая загрузка).
  @protected
  void onLoaded(T? previous, T next) {}

  /// Подписка на сессию и жизненный цикл приложения; если опрос пользователю положен — загрузка сразу и дальше
  /// каждые [interval] на переднем плане. Повторный вызов ничего не делает.
  void start() {
    if (_started || _disposed) {
      return;
    }
    _started = true;
    final binding = WidgetsBinding.instance;
    binding.addObserver(this);
    _foreground = !_isBackground(binding.lifecycleState);
    session.addListener(_sync);
    _sync();
  }

  /// Отписка, таймер остановлен, данные сброшены. После [stop] можно снова [start].
  void stop() {
    if (!_started) {
      return;
    }
    _started = false;
    session.removeListener(_sync);
    WidgetsBinding.instance.removeObserver(this);
    if (_active) {
      _deactivate();
      notifyListeners();
    }
  }

  /// Перечитать сейчас (после действия пользователя, отметки прочтения, pull-to-refresh). Ответ запроса, начатого
  /// раньше, отбрасывается. Неактивный опрос — ничего не делает. Не бросает: ошибка — в [error].
  Future<void> refresh() {
    if (!_active || _disposed) {
      return Future.value();
    }
    _generation++;
    return _begin(_generation);
  }

  /// Подменяет данные (мгновенная отметка прочтения до ответа сервера); неактивный опрос — без изменений.
  @protected
  void replaceData(T value) {
    if (!_active || _disposed) {
      return;
    }
    _data = value;
    notifyListeners();
  }

  /// Записывает ошибку действия (отметки прочтения), чтобы экран мог её показать.
  @protected
  void recordError(Object error) {
    if (!_active || _disposed) {
      return;
    }
    _error = error;
    notifyListeners();
  }

  void _sync() {
    if (_disposed) {
      return;
    }
    if (!_started || !eligible(session)) {
      if (_active) {
        _deactivate();
        notifyListeners();
      }
      return;
    }
    final scope = scopeOf(session);
    if (_active && scope == _scope) {
      return;
    }
    _deactivate();
    _active = true;
    _scope = scope;
    notifyListeners();
    unawaited(refresh());
    _schedule();
  }

  void _deactivate() {
    _active = false;
    _scope = null;
    _data = null;
    _error = null;
    _generation++;
    _inFlight = null;
    _cancelTimer();
  }

  Future<void> _begin(int generation) {
    final future = _load(generation);
    _inFlight = future;
    unawaited(future.whenComplete(() {
      if (identical(_inFlight, future)) {
        _inFlight = null;
      }
    }));
    return future;
  }

  void _poll() {
    if (_active && _inFlight == null) {
      unawaited(_begin(_generation));
    }
  }

  Future<void> _load(int generation) async {
    final T next;
    try {
      next = await fetch(session).timeout(timeout);
    } on Exception catch (e) {
      _fail(generation, e);
      return;
    } catch (e, stack) {
      FlutterError.reportError(FlutterErrorDetails(exception: e, stack: stack, library: 'darumen state'));
      _fail(generation, e);
      return;
    }
    if (_stale(generation)) {
      return;
    }
    final previous = _data;
    _data = next;
    _error = null;
    onLoaded(previous, next);
    notifyListeners();
  }

  void _fail(int generation, Object error) {
    if (_stale(generation)) {
      return;
    }
    _error = error;
    notifyListeners();
  }

  bool _stale(int generation) => _disposed || !_active || generation != _generation;

  void _schedule() {
    _cancelTimer();
    if (_active && _foreground) {
      _timer = Timer.periodic(interval, (_) => _poll());
    }
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  static bool _isBackground(AppLifecycleState? state) =>
      state == AppLifecycleState.hidden || state == AppLifecycleState.paused || state == AppLifecycleState.detached;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isBackground(state)) {
      _foreground = false;
      _cancelTimer();
      return;
    }
    if (state == AppLifecycleState.resumed && !_foreground) {
      // из фона (опрос был остановлен) — сразу перечитать; inactive (шторка, системный диалог) — не возвращение
      _foreground = true;
      unawaited(refresh());
      _schedule();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelTimer();
    if (_started) {
      _started = false;
      session.removeListener(_sync);
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }
}
