import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/client.dart';
import '../api/models.dart';
import 'load_state.dart';
import 'session.dart';

/// Маршрут гражданина и его запросы записи приёма — один экземпляр над приложением (`AppScope`) вместо своей копии
/// маршрута в каждом экране (главная, «Мой путь», «Сколько ждут», памятка). Повторяет `useRouteData.ts` веба:
/// - что можно сделать — только из `progress.allowed` ([can]); правил состояния клиент не вычисляет;
/// - одно действие за раз: пока запрос в полёте, [acting] показывает, какая кнопка нажата (экран блокирует все
///   кнопки действий), повторное нажатие получает тот же итог без второго запроса;
/// - один свежий Idempotency-Key на нажатие; успех (201 или 200 на повтор) — маршрут перечитывается;
/// - 409 — маршрут уже изменился: сначала перечитать, потом вернуть ошибку (заголовок и деталь сервера для показа);
///   422 / 403 / сеть — вернуть как есть, без перечитывания;
/// - каждый вызов `/route/me/*` — с регионом сессии (решение API 8); смена языка (тексты сервера) или региона
///   (другой пациент) перечитывает маршрут, если экран его уже просил; смена пользователя сбрасывает всё.
/// После каждого действия вызывается [afterAction] — `AppScope` перечитывает колокольчик гражданина.
///
/// Итог действия — `Future<Object?>`: null — записано, иначе ошибка (`ApiException` с HTTP-кодом в `status`, строкой
/// состояния в `stateCode` и ошибками полей; `http.ClientException`; `TimeoutException`). Та же ошибка лежит в
/// [actionError] до следующего действия или [clearActionError] — для показа рядом с карточкой.
class CitizenRouteController extends ChangeNotifier {
  CitizenRouteController({required this.session, this.afterAction})
      : _identity = _identityOf(session),
        _context = _contextOf(session) {
    session.addListener(_onSession);
  }

  final Session session;

  /// Вызывается после каждого действия гражданина (успех или ошибка).
  final VoidCallback? afterAction;

  LoadState<PatientRoute> _state = const Loading();
  bool _refreshing = false;
  List<ScribeConsent> _scribe = const [];
  Object? _scribeError;
  bool _requested = false;
  bool _disposed = false;
  String? _acting;
  Object? _actionError;
  Future<Object?>? _action;
  Future<void>? _loading;
  int _generation = 0;
  int _epoch = 0;
  (bool, String?, ShellKind?) _identity;
  (String, String) _context;

  /// Маршрут: [Loading] до первого ответа, [Loaded], [Failed] (404 «Нет очередей в регионе» — маршрута нет).
  /// При обновлении прежний маршрут остаётся [Loaded], а [refreshing] — true.
  LoadState<PatientRoute> get state => _state;

  /// Загруженный маршрут; null — ещё нет или ошибка.
  PatientRoute? get route => switch (_state) { Loaded<PatientRoute>(:final data) => data, _ => null };

  /// Идёт перечитывание уже показанного маршрута (pull-to-refresh, после действия, смена языка).
  bool get refreshing => _refreshing;

  /// Запросы записи приёма и памятки (`GET /route/me/scribe`), новые первыми; без маршрута — пусто.
  List<ScribeConsent> get scribe => _scribe;

  /// Ошибка загрузки запросов записи; маршрут при этом показывается.
  Object? get scribeError => _scribeError;

  /// Запрос записи приёма, ждущий ответа гражданина (карточка «Разрешаю / Не разрешаю»).
  ScribeConsent? get pendingScribe => _scribe.where((c) => c.status == RouteCodes.scribePending).firstOrNull;

  /// Данное сегодня согласие, пока запись не начата (полоса «Вы разрешили записать приём сегодня» с «Отозвать»).
  ScribeConsent? get grantedScribe => _scribe.where((c) => c.status == RouteCodes.scribeGranted).firstOrNull;

