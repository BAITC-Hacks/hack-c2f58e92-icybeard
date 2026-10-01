import 'dart:async';
import 'dart:convert';

import 'package:darumen/api/client.dart';
import 'package:darumen/api/models.dart';
import 'package:darumen/state/citizen_route_controller.dart';
import 'package:darumen/state/load_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/harness.dart';

const _route = '/route/me';
const _scribe = '/route/me/scribe';
const _transferId = 'd2a6afd6-c158-49ab-96ef-385974a9fe4a';

Map<String, Object?> _consent(String id, String status, {String? token}) => {
      'requestId': id,
      'patientRef': 'SYN-75-08IV-121-01',
      'moCode': '08IV',
      'moName': 'Алматинский онкологический центр',
      'requestedRole': 'doctor',
      'requestedAt': '2026-10-01T09:00:00+00:00',
      'day': '2026-10-01',
      'status': status,
      'leafletToken': ?token,
    };

/// Бэкенд гражданина: маршрут из фикстуры, список запросов записи и 201 на любое действие.
Future<(CitizenRouteController, DemoBackend, List<int>)> _controller({Map<String, Object?> api = const {}, Map<String, String?> claims = const {}}) async {
  final (session, backend) = await demoSession(DemoUser.citizen1, claimOverrides: claims, api: {
    _route: fixtureMap('route-me'),
    _scribe: [_consent('r-new', 'pending'), _consent('r-ok', 'granted'), _consent('r-done', 'completed', token: 'tok-12345678ABCDEF'), _consent('r-old', 'completed')],
    'POST /route/me/signals': recorded(),
    'POST /route/me/consent': recorded(),
    'POST /answer': recorded(),
    ...api,
  });
  final afterAction = <int>[];
  final controller = CitizenRouteController(session: session, afterAction: () => afterAction.add(1));
  addTearDown(controller.dispose);
  return (controller, backend, afterAction);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('loading', () {
    test('ensureLoaded reads the route and the scribe requests with the session region, once', () async {
      final (controller, backend, _) = await _controller();
      expect(controller.state, isA<Loading<PatientRoute>>());
      expect(controller.route, isNull);
      expect(backend.calls('GET', _route), isEmpty, reason: 'ничего не грузится, пока экран не попросил');

      await controller.ensureLoaded();
      expect(controller.state, isA<Loaded<PatientRoute>>());
      expect(controller.route!.patientRef, 'SYN-75-08IV-121-01');
      expect(backend.calls('GET', _route).single.url.queryParameters['regionKato'], '75');
      expect(backend.calls('GET', _scribe).single.url.queryParameters['regionKato'], '75');
      expect(controller.can(RouteCodes.actionAcceptTransfer), isTrue, reason: 'кнопки — только из progress.allowed');
      expect(controller.can(RouteCodes.actionStillWaiting), isFalse);
      expect(controller.scribe.map((c) => c.requestId), ['r-new', 'r-ok', 'r-done', 'r-old'], reason: 'порядок сервера');
      expect(controller.pendingScribe?.requestId, 'r-new');
      expect(controller.grantedScribe?.requestId, 'r-ok');
      expect(controller.leaflets.map((c) => c.requestId), ['r-done'], reason: 'памятка — completed с токеном');

      await controller.ensureLoaded();
      expect(backend.calls('GET', _route), hasLength(1), reason: 'второй экран не перезапрашивает');
    });

    test('load() refreshes in place: the old route stays visible while «refreshing»', () async {
      final slow = Completer<Object?>();
      var calls = 0;
      final (controller, _, _) = await _controller(api: {
        _route: (http.Request r) => ++calls == 2 ? slow.future : fixtureMap('route-me'),
      });
      await controller.ensureLoaded();
      final pending = controller.load();
      expect(controller.state, isA<Loaded<PatientRoute>>(), reason: 'без скелетона на обновлении');
      expect(controller.refreshing, isTrue);
      slow.complete(fixtureMap('route-me'));
      await pending;
      expect(controller.refreshing, isFalse);
    });

    test('no route in the region (404) is a failed state; the scribe list failing alone does not fail the route', () async {
      final (missing, _, _) = await _controller(api: {_route: problem(404, 'Нет очередей в регионе')});
      await missing.ensureLoaded();
      expect(missing.state, isA<Failed<PatientRoute>>().having((f) => (f.error as ApiException).status, 'status', 404));

      final (partial, _, _) = await _controller(api: {_scribe: problem(503, 'Хранилище недоступно')});
      await partial.ensureLoaded();
      expect(partial.state, isA<Loaded<PatientRoute>>());
      expect(partial.scribe, isEmpty);
      expect(partial.scribeError, isA<ApiException>());
    });

    test('a locale change reloads (server texts come in the request language); a region change reloads for the new region', () async {
      final (controller, backend, _) = await _controller(claims: {'region_kato': null});
      final session = controller.session;
      await session.setLocale('kk');
      expect(backend.calls('GET', _route), isEmpty, reason: 'не запрошенный маршрут не грузится сам');
      await controller.ensureLoaded();

      await session.setLocale('ru');
      await pumpEventQueue();
      expect(backend.calls('GET', _route), hasLength(2));
      expect(backend.calls('GET', _route).last.headers['Accept-Language'], 'ru');

      await session.setRegion('11');
      await pumpEventQueue();
      expect(backend.calls('GET', _route).last.url.queryParameters['regionKato'], '11');
      expect(backend.calls('GET', _scribe).last.url.queryParameters['regionKato'], '11');
    });

    test('sign-out resets the controller; signing in again reloads what a screen had asked for', () async {
      final (controller, backend, _) = await _controller();
      await controller.ensureLoaded();
      final session = controller.session;
      await session.logout();
      expect(controller.route, isNull);
      expect(controller.state, isA<Loading<PatientRoute>>());
      expect(controller.scribe, isEmpty);

      await session.login('citizen1', 'darumen');
      await pumpEventQueue();
      expect(backend.calls('GET', _route), hasLength(2));
      expect(controller.state, isA<Loaded<PatientRoute>>());
    });
  });

  group('actions', () {
    test('answerTransfer: explicit accepted, the session region, a fresh key; then reload and the bell refresh', () async {
      final (controller, backend, afterAction) = await _controller();
      await controller.ensureLoaded();
      final outcome = await controller.answerTransfer(_transferId, accepted: true);
      expect(outcome, isNull, reason: 'null — записано');
      final post = backend.calls('POST', '/route/me/consent').single;
      expect(jsonDecode(post.body), {'decisionId': _transferId, 'accepted': true});
      expect(post.url.queryParameters['regionKato'], '75');
      expect(post.headers['Idempotency-Key'], isNotEmpty);
      expect(backend.calls('GET', _route), hasLength(2), reason: 'успех — перечитать маршрут');
      expect(afterAction, [1]);

      await controller.answerTransfer(_transferId, accepted: false, reason: '  далеко ездить  ');
      expect(backend.lastBody('POST', '/route/me/consent'), {'decisionId': _transferId, 'accepted': false, 'reason': 'далеко ездить'});
      await controller.answerTransfer(_transferId, accepted: false, reason: '   ');
      expect(backend.lastBody('POST', '/route/me/consent'), {'decisionId': _transferId, 'accepted': false}, reason: 'пустая причина не уходит');
      final keys = backend.calls('POST', '/route/me/consent').map((r) => r.headers['Idempotency-Key']).toSet();
      expect(keys, hasLength(3), reason: 'новый ключ на каждое нажатие');
    });

    test('signals: a hospital request with a trimmed comment, «хочу остаться», «я ещё жду», withdrawal of both kinds', () async {
      final (controller, backend, afterAction) = await _controller();
      await controller.ensureLoaded();
      await controller.requestTransfer('22GN', comment: '  живу рядом ');
      expect(backend.lastBody('POST', '/route/me/signals'), {'kind': 'request_redirect', 'toMoCode': '22GN', 'comment': 'живу рядом'});
      await controller.preferCurrent();
      expect(backend.lastBody('POST', '/route/me/signals'), {'kind': 'prefer_current'});
      await controller.stillWaiting();
      expect(backend.lastBody('POST', '/route/me/signals'), {'kind': 'still_waiting'});
      await controller.withdraw();
      expect(backend.lastBody('POST', '/route/me/signals'), {'kind': 'withdraw'});
      await controller.withdraw(treatedElsewhere: true, comment: 'прооперировали в Астане');
      expect(backend.lastBody('POST', '/route/me/signals'), {'kind': 'treated_elsewhere', 'comment': 'прооперировали в Астане'});
      expect(backend.calls('POST', '/route/me/signals').every((r) => r.url.queryParameters['regionKato'] == '75'), isTrue);
      expect(afterAction, hasLength(5));
    });

    test('answerScribe sends granted explicitly and reloads the scribe list', () async {
      final (controller, backend, _) = await _controller();
      await controller.ensureLoaded();
      expect(await controller.answerScribe('r-new', granted: false), isNull);
      final post = backend.calls('POST', '/route/me/scribe/r-new/answer').single;
      expect(jsonDecode(post.body), {'granted': false});
      expect(post.url.queryParameters['regionKato'], '75');
      expect(post.headers['Idempotency-Key'], isNotEmpty);
      expect(backend.calls('GET', _scribe), hasLength(2));
    });

    test('the acting marker is set while the request is in flight; a second tap gets the same outcome without a second request', () async {
      final gate = Completer<Object?>();
      final (controller, backend, _) = await _controller(api: {'POST /route/me/consent': (http.Request r) => gate.future});
      await controller.ensureLoaded();
      final markers = <String?>[];
      controller.addListener(() => markers.add(controller.acting));

      final first = controller.answerTransfer(_transferId, accepted: true);
      final second = controller.answerTransfer(_transferId, accepted: false);
      expect(controller.acting, RouteCodes.actionAcceptTransfer);
      expect(controller.isActing, isTrue);
      await pumpEventQueue();
      expect(backend.calls('POST', '/route/me/consent'), hasLength(1), reason: 'двойное нажатие — одна запись в журнале');

      gate.complete(recorded());
      expect(await first, isNull);
      expect(await second, isNull);
      expect(controller.acting, isNull);
      expect(markers.first, RouteCodes.actionAcceptTransfer);

      final hospital = controller.requestTransfer('22GN');
      expect(controller.acting, '22GN', reason: 'просьба о больнице помечается её кодом — крутилка на её плитке');
      await hospital;
      final scribe = controller.answerScribe('r-new', granted: true);
      expect(controller.acting, 'r-new');
      await scribe;
      final still = controller.stillWaiting();
      expect(controller.acting, RouteCodes.actionStillWaiting);
      await still;
    });

    test('409: the route is reloaded first, then the error is surfaced with the server title, detail and state', () async {
      final (controller, backend, afterAction) = await _controller(api: {
        'POST /route/me/consent': problem(409, 'Ждём подтверждения больницы',
            detail: 'пациент согласился на перевод, принимающая больница ещё не ответила', stateCode: 'transfer_pending_confirmation'),
      });
      await controller.ensureLoaded();
      final outcome = await controller.answerTransfer(_transferId, accepted: true);
      expect(outcome, isA<ApiException>().having((e) => e.status, 'status', 409).having((e) => e.stateCode, 'stateCode', 'transfer_pending_confirmation'));
      expect(backend.calls('GET', _route), hasLength(2), reason: 'кто-то успел раньше — показываем актуальный маршрут');
      expect(controller.actionError, same(outcome));
      expect(controller.acting, isNull);
      expect(afterAction, [1]);
      controller.clearActionError();
      expect(controller.actionError, isNull);
    });

    test('422, 403 and network failures are returned as they are, without a reload', () async {
      final (controller, backend, _) = await _controller(api: {
        'POST /route/me/signals': (http.Request r) => switch (jsonDecode(r.body)['kind']) {
              'request_redirect' => problem(422, 'Ошибка валидации', errors: {'toMoCode': ['организация совпадает с текущей']}),
              'prefer_current' => problem(403, 'Нет доступа к разделу', detail: 'permission_required'),
              _ => throw http.ClientException('offline'),
            },
      });
      await controller.ensureLoaded();
      final invalid = await controller.requestTransfer('08IV');
      expect(invalid, isA<ApiException>().having((e) => e.fieldError('toMoCode'), 'field', 'организация совпадает с текущей'));
      final forbidden = await controller.preferCurrent();
      expect(forbidden, isA<ApiException>().having((e) => e.status, 'status', 403));
      final offline = await controller.stillWaiting();
      expect(offline, isA<http.ClientException>());
      expect(backend.calls('GET', _route), hasLength(1));
      expect(controller.actionError, same(offline), reason: 'ошибка — последнего действия');
    });

    test('dispose drops late answers without errors', () async {
      final gate = Completer<Object?>();
      final (session, _) = await demoSession(DemoUser.citizen1, api: {_route: (http.Request r) => gate.future});
      final controller = CitizenRouteController(session: session);
      final loading = controller.ensureLoaded();
      controller.dispose();
      gate.complete(fixtureMap('route-me'));
      await loading;
      expect(controller.route, isNull);
    });
  });
}
