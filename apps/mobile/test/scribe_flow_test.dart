import 'dart:convert';

import 'package:darumen/api/client.dart';
import 'package:darumen/widgets/scribe/scribe_flow.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/harness.dart';

/// ScribeFlow — состояние экрана скрайба одного пациента (порт ScribeView.vue): согласие пациента, состояние сервиса,
/// сессия записи, фразы, запись приёма и памятка, утверждение. Проверяется через мок-API harness: что уходит на
/// сервер (тела, ключ идемпотентности только у запроса согласия), что происходит на 409/404/429.
const ref = 'SYN-75-028B-381-03';

Map<String, Object?> consent(String id, String status, {String? sessionId, String? token}) => {
      'requestId': id,
      'patientRef': ref,
      'moCode': '028B',
      'moName': 'НИИ глазных болезней',
      'requestedRole': 'doctor',
      'requestedAt': '2026-10-01T09:00:00+00:00',
      'day': '2026-10-01',
      'status': status,
      'answeredAt': status == 'pending' ? null : '2026-10-01T09:05:00+00:00',
      'sessionId': ?sessionId,
      'leafletToken': ?token,
    };

Map<String, Object?> segment(String text, {String? original, String? source, double t0 = 0}) =>
    {'t0': t0, 't1': t0 + 4, 'text': text, 'original': ?original, 'source': ?source};

const health = {'status': 'ok', 'transcriber': 'faster-whisper', 'drafter': 'stub', 'transcriberState': 'ready'};

Future<(ScribeFlow, DemoBackend)> flowWith(Map<String, Object?> api, {String language = 'ru'}) async {
  final (session, backend) = await demoSession(DemoUser.doctor1, api: {'/scribe/health': health, ...api});
  final flow = ScribeFlow(api: session.api, patientRef: ref, language: language);
  addTearDown(flow.dispose);
  return (flow, backend);
}