  /// Готовые памятки врача: завершённые записи с токеном (`/home/route/leaflet/:token`).
  List<ScribeConsent> get leaflets =>
      List.unmodifiable(_scribe.where((c) => c.status == RouteCodes.scribeCompleted && (c.leafletToken?.isNotEmpty ?? false)));

  /// Какое действие в полёте: код больницы у просьбы о переводе, код действия (`RouteCodes.action*`) у остальных
  /// сигналов и ответа на перевод, `requestId` у ответа на запрос записи; null — ничего.
  String? get acting => _acting;
  bool get isActing => _acting != null;

  /// Ошибка последнего действия (409 — уже после перечитывания маршрута); null после успеха.
  Object? get actionError => _actionError;

  /// Экран уже просил маршрут — смена языка, региона или пользователя перечитывает его сама.
  bool get requested => _requested;

  /// Действие есть в `progress.allowed` — только тогда экран показывает кнопку.
  bool can(String action) => route?.can(action) ?? false;

  /// Первая загрузка для экрана: если маршрут уже просили — ничего не делает (ждёт идущую загрузку).
  Future<void> ensureLoaded() => _requested ? (_loading ?? Future.value()) : load();

  /// Перечитать маршрут и запросы записи (pull-to-refresh, «Повторить»): ответ начатой раньше загрузки
  /// отбрасывается. Без входа ничего не делает. Не бросает: ошибка — в [state].
  Future<void> load() {
    if (_disposed || !session.isAuthenticated) {
      return Future.value();
    }
    _requested = true;
    final generation = ++_generation;
    if (_state is Loaded<PatientRoute>) {
      _refreshing = true;
    } else {
      _state = const Loading();
    }
    notifyListeners();
    final future = _fetch(generation);
    _loading = future;
    unawaited(future.whenComplete(() {
      if (identical(_loading, future)) {
        _loading = null;
      }
    }));
    return future;
  }

  /// «Попросить рассмотреть» больницу [toMoCode] (`request_transfer`); [comment] — необязательный (Q20).
  Future<Object?> requestTransfer(String toMoCode, {String? comment}) =>
      _signal(RouteCodes.requestRedirect, marker: toMoCode, toMoCode: toMoCode, comment: comment);

  /// «Хочу остаться в своей больнице» (`prefer_current`).
  Future<Object?> preferCurrent() => _signal(RouteCodes.preferCurrent, marker: RouteCodes.actionPreferCurrent);

  /// «Да, жду» / «Я ещё жду» (`still_waiting`).
  Future<Object?> stillWaiting() => _signal(RouteCodes.stillWaiting, marker: RouteCodes.actionStillWaiting);

  /// «Больше не нужно» / «Отказаться от госпитализации» (`withdraw`); [treatedElsewhere] — «Уже лечился в другом
  /// месте». [comment] необязателен.
  Future<Object?> withdraw({bool treatedElsewhere = false, String? comment}) =>
      _signal(treatedElsewhere ? RouteCodes.treatedElsewhere : RouteCodes.withdraw, marker: RouteCodes.actionWithdraw, comment: comment);

  /// Ответ на предложенный перевод [decisionId] (`progress.transfer.decisionId`): согласие (`accept_transfer`) или
  /// отказ (`decline_transfer`, после согласия — отзыв согласия) с необязательной причиной [reason].
  Future<Object?> answerTransfer(String decisionId, {required bool accepted, String? reason}) => _act(
        accepted ? RouteCodes.actionAcceptTransfer : RouteCodes.actionDeclineTransfer,
        (key) => session.api.answerTransfer(decisionId: decisionId, accepted: accepted, reason: _clean(reason), idempotencyKey: key, regionKato: session.region),
      );

