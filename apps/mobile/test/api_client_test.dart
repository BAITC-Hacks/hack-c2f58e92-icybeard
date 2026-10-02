import 'dart:convert';
import 'dart:io';

import 'package:darumen/api/client.dart';
import 'package:darumen/api/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fixtures/api/api_fixtures.dart';

const ref = 'SYN-75-028B-381-01';
const created = {'decisionId': 'rec-1', 'recordedAt': '2026-10-01T00:00:00+00:00'};

/// Ответ API с JSON-телом в UTF-8 (как у сервера); null — пустое тело (204).
http.Response jsonResponse(Object? body, int status) => http.Response.bytes(
      body == null ? const <int>[] : utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

/// Записывает каждый запрос и отвечает одним и тем же телом на любой путь — чтобы проверить, что именно отправил
/// клиент (метод, путь, query, заголовки, тело), независимо от разбора ответа.
class RequestLog {
  final requests = <http.Request>[];

  ApiClient client({Object? body = created, int status = 201, String? token, String locale = 'ru'}) => ApiClient(
        baseUrl: 'https://api.test',
        tokenProvider: () async => token,
        locale: () => locale,
        client: MockClient((request) async {
          requests.add(request);
          return jsonResponse(body, status);
        }),
      );

  http.Request get last => requests.last;
  Map<String, dynamic> get lastBody => jsonDecode(last.body) as Map<String, dynamic>;
  Map<String, String> get lastQuery => last.url.queryParameters;
  String? get lastKey => last.headers['Idempotency-Key'];

  /// Последний запрос — POST на [path] с телом [body] и ключом [key] (null — без Idempotency-Key).
  void expectPost(String path, Map<String, Object?> body, String? key) {
    expect(last.method, 'POST');
    expect(last.url.path, path);
    expect(lastBody, body);
    expect(lastKey, key);
  }
}

void main() {
  group('common request shape', () {
    test('every request carries Accept, Accept-Language and the bearer token when signed in', () async {
      final log = RequestLog();
      await log.client(body: const {'items': []}, status: 200, token: 'tok-1', locale: 'kk').regions();
      expect(log.last.headers['Accept'], 'application/json');
      expect(log.last.headers['Accept-Language'], 'kk');
      expect(log.last.headers['Authorization'], 'Bearer tok-1');
    });

    test('without a token no Authorization header is sent', () async {
      final log = RequestLog();
      await log.client(body: const {'items': []}, status: 200).regions();
      expect(log.last.headers.containsKey('Authorization'), isFalse);
    });

    test('path parameters are percent-encoded', () async {
      final log = RequestLog();
      await log.client(body: null, status: 204).markRouteNotificationRead('a/b c');
      expect(log.last.url.path, '/api/v1/route/me/notifications/a%2Fb%20c/read');
    });

    test('a journal write returns the decisionId, and a 200 replay of the same key counts as success', () async {
      final log = RequestLog();
      expect(await log.client(body: const {'decisionId': 'stored', 'recordedAt': 'x'}, status: 200).keepRoute(ref, reason: 'r', idempotencyKey: 'k'), 'stored');
    });

    test('an API error from a journal write surfaces as ApiException with the state code', () async {
      const body = '{"title":"Пациент ещё не согласился","status":409,"detail":"нельзя подтвердить приём, пока пациент не принял перевод",'
          '"status":"transfer_pending_consent"}';
      final api = ApiClient(
        baseUrl: 'https://api.test',
        client: MockClient((r) async => http.Response.bytes(utf8.encode(body), 409, headers: {'content-type': 'application/problem+json; charset=utf-8'})),
      );
      await expectLater(
        api.confirmReferral('d-1', patientRef: ref, plannedAt: '2026-10-10', idempotencyKey: 'k'),
        throwsA(isA<ApiException>().having((e) => e.isConflict, 'isConflict', isTrue).having((e) => e.stateCode, 'stateCode', 'transfer_pending_consent')),
      );
    });
  });

  group('newIdempotencyKey', () {
    test('is 32 lowercase hex characters (128 random bits)', () {
      expect(newIdempotencyKey(), matches(RegExp(r'^[0-9a-f]{32}$')));
    });

    test('a fresh key per call', () {
      final keys = {for (var i = 0; i < 200; i++) newIdempotencyKey()};
      expect(keys, hasLength(200));
    });
  });

  group('citizen: /route/me/* (route.own)', () {
    test('myRoute passes regionKato only when given', () async {
      final log = RequestLog();
      final api = log.client(body: jsonDecode(File('test/fixtures/api/route-me.json').readAsStringSync()), status: 200);
      await api.myRoute(regionKato: '75');
      expect(log.lastQuery['regionKato'], '75');
      await api.myRoute(regionKato: '');
      expect(log.last.url.hasQuery, isFalse, reason: 'пустой регион не отправляется');
    });

    test('sendRouteSignal posts kind, optional toMoCode and comment, regionKato and the key', () async {
      final log = RequestLog();
      final id = await log.client().sendRouteSignal(RouteCodes.requestRedirect, toMoCode: '22GN', comment: 'живу рядом', idempotencyKey: 'k-s', regionKato: '75');
      expect(id, 'rec-1');
      expect(log.last.method, 'POST');
      expect(log.last.url.path, '/api/v1/route/me/signals');
      expect(log.lastQuery, {'regionKato': '75'});
      expect(log.lastKey, 'k-s');
      expect(log.lastBody, {'kind': 'request_redirect', 'toMoCode': '22GN', 'comment': 'живу рядом'});
    });

    test('sendRouteSignal omits a null toMoCode and an empty comment; prefer_current is a plain kind', () async {
      final log = RequestLog();
      await log.client().sendRouteSignal(RouteCodes.preferCurrent, comment: '', idempotencyKey: 'k-14');
      expect(log.lastBody, {'kind': 'prefer_current'});
      expect(log.last.url.hasQuery, isFalse);
    });

    test('answerTransfer: accepted is always sent explicitly, even when declining (§4.8)', () async {
      final log = RequestLog();
      await log.client().answerTransfer(decisionId: 't-1', accepted: false, reason: 'передумал', idempotencyKey: 'k-2', regionKato: '75');
      expect(log.last.url.path, '/api/v1/route/me/consent');
      expect(log.lastQuery['regionKato'], '75');
      expect(log.lastKey, 'k-2');
      expect(log.lastBody, {'decisionId': 't-1', 'accepted': false, 'reason': 'передумал'});
    });

    test('answerTransfer: accepting omits an absent or empty reason but still sends accepted:true', () async {
      final log = RequestLog();
      await log.client().answerTransfer(decisionId: 't-1', accepted: true, reason: '', idempotencyKey: 'k-3');
      expect(log.lastBody, {'decisionId': 't-1', 'accepted': true});
      expect(log.lastQuery.containsKey('regionKato'), isFalse);
    });

    test('routeNotifications parses the real sample and passes regionKato', () async {
      final log = RequestLog();
      final sample = jsonDecode(File('test/fixtures/api/route-me-notifications.json').readAsStringSync());
      final result = await log.client(body: sample, status: 200).routeNotifications(regionKato: '75');
      expect(log.last.method, 'GET');
      expect(log.last.url.path, '/api/v1/route/me/notifications');
      expect(log.lastQuery['regionKato'], '75');
      expect(result.unread, 4);
      expect(result.items.first.kind, RouteCodes.redirect);
      expect(result.items.first.needsAction, isTrue);
    });

    test('markRouteNotificationRead posts {} without a key and returns on 204', () async {
      final log = RequestLog();
      await log.client(body: null, status: 204).markRouteNotificationRead('n-1', regionKato: '75');
      expect(log.last.method, 'POST');
      expect(log.last.url.path, '/api/v1/route/me/notifications/n-1/read');
      expect(log.lastQuery['regionKato'], '75');
      expect(log.lastBody, isEmpty);
      expect(log.lastKey, isNull);
    });

    test('myScribe parses a bare array and passes regionKato', () async {
      final log = RequestLog();
      final list = await log.client(body: [
        {'requestId': 'r-1', 'patientRef': ref, 'requestedRole': 'doctor', 'requestedAt': '2026-10-01T00:00:00+00:00', 'day': '2026-10-01', 'status': 'pending'},
      ], status: 200).myScribe(regionKato: '75');
      expect(log.last.url.path, '/api/v1/route/me/scribe');
      expect(log.lastQuery['regionKato'], '75');
      expect(list.single.requestId, 'r-1');
      expect(list.single.status, RouteCodes.scribePending);
    });

    test('myScribe of a citizen without a route is an empty list', () async {
      expect(await RequestLog().client(body: const [], status: 200).myScribe(), isEmpty);
    });

    test('answerScribe always sends granted explicitly (§4.8), with the key and regionKato', () async {
      final log = RequestLog();
      await log.client().answerScribe('r-1', granted: false, idempotencyKey: 'k-4', regionKato: '75');
      expect(log.last.url.path, '/api/v1/route/me/scribe/r-1/answer');
      expect(log.lastQuery['regionKato'], '75');
      expect(log.lastBody, {'granted': false});
      expect(log.lastKey, 'k-4');
    });
  });

  group('doctor: route actions (referral.confirm)', () {
    test('redirectRoute sends toMoCode/reason and the key, without severe when false', () async {
      final log = RequestLog();
      await log.client().redirectRoute(ref, toMoCode: '22GN', reason: 'ближе', idempotencyKey: 'k-1');
      expect(log.last.url.path, '/api/v1/route/$ref/redirect');
      expect(log.lastKey, 'k-1');
      expect(log.lastBody, {'toMoCode': '22GN', 'reason': 'ближе'});
    });

    test('redirectRoute adds severe:true only when severe is true', () async {
      final log = RequestLog();
      await log.client().redirectRoute(ref, toMoCode: '22GN', reason: 'тяжёлый', idempotencyKey: 'k-1', severe: true);
      expect(log.lastBody, {'toMoCode': '22GN', 'reason': 'тяжёлый', 'severe': true});
    });

    test('keepRoute, cancelTransfer and closeRoute post a reason with the key', () async {
      final log = RequestLog();
      final api = log.client();
      await api.keepRoute(ref, reason: 'профиль', idempotencyKey: 'k-k');
      log.expectPost('/api/v1/route/$ref/keep', {'reason': 'профиль'}, 'k-k');
      await api.cancelTransfer(ref, reason: 'ошиблись с выбором', idempotencyKey: 'k-5');
      log.expectPost('/api/v1/route/$ref/cancel-transfer', {'reason': 'ошиблись с выбором'}, 'k-5');
      await api.closeRoute(ref, reason: 'пациент не пришёл', idempotencyKey: 'k-6');
      log.expectPost('/api/v1/route/$ref/close', {'reason': 'пациент не пришёл'}, 'k-6');
    });

    test('recordDecision posts the referral decision as given, with the key as a named argument', () async {
      final log = RequestLog();
      final decision = {'subject': 'referral', 'subjectId': '75.028B.381.mobile', 'chosen': {'moCode': '22GN'}, 'reason': 'ближе'};
      expect(await log.client().recordDecision(decision, idempotencyKey: 'k-d'), 'rec-1');
      expect(log.last.url.path, '/api/v1/journal/decisions');
      expect(log.lastBody, decision);
      expect(log.lastKey, 'k-d');
    });
  });

  group('receiving hospital: incoming referrals (§3.6)', () {
    test('sends moCode and includeConfirmed=true by default, severe only when given', () async {
      final log = RequestLog();
      final list = await log.client(body: const [], status: 200).incomingReferrals(moCode: '028B');
      expect(log.last.method, 'GET');
      expect(log.last.url.path, '/api/v1/journal/referrals/incoming');
      expect(log.lastQuery, {'moCode': '028B', 'includeConfirmed': 'true'});
      expect(list, isEmpty);
    });

    test('severe and includeConfirmed=false are sent when given', () async {
      final log = RequestLog();
      await log.client(body: const [], status: 200).incomingReferrals(severe: true, includeConfirmed: false);
      expect(log.lastQuery, {'severe': 'true', 'includeConfirmed': 'false'});
    });

    test('parses a real-shaped row into IncomingReferral', () async {
      final list = await RequestLog().client(body: [
        {
          'decisionId': 'd-1',
          'patientRef': ref,
          'fromMoCode': '028B',
          'profileCode': '381',
          'recordedAt': '2026-01-01T00:00:00+00:00',
          'patientConsent': 'accepted',
          'status': 'transfer_pending_confirmation',
          'allowed': ['confirm', 'reject'],
        },
      ], status: 200).incomingReferrals();
      expect(list.single.decisionId, 'd-1');
      expect(list.single.allowed, ['confirm', 'reject']);
    });

    test('without a hospital the real 422 «Нужна организация» is an ApiException (fixture incoming.json)', () async {
      final body = File('test/fixtures/api/incoming.json').readAsBytesSync();
      final api = ApiClient(baseUrl: 'https://api.test', client: MockClient((r) async => http.Response.bytes(body, 422)));
      await expectLater(api.incomingReferrals(), throwsA(isA<ApiException>().having((e) => e.title, 'title', 'Нужна организация')));
    });
  });

  group('receiving hospital: referral actions — patientRef in the body, Idempotency-Key always', () {
    test('confirmReferral sends patientRef, plannedAt and an optional comment', () async {
      final log = RequestLog();
      await log.client().confirmReferral('d-1', patientRef: ref, plannedAt: '2026-10-10', comment: 'ок', idempotencyKey: 'k-7');
      expect(log.last.url.path, '/api/v1/journal/referrals/d-1/confirm');
      expect(log.lastBody, {'patientRef': ref, 'plannedAt': '2026-10-10', 'comment': 'ок'});
      expect(log.lastKey, 'k-7');
    });

    test('confirmReferral omits an absent or empty comment', () async {
      final log = RequestLog();
      await log.client().confirmReferral('d-1', patientRef: ref, plannedAt: '2026-10-10', comment: '', idempotencyKey: 'k-7b');
      expect(log.lastBody, {'patientRef': ref, 'plannedAt': '2026-10-10'});
    });

    test('rejectReferral and rescheduleReferral send their required fields', () async {
      final log = RequestLog();
      final api = log.client();
      await api.rejectReferral('d-1', patientRef: ref, reason: 'нет мест', idempotencyKey: 'k-8');
      log.expectPost('/api/v1/journal/referrals/d-1/reject', {'patientRef': ref, 'reason': 'нет мест'}, 'k-8');
      await api.rescheduleReferral('d-1', patientRef: ref, plannedAt: '2026-10-15', reason: 'перенос', idempotencyKey: 'k-9');
      log.expectPost('/api/v1/journal/referrals/d-1/reschedule', {'patientRef': ref, 'plannedAt': '2026-10-15', 'reason': 'перенос'}, 'k-9');
    });

    test('admitReferral and noShowReferral send patientRef and an optional reason', () async {
      final log = RequestLog();
      final api = log.client();
      await api.admitReferral('d-1', patientRef: ref, idempotencyKey: 'k-10');
      log.expectPost('/api/v1/journal/referrals/d-1/admit', {'patientRef': ref}, 'k-10');
      await api.admitReferral('d-1', patientRef: ref, reason: 'по плану', idempotencyKey: 'k-10b');
      expect(log.lastBody, {'patientRef': ref, 'reason': 'по плану'});
      await api.noShowReferral('d-1', patientRef: ref, idempotencyKey: 'k-11');
      log.expectPost('/api/v1/journal/referrals/d-1/no-show', {'patientRef': ref}, 'k-11');
      await api.noShowReferral('d-1', patientRef: ref, reason: 'не дозвонились', idempotencyKey: 'k-11b');
      expect(log.lastBody, {'patientRef': ref, 'reason': 'не дозвонились'});
    });

    test('dischargeReferral sends patientRef and the required summary', () async {
      final log = RequestLog();
      await log.client().dischargeReferral('d-1', patientRef: ref, summary: 'выписан в срок', idempotencyKey: 'k-12');
      expect(log.last.url.path, '/api/v1/journal/referrals/d-1/discharge');
      expect(log.lastBody, {'patientRef': ref, 'summary': 'выписан в срок'});
      expect(log.lastKey, 'k-12');
    });
  });

  group('doctor bell (§3.8)', () {
    test('doctorBell passes moCode and parses the envelope', () async {
      final log = RequestLog();
      final bell = await log.client(body: const {'pendingIncomingCount': 2}, status: 200).doctorBell(moCode: '028B');
      expect(log.last.url.path, '/api/v1/journal/notifications/bell');
      expect(log.lastQuery['moCode'], '028B');
      expect(bell.pendingIncomingCount, 2);
    });

    test('markBellRead posts {} to kind/id/read without a key and tolerates 204', () async {
      final log = RequestLog();
      await log.client(body: null, status: 204).markBellRead(RouteCodes.bellPatientSignal, 's-1');
      expect(log.last.method, 'POST');
      expect(log.last.url.path, '/api/v1/journal/notifications/bell/patient-signal/s-1/read');
      expect(log.lastBody, isEmpty);
      expect(log.lastKey, isNull);
    });
  });

  group('scribe consents: doctor side (§3.10.1)', () {
    test('scribeConsents GET passes patientRef and parses a bare array', () async {
      final log = RequestLog();
      expect(await log.client(body: const [], status: 200).scribeConsents(ref), isEmpty);
      expect(log.last.url.path, '/api/v1/scribe-consents');
      expect(log.lastQuery, {'patientRef': ref});
    });

    test('requestScribeConsent sends patientRef/comment with the key and returns the new requestId', () async {
      final log = RequestLog();
      final id = await log.client(body: const {'decisionId': 'req-9', 'recordedAt': 'x'}).requestScribeConsent(ref, comment: 'плановый приём', idempotencyKey: 'k-13');
      expect(id, 'req-9');
      expect(log.last.url.path, '/api/v1/scribe-consents');
      expect(log.lastBody, {'patientRef': ref, 'comment': 'плановый приём'});
      expect(log.lastKey, 'k-13');
    });

    test('requestScribeConsent omits an absent comment', () async {
      final log = RequestLog();
      await log.client().requestScribeConsent(ref, idempotencyKey: 'k-13b');
      expect(log.lastBody, {'patientRef': ref});
    });

    test('cancelScribeConsent and discardScribeRecording send patientRef without a key (§4.6)', () async {
      final log = RequestLog();
      final api = log.client();
      await api.cancelScribeConsent('r-1', ref);
      log.expectPost('/api/v1/scribe-consents/r-1/cancel', {'patientRef': ref}, null);
      await api.discardScribeRecording('r-2', ref);
      log.expectPost('/api/v1/scribe-consents/r-2/discard', {'patientRef': ref}, null);
    });
  });

  group('scribe session (§2.1, §2.2, §3.10.4–§3.10.5)', () {
    test('createScribeSession sends consentId and language, and never an Idempotency-Key', () async {
      final log = RequestLog();
      final session = await log.client(body: const {'sessionId': 's-1', 'consentId': 'c-1', 'patientRef': ref}).createScribeSession(consentId: 'c-1', language: 'kk');
      expect(log.last.url.path, '/api/v1/scribe/sessions');
      expect(log.lastBody, {'consentId': 'c-1', 'language': 'kk'});
      expect(log.lastKey, isNull);
      expect(session.sessionId, 's-1');
      expect(session.consentId, 'c-1');
    });

    test('approveScribe posts sections and patientLeaflet without a key', () async {
      final log = RequestLog();
      final result = await log
          .client(body: const {'leafletToken': 'tok-1', 'audioDeleted': true, 'consentId': 'c-1'}, status: 200)
          .approveScribe('s-1', const [DraftSection(name: 'Запись приёма', text: 'текст')], 'памятка');
      expect(log.last.url.path, '/api/v1/scribe/sessions/s-1/approve');
      expect(log.lastBody, {
        'sections': [
          {'name': 'Запись приёма', 'text': 'текст'},
        ],
        'patientLeaflet': 'памятка',
      });
      expect(log.lastKey, isNull);
      expect(result.leafletToken, 'tok-1');
    });

    test('uploadScribeAudio sends a multipart file and returns segments and text', () async {
      final requests = <http.Request>[];
      final api = ApiClient(
        baseUrl: 'https://api.test',
        tokenProvider: () async => 'tok',
        client: MockClient((request) async {
          requests.add(request);
          return jsonResponse({
            'transcript': [
              {'t0': 0.0, 't1': 4.0, 'text': 'жалобы на боль'},
            ],
            'text': 'жалобы на боль',
            'transcriber': 'whisper',
          }, 200);
        }),
      );
      final upload = await api.uploadScribeAudio('s-1', [1, 2, 3], 'consult.m4a');
      final request = requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/scribe/sessions/s-1/audio');
      expect(request.headers['content-type'], startsWith('multipart/form-data'));
      expect(request.headers['Authorization'], 'Bearer tok');
      expect(utf8.decode(request.bodyBytes), allOf(contains('name="file"'), contains('consult.m4a')));
      expect(upload.text, 'жалобы на боль');
      expect(upload.transcript.single.text, 'жалобы на боль');
    });

    test('setTranscript posts the text and returns the re-split segments', () async {
      final log = RequestLog();
      final segments = await log.client(body: const {
        'transcript': [
          {'t0': 0.0, 't1': 4.0, 'text': 'Первая фраза.'},
          {'t0': 4.0, 't1': 8.0, 'text': 'Вторая.'},
        ],
      }, status: 200).setTranscript('s-1', 'Первая фраза. Вторая.');
      expect(log.last.url.path, '/api/v1/scribe/sessions/s-1/transcript');
      expect(log.lastBody, {'text': 'Первая фраза. Вторая.'});
      expect(segments.map((s) => s.text), ['Первая фраза.', 'Вторая.']);
    });

    test('scribeSession GETs the session by id', () async {
      final log = RequestLog();
      final state = await log.client(body: const {'sessionId': 's-1', 'language': 'ru', 'approved': false}, status: 200).scribeSession('s-1');
      expect(log.last.method, 'GET');
      expect(log.last.url.path, '/api/v1/scribe/sessions/s-1');
      expect(state.sessionId, 's-1');
    });

    test('editScribeSegment posts text to the indexed segment path', () async {
      final log = RequestLog();
      final segments = await log.client(body: const {
        'transcript': [
          {'t0': 0.0, 't1': 1.0, 'text': 'исправлено', 'original': 'исходно', 'source': 'doctor'},
        ],
      }, status: 200).editScribeSegment('s-1', 2, 'исправленный текст');
      expect(log.last.url.path, '/api/v1/scribe/sessions/s-1/segments/2');
      expect(log.lastBody, {'text': 'исправленный текст'});
      expect(segments.single.source, RouteCodes.sourceDoctor);
    });

    test('correctScribeTerms posts an empty body and parses changed/aiError', () async {
      final log = RequestLog();
      final correction = await log.client(body: const {'transcript': [], 'changed': 2, 'aiError': null}, status: 200).correctScribeTerms('s-1');
      expect(log.last.url.path, '/api/v1/scribe/sessions/s-1/correct');
      expect(log.lastBody, isEmpty);
      expect(correction.changed, 2);
    });

    test('scribeHealth GETs the health endpoint', () async {
      final log = RequestLog();
      final health = await log.client(body: const {'status': 'ok', 'transcriber': 'whisper', 'drafter': 'qwen'}, status: 200).scribeHealth();
      expect(log.last.url.path, '/api/v1/scribe/health');
      expect(health.status, 'ok');
    });
  });

  group('existing endpoints keep their verb, path and query', () {
    const predict = {
      'p50Days': 10.0, 'p90Days': 20.0, 'pWithin30Days': 0.9, 'pRefusal': 0.1, //
      'explanation': {'summary': '', 'factors': []},
      'model': {'name': 'wait_quantile', 'version': '1.0.0', 'trainedThrough': '2025-02-28'},
    };
    const check = {'covered': true, 'program': 'ГОБМП', 'fillDaysP50': 3, 'shortage': {'flag': false, 'score': 0.1, 'basis': 'ok'}};

    /// Отвечает по пути запроса: так один клиент обслуживает все вызовы группы.
    (ApiClient, List<http.Request>) routed() {
      final requests = <http.Request>[];
      Object? bodyFor(String path) => switch (path) {
            '/api/v1/queue/predict' => predict,
            '/api/v1/medicines/check' => check,
            '/api/v1/journal/worklist' => apiFixture('worklist.json'),
            '/api/v1/journal/decisions' => apiFixture('decisions.json'),
            '/api/v1/me' => apiFixture('me-doctor.json'),
            final p when p.startsWith('/api/v1/route/') => apiFixture('route-doctor.json'),
            final p when p.startsWith('/api/v1/me/') || p.startsWith('/api/v1/public/') || p.endsWith('route-standard') => const <String, Object?>{},
            _ => const {'items': []},
          };
      final api = ApiClient(
        baseUrl: 'https://api.test',
        client: MockClient((request) async {
          requests.add(request);
          return jsonResponse(bodyFor(request.url.path), 200);
        }),
      );
      return (api, requests);
    }

    test('reference data, forecast and medicines', () async {
      final (api, requests) = routed();
      await api.regions();
      await api.profiles();
      await api.organizations('75', '381');
      await api.organizations('75');
      await api.predict(const {'regionKato': '75'});
      await api.alternatives(const {'regionKato': '75'});
      await api.regionIndex(profileCode: '381');
      await api.routeStandard();
      await api.nosologies();
      await api.mnn('n-1');
      await api.checkMedicine(mnnId: 'm-1', regionKato: '75');
      await api.vaccination();
      expect([for (final r in requests) '${r.method} ${r.url.path}?${r.url.query}'], [
        'GET /api/v1/refdata/regions?',
        'GET /api/v1/refdata/profiles?',
        'GET /api/v1/refdata/organizations?regionKato=75&profileCode=381&limit=100',
        'GET /api/v1/refdata/organizations?regionKato=75&limit=500',
        'POST /api/v1/queue/predict?',
        'POST /api/v1/queue/alternatives?',
        'GET /api/v1/index?profileCode=381',
        'GET /api/v1/refdata/route-standard?',
        'GET /api/v1/medicines/nosologies?limit=30',
        'GET /api/v1/medicines/mnn?nosologyId=n-1&limit=30',
        'POST /api/v1/medicines/check?',
        'GET /api/v1/refdata/vaccination?',
      ]);
      expect(jsonDecode(requests[5].body), {'regionKato': '75', 'limit': 5});
    });

    test('worklist, patient route and the decisions journal parse the real samples', () async {
      final (api, requests) = routed();
      expect((await api.worklistPage(flag: 'patient_signal')).items, isNotEmpty);
      expect((await api.patientRoute('SYN-75-224E-171-01')).patientRef, 'SYN-75-224E-171-01');
      expect(await api.myDecisions(), isNotEmpty);
      expect([for (final r in requests) '${r.method} ${r.url.path}?${r.url.query}'], [
        'GET /api/v1/journal/worklist?flag=patient_signal',
        'GET /api/v1/route/SYN-75-224E-171-01?',
        'GET /api/v1/journal/decisions?actor=me&page=1&size=50',
      ]);
    });

    test('account endpoints', () async {
      final (api, requests) = routed();
      expect((await api.me()).moCode, '028B');
      await api.mySecurity();
      await api.endSession('s/1');
      await api.endOtherSessions();
      final settings = await api.myNotifications();
      await api.saveNotifications(settings);
      await api.requestPasswordReset('a@b.kz');
      expect([for (final r in requests) '${r.method} ${r.url.path}?${r.url.query}'], [
        'GET /api/v1/me?',
        'GET /api/v1/me/security?',
        'DELETE /api/v1/me/sessions/s%2F1?',
        'DELETE /api/v1/me/sessions?keepCurrent=true',
        'GET /api/v1/me/notifications?',
        'PUT /api/v1/me/notifications?',
        'POST /api/v1/public/password-reset?',
      ]);
      expect(jsonDecode(requests.last.body), {'email': 'a@b.kz'});
      api.close();
    });
  });
}