/// Список согласий меняется по ходу теста: каждый GET отдаёт текущее значение.
Object? Function(http.Request) consentsOf(List<Map<String, Object?>> Function() current) => (_) => current();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('согласие пациента', () {
    test('список читается по рефу пациента; текущее — первое; без запросов — «none»', () async {
      final (flow, backend) = await flowWith({'/scribe-consents': [consent('r2', 'pending'), consent('r1', 'completed')]});
      expect(flow.consentsLoaded, isFalse);
      await flow.loadConsents();
      expect(backend.calls('GET', '/scribe-consents').single.url.queryParameters['patientRef'], ref);
      expect(flow.consent?.requestId, 'r2');
      expect(flow.consentState, 'pending');
      expect(flow.waitsForPatient, isTrue, reason: 'ждём ответа и сессии нет — экран опрашивает каждые 5 с');

      backend.routes['/scribe-consents'] = <Object?>[];
      await flow.loadConsents();
      expect(flow.consentState, 'none');
      expect(flow.waitsForPatient, isFalse);
    });

    test('сбой опроса не стирает известное состояние, а кладёт ошибку рядом', () async {
      final (flow, backend) = await flowWith({'/scribe-consents': [consent('r1', 'granted')]});
      await flow.loadConsents();
      backend.routes['/scribe-consents'] = problem(503, 'Service Unavailable');
      await flow.loadConsents();
      expect(flow.consentState, 'granted');
      expect(flow.consentsError, isA<ApiException>());
      backend.routes['/scribe-consents'] = [consent('r1', 'granted')];
      await flow.loadConsents();
      expect(flow.consentsError, isNull);
    });

    test('запрос согласия: тело с рефом, свежий ключ идемпотентности на каждое нажатие, затем перечитывание', () async {
      var list = <Map<String, Object?>>[];
      final (flow, backend) = await flowWith({
        '/scribe-consents': consentsOf(() => list),
        'POST /scribe-consents': (http.Request r) {
          list = [consent('r9', 'pending')];
          return recorded('r9');
        },
      });
      await flow.loadConsents();
      expect(await flow.askConsent(), isTrue);
      final call = backend.calls('POST', '/scribe-consents').single;
      expect(jsonDecode(call.body), {'patientRef': ref});
      expect(call.headers['Idempotency-Key'], isNotEmpty);
      expect(flow.consentState, 'pending');
      expect(flow.consentBusy, isFalse);

      list = [consent('r8', 'declined')];
      await flow.loadConsents();
      await flow.askConsent();
      final keys = backend.calls('POST', '/scribe-consents').map((r) => r.headers['Idempotency-Key']).toSet();
      expect(keys, hasLength(2), reason: 'новое нажатие — новый ключ');
    });

    test('409 «Запрос уже отправлен» не ошибка: список перечитывается, false — без тоста', () async {
      final (flow, backend) = await flowWith({
        '/scribe-consents': [consent('r1', 'pending')],
        'POST /scribe-consents': problem(409, 'Запрос уже отправлен', detail: 'у пациента уже есть действующий запрос согласия на сегодня'),
      });
      expect(await flow.askConsent(), isFalse);
      expect(backend.calls('GET', '/scribe-consents'), hasLength(1));
      expect(flow.consentState, 'pending');
    });

    test('двойное нажатие «Запросить» уходит на сервер одним запросом', () async {
      final (flow, backend) = await flowWith({'/scribe-consents': <Object?>[], 'POST /scribe-consents': recorded('r1')});
      await Future.wait([flow.askConsent(), flow.askConsent()]);
      expect(backend.calls('POST', '/scribe-consents'), hasLength(1));
    });

    test('отмена запроса: POST …/cancel с рефом, без ключа идемпотентности; ошибка — после перечитывания', () async {
      var list = [consent('r1', 'granted')];
      final (flow, backend) = await flowWith({
        '/scribe-consents': consentsOf(() => list),
        'POST /cancel': (http.Request r) {
          list = [consent('r1', 'cancelled')];
          return recorded();
        },
      });
      await flow.loadConsents();
      await flow.cancelConsent();
      final call = backend.calls('POST', '/scribe-consents/r1/cancel').single;
      expect(jsonDecode(call.body), {'patientRef': ref});
      expect(call.headers.containsKey('Idempotency-Key'), isFalse);
      expect(flow.consentState, 'cancelled');

      list = [consent('r2', 'pending')];
      backend.routes['POST /cancel'] = problem(409, 'Действие недоступно', detail: 'запрос уже закрыт или запись начата — отменить нельзя');
      await flow.loadConsents();
      list = [consent('r2', 'granted')];
      await expectLater(flow.cancelConsent(), throwsA(isA<ApiException>().having((e) => e.status, 'status', 409)));
      expect(flow.consentState, 'granted', reason: '409 — сначала перечитали');
    });
  });

  group('сервис скрайба', () {
    test('состояние модели читается; сбой сети — «сервис не запущен»; 429 — «позже», не «недоступен»', () async {
      final (flow, backend) = await flowWith({'/scribe/health': {...health, 'transcriberState': 'loading'}});
      await flow.loadHealth();
      expect(flow.health?.transcriberState, 'loading');
      expect(flow.pollHealth, isTrue, reason: 'опрос 12 с, пока модель грузится');
      expect(flow.serviceDown, isFalse);

      backend.routes['/scribe/health'] = problem(429, 'Too Many Requests');
      await flow.loadHealth();
      expect(flow.healthRateLimited, isTrue);
      expect(flow.serviceDown, isFalse);
      expect(flow.health, isNotNull, reason: 'прежнее состояние остаётся');
      expect(flow.pollHealth, isTrue);

      backend.routes['/scribe/health'] = problem(502, 'Bad Gateway');
      await flow.loadHealth();
      expect(flow.serviceDown, isTrue);
      expect(flow.health, isNull);

      backend.routes['/scribe/health'] = health;
      await flow.loadHealth();
      expect(flow.serviceDown, isFalse);
      expect(flow.pollHealth, isFalse);
    });
  });

  group('сессия записи', () {
    test('начать: consentId и язык приёма без ключа идемпотентности; язык после начала не меняется', () async {
      var list = [consent('r1', 'granted')];
      final (flow, backend) = await flowWith({
        '/scribe-consents': consentsOf(() => list),
        'POST /scribe/sessions': (http.Request r) {
          list = [consent('r1', 'recording', sessionId: 's1')];
          return json({'sessionId': 's1', 'consentId': 'r1', 'patientRef': ref}, 201);
        },
      }, language: 'kk');
      await flow.loadConsents();
      await flow.loadHealth();
      expect(flow.canStart, isTrue);
      await flow.start();
      final call = backend.calls('POST', '/scribe/sessions').single;
      expect(jsonDecode(call.body), {'consentId': 'r1', 'language': 'kk'});
      expect(call.headers.containsKey('Idempotency-Key'), isFalse);
      expect(flow.sessionId, 's1');
      expect(flow.consentState, 'recording');
      flow.setLanguage('ru');
      expect(flow.language, 'kk');
    });

    test('без согласия или без живого сервиса начать нельзя', () async {
      final (flow, backend) = await flowWith({'/scribe-consents': [consent('r1', 'pending')], '/scribe/health': problem(503, 'Скрайб недоступен')});
      await flow.loadConsents();
      await flow.loadHealth();
      expect(flow.canStart, isFalse);
      backend.routes['/scribe-consents'] = [consent('r1', 'granted')];
      await flow.loadConsents();
      expect(flow.canStart, isFalse, reason: 'сервис не отвечает');
      await flow.start();
      expect(backend.calls('POST', '/scribe/sessions'), isEmpty);
    });

    test('409 при начале: список согласий перечитан до того, как экран покажет текст', () async {
      var list = [consent('r1', 'granted')];
      final (flow, _) = await flowWith({
        '/scribe-consents': consentsOf(() => list),
        'POST /scribe/sessions': (http.Request r) {
          list = [consent('r1', 'withdrawn')];
          return problem(409, 'Действие недоступно', detail: 'пациент не дал согласия на запись');
        },
      });
      await flow.loadConsents();
      await flow.loadHealth();
      await expectLater(flow.start(), throwsA(isA<ApiException>()));
      expect(flow.consentState, 'withdrawn');
      expect(flow.hasSession, isFalse);
    });

    test('продолжить начатую запись: язык и фразы восстанавливаются, запись приёма и памятка собираются', () async {
      final (flow, backend) = await flowWith({
        '/scribe-consents': [consent('r1', 'recording', sessionId: 's7')],
        '/scribe/sessions/s7': {
          'sessionId': 's7',
          'language': 'kk',
          'approved': false,
          'transcript': [segment('Қысым 150-95.'), segment('Таңертең 5 мг амлодипин тағайындаймын.', t0: 4)],
        },
      });
      await flow.loadConsents();
      await flow.resume();
      expect(backend.calls('GET', '/scribe/sessions/s7'), hasLength(1));
      expect(flow.sessionId, 's7');
      expect(flow.language, 'kk');
      expect(flow.segments, hasLength(2));
      expect(flow.recordText, 'Қысым 150-95.\nТаңертең 5 мг амлодипин тағайындаймын.');
      expect(flow.leaflet.split('\n').first, 'Қабылдаудан кейін не істеу керек:', reason: 'памятка — на языке приёма');
    });

    test('404 при продолжении — запись потеряна: остаётся только отмена', () async {
      final (flow, _) = await flowWith({
        '/scribe-consents': [consent('r1', 'recording', sessionId: 's7')],
        '/scribe/sessions/s7': problem(404, 'Скрайб', detail: 'session not found'),
      });
      await flow.loadConsents();
      await flow.resume();
      expect(flow.sessionLost, isTrue);
      expect(flow.hasSession, isFalse);
    });

    test('отмена записи: POST …/discard с рефом без ключа; сессия сброшена, согласие перечитано', () async {
      var list = [consent('r1', 'recording', sessionId: 's7')];
      final (flow, backend) = await flowWith({
        '/scribe-consents': consentsOf(() => list),
        '/scribe/sessions/s7': {'sessionId': 's7', 'language': 'ru', 'approved': false, 'transcript': [segment('Жалоб нет.')]},
        'POST /discard': (http.Request r) {
          list = [consent('r1', 'discarded')];
          return recorded();
        },
      });
      await flow.loadConsents();
      await flow.resume();
      await flow.discard();
      final call = backend.calls('POST', '/scribe-consents/r1/discard').single;
      expect(jsonDecode(call.body), {'patientRef': ref});
      expect(call.headers.containsKey('Idempotency-Key'), isFalse);
      expect(flow.hasSession, isFalse);
      expect(flow.segments, isEmpty);
      expect(flow.consentState, 'discarded');
    });
  });

  group('стенограмма, запись приёма и памятка', () {
    Future<(ScribeFlow, DemoBackend)> recordingFlow(Map<String, Object?> api) async {
      final pair = await flowWith({
        '/scribe-consents': [consent('r1', 'recording', sessionId: 's1')],
        '/scribe/sessions/s1': {'sessionId': 's1', 'language': 'ru', 'approved': false, 'transcript': <Object?>[]},
        ...api,
      });
      await pair.$1.loadConsents();
      await pair.$1.resume();
      return pair;
    }

    test('вставленный текст → фразы; запись приёма следует за стенограммой, пока врач её не правил', () async {
      final (flow, backend) = await recordingFlow({
        'POST /transcript': {'transcript': [segment('Давление 150 на 95.'), segment('Назначаю амлодипин 5 мг утром.', t0: 4)]},
      });
      await flow.useText('Давление 150 на 95. Назначаю амлодипин 5 мг утром.');
      expect(backend.lastBody('POST', '/scribe/sessions/s1/transcript'), {'text': 'Давление 150 на 95. Назначаю амлодипин 5 мг утром.'});
      expect(flow.recordText, 'Давление 150 на 95.\nНазначаю амлодипин 5 мг утром.');
      expect(flow.leaflet, contains('- Назначаю амлодипин 5 мг утром.'));
      expect(flow.canApprove, isTrue);

      flow.editRecord('Свой текст');
      backend.routes['POST /segments/0'] = {'transcript': [segment('Давление 140 на 90.', original: 'Давление 150 на 95.', source: 'doctor'), segment('Назначаю амлодипин 5 мг утром.', t0: 4)]};
      await flow.saveSegment(0, '  Давление 140 на 90. ');
      expect(backend.lastBody('POST', '/scribe/sessions/s1/segments/0'), {'text': 'Давление 140 на 90.'});
      expect(flow.recordText, 'Свой текст', reason: 'правка врача не затирается');
      expect(flow.transcriptChanged, isTrue);
      flow.replaceRecord();
      expect(flow.recordText, 'Давление 140 на 90.\nНазначаю амлодипин 5 мг утром.');
      expect(flow.transcriptChanged, isFalse);
    });

    test('правленая врачом памятка не пересобирается, пока он не попросит', () async {
      final (flow, backend) = await recordingFlow({'POST /transcript': {'transcript': [segment('Жалоб нет.')]}});
      await flow.useText('Жалоб нет.');
      flow.editLeaflet('Моя памятка');
      backend.routes['POST /transcript'] = {'transcript': [segment('Назначен покой.')]};
      await flow.useText('Назначен покой.');
      expect(flow.leaflet, 'Моя памятка');
      expect(flow.leafletDirty, isTrue);
      flow.rebuildLeaflet();
      expect(flow.leaflet, contains('- Назначен покой.'));
    });

    test('исправление терминов: применяется только при изменениях; ответ с aiError — не ошибка', () async {
      final (flow, backend) = await recordingFlow({
        'POST /transcript': {'transcript': [segment('амлодепин 5 мг')]},
        'POST /correct': {'transcript': [segment('амлодипин 5 мг', original: 'амлодепин 5 мг', source: 'dictionary')], 'changed': 1, 'aiError': 'model down'},
      });
      await flow.useText('амлодепин 5 мг');
      final correction = await flow.correctTerms();
      expect(correction.changed, 1);
      expect(correction.aiError, 'model down');
      expect(flow.segments.single.source, 'dictionary');
      expect(flow.recordText, 'амлодипин 5 мг');

      backend.routes['POST /correct'] = {'transcript': [segment('другое')], 'changed': 0};
      await flow.correctTerms();
      expect(flow.segments.single.text, 'амлодипин 5 мг', reason: 'changed 0 — стенограмма не меняется');
    });

    test('утверждение: один раздел «Запись приёма» и памятка, без ключа идемпотентности; результат с токеном', () async {
      var list = [consent('r1', 'recording', sessionId: 's1')];
      final (flow, backend) = await recordingFlow({
        '/scribe-consents': consentsOf(() => list),
        'POST /transcript': {'transcript': [segment('Назначен покой.')]},
        'POST /approve': (http.Request r) {
          list = [consent('r1', 'completed', token: 'tok-1')];
          return json({'leafletToken': 'tok-1', 'audioDeleted': true, 'consentId': 'r1'});
        },
      });
      await flow.useText('Назначен покой.');
      await flow.approve('Запись приёма');
      final call = backend.calls('POST', '/scribe/sessions/s1/approve').single;
      expect(jsonDecode(call.body), {
        'sections': [
          {'name': 'Запись приёма', 'text': 'Назначен покой.'},
        ],
        'patientLeaflet': flow.leaflet,
      });
      expect(call.headers.containsKey('Idempotency-Key'), isFalse);
      expect(flow.approved, isTrue);
      expect(flow.result?.leafletToken, 'tok-1');
      expect(flow.consentState, 'completed');
      expect(flow.canApprove, isFalse);

      await flow.newVisit();
      expect(flow.hasSession, isFalse);
      expect(flow.approved, isFalse);
    });

    test('409 при утверждении (запись отменена или истекла): согласие перечитано, сессия закрыта', () async {
      var list = [consent('r1', 'recording', sessionId: 's1')];
      final (flow, _) = await recordingFlow({
        '/scribe-consents': consentsOf(() => list),
        'POST /transcript': {'transcript': [segment('Назначен покой.')]},
        'POST /approve': (http.Request r) {
          list = [consent('r1', 'expired')];
          return problem(409, 'Действие недоступно', detail: 'запись отменена или истекла — для нового приёма нужно новое согласие');
        },
      });
      await flow.useText('Назначен покой.');
      await expectLater(flow.approve('Запись приёма'), throwsA(isA<ApiException>()));
      expect(flow.consentState, 'expired');
      expect(flow.hasSession, isFalse, reason: 'экран возвращается к шагам и показывает настоящее состояние');
    });

    test('404 сессии при работе: запись потеряна, сессия закрыта, остаётся отмена', () async {
      final (flow, _) = await recordingFlow({'POST /transcript': problem(404, 'Скрайб', detail: 'session not found')});
      await expectLater(flow.useText('текст'), throwsA(isA<ApiException>()));
      expect(flow.hasSession, isFalse);
      expect(flow.sessionLost, isTrue);
    });

    test('422 «речь не распознана» оставляет сессию открытой', () async {
      final (flow, _) = await recordingFlow({'POST /audio': problem(422, 'Скрайб', detail: 'речь не распознана: запись слишком короткая или тихая — запишите ещё раз или вставьте текст')});
      await expectLater(flow.uploadAudio([1, 2, 3], 'consult.m4a'), throwsA(isA<ApiException>()));
      expect(flow.hasSession, isTrue);
      expect(flow.processing, isFalse);
    });
  });
}