  /// Ответ на запрос записи приёма [requestId]: «Разрешаю» / «Не разрешаю»; после разрешения `granted: false` —
  /// «Отозвать» (пока запись не начата).
  Future<Object?> answerScribe(String requestId, {required bool granted}) => _act(
        requestId,
        (key) => session.api.answerScribe(requestId, granted: granted, idempotencyKey: key, regionKato: session.region),
      );

  /// Убрать показанную ошибку действия.
  void clearActionError() {
    if (_actionError == null) {
      return;
    }
    _actionError = null;
    notifyListeners();
  }

  Future<Object?> _signal(String kind, {required String marker, String? toMoCode, String? comment}) => _act(
        marker,
        (key) => session.api.sendRouteSignal(kind, toMoCode: toMoCode, comment: _clean(comment), idempotencyKey: key, regionKato: session.region),
      );

  Future<Object?> _act(String marker, Future<Object?> Function(String idempotencyKey) request) {
    final running = _action;
    if (running != null) {
      return running;
    }
    final future = _run(marker, request);
    _action = future;
    return future;
  }

  Future<Object?> _run(String marker, Future<Object?> Function(String idempotencyKey) request) async {
    final epoch = _epoch;
    _acting = marker;
    _actionError = null;
    notifyListeners();
    Object? outcome;
    try {
      await request(newIdempotencyKey());
      await load();
    } on Exception catch (e) {
      outcome = e;
      if (e is ApiException && e.isConflict && epoch == _epoch) {
        await load();
      }
    } catch (e, stack) {
      _report(e, stack);
      outcome = e;
    }
    _action = null;
    if (_disposed) {
      return outcome;
    }
    _acting = null;
    if (epoch == _epoch) {
      _actionError = outcome;
    }
    notifyListeners();
    afterAction?.call();
    return outcome;
  }

  Future<void> _fetch(int generation) async {
    final region = session.region;
    final scribe = _fetchScribe(region);
    LoadState<PatientRoute> next;
    try {
      next = Loaded(await session.api.myRoute(regionKato: region));
    } on Exception catch (e) {
      next = Failed(e);
    } catch (e, stack) {
      _report(e, stack);
      next = Failed(e);
    }
    final (consents, scribeError) = await scribe;
    if (_disposed || generation != _generation) {
      return;
    }
    _state = next;
    _scribe = consents;
    _scribeError = scribeError;
    _refreshing = false;
    notifyListeners();
  }

  Future<(List<ScribeConsent>, Object?)> _fetchScribe(String region) async {
    try {
      return (List<ScribeConsent>.unmodifiable(await session.api.myScribe(regionKato: region)), null);
    } on Exception catch (e) {
      return (const <ScribeConsent>[], e);
    } catch (e, stack) {
      _report(e, stack);
      return (const <ScribeConsent>[], e);
    }
  }

  void _onSession() {
    if (_disposed) {
      return;
    }
    final identity = _identityOf(session);
    final context = _contextOf(session);
    if (identity != _identity) {
      _identity = identity;
      _context = context;
      _epoch++;
      _generation++;
      _loading = null;
      _state = const Loading();
      _refreshing = false;
      _scribe = const [];
      _scribeError = null;
      _actionError = null;
      notifyListeners();
      // экран уже просил маршрут — после входа другого гражданина он увидит свой, а не пустой
      if (_requested && session.isCitizen) {
        unawaited(load());
      }
      return;
    }
    if (context != _context) {
      _context = context;
      if (_requested) {
        unawaited(load());
      }
    }
  }

  static (bool, String?, ShellKind?) _identityOf(Session session) => (session.isAuthenticated, session.username, session.shell);

  static (String, String) _contextOf(Session session) => (session.locale, session.region);

  static String? _clean(String? text) {
    final trimmed = text?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static void _report(Object error, StackTrace stack) =>
      FlutterError.reportError(FlutterErrorDetails(exception: error, stack: stack, library: 'darumen state'));

  @override
  void dispose() {
    _disposed = true;
    session.removeListener(_onSession);
    super.dispose();
  }
}
