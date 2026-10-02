import 'dart:convert';
import 'dart:io';

import 'package:darumen/api/client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

ApiClient clientFor(http.Response Function(http.Request request) handler) =>
    ApiClient(baseUrl: 'https://api.test', client: MockClient((request) async => handler(request)));

/// Ответ с телом в UTF-8, как у сервера: `utf8Response(String, …)` без charset в content-type кодирует latin1 и
/// падает на кириллице.
http.Response utf8Response(String body, int status, {Map<String, String> headers = const {}}) =>
    http.Response.bytes(utf8.encode(body), status, headers: {'content-type': 'application/problem+json; charset=utf-8', ...headers});

void main() {
  group('ApiException convenience getters', () {
    test('isConflict is true only for 409', () {
      expect(ApiException(409, 'x').isConflict, isTrue);
      expect(ApiException(404, 'x').isConflict, isFalse);
    });

    test('isValidation is true only for 422', () {
      expect(ApiException(422, 'x').isValidation, isTrue);
      expect(ApiException(409, 'x').isValidation, isFalse);
    });

    test('isForbidden is true only for 403', () {
      expect(ApiException(403, 'x').isForbidden, isTrue);
      expect(ApiException(401, 'x').isForbidden, isFalse);
    });

    test('isNotFound is true only for 404', () {
      expect(ApiException(404, 'x').isNotFound, isTrue);
      expect(ApiException(410, 'x').isNotFound, isFalse);
    });

    test('isRateLimited is true only for 429', () {
      expect(ApiException(429, 'x').isRateLimited, isTrue);
      expect(ApiException(503, 'x').isRateLimited, isFalse);
    });

    test('isServerError covers exactly 500…599', () {
      expect(ApiException(500, 'x').isServerError, isTrue);
      expect(ApiException(502, 'x').isServerError, isTrue);
      expect(ApiException(599, 'x').isServerError, isTrue);
      expect(ApiException(499, 'x').isServerError, isFalse);
      expect(ApiException(600, 'x').isServerError, isFalse);
    });

    test('fieldError() reads the first message for a validation field', () {
      final e = ApiException(422, 'Ошибка валидации', errors: {
        'reason': ['обязательное поле', 'второе сообщение'],
        'empty': [],
      });
      expect(e.fieldError('reason'), 'обязательное поле');
      expect(e.fieldError('missing'), isNull);
      expect(e.fieldError('empty'), isNull, reason: 'пустой список сообщений — тоже null, не исключение');
      expect(ApiException(422, 'x').fieldError('reason'), isNull, reason: 'без errors — null');
    });

    test('the positional constructor keeps working for callers outside lib/api (session.dart)', () {
      final e = ApiException(400, 'invalid_grant', detail: 'Invalid user credentials');
      expect(e.status, 400);
      expect(e.stateCode, isNull);
      expect(e.requestId, isNull);
      expect(e.permissions, isNull);
      expect(e.retryAfterSeconds, isNull);
    });

    test('toString concatenates title and detail, or just the title', () {
      expect(ApiException(409, 'Title only').toString(), 'Title only');
      expect(ApiException(409, 'Title', detail: 'Detail').toString(), 'Title: Detail');
    });
  });

  group('duplicate status key in 409 bodies (§4.1)', () {
    test('status comes from the HTTP status code, stateCode from the body string', () async {
      // Строка — буквальная копия примера из §4.1: ключ status встречается дважды (409 и строка состояния);
      // jsonDecode Dart оставляет последнее значение — строку.
      const body = '{"type":"https://tools.ietf.org/html/rfc9110#section-15.5.10","title":"Ждём ответа пациента",'
          '"status":409,"detail":"по маршруту есть перевод, на который пациент ещё не ответил",'
          '"status":"transfer_pending_consent","traceId":"00-abc-def-00"}';
      final api = clientFor((r) => utf8Response(body, 409, headers: {'content-type': 'application/problem+json'}));
      await expectLater(
        api.get('/api/v1/route/SYN-75-028B-381-01/keep'),
        throwsA(isA<ApiException>()
            .having((e) => e.status, 'status', 409)
            .having((e) => e.stateCode, 'stateCode', 'transfer_pending_consent')
            .having((e) => e.title, 'title', 'Ждём ответа пациента')
            .having((e) => e.detail, 'detail', 'по маршруту есть перевод, на который пациент ещё не ответил')),
      );
    });

    test('stateCode is null when the body has no string status extension', () async {
      final api = clientFor((r) => utf8Response('{"title":"Пациент не найден","status":404}', 404));
      await expectLater(api.get('/x'), throwsA(isA<ApiException>().having((e) => e.stateCode, 'stateCode', isNull)));
    });
  });

  group('requestId extension (§4.1, 409 from POST /scribe-consents)', () {
    test('requestId is read from the body when present', () async {
      const body = '{"title":"Запрос уже отправлен","status":409,'
          '"detail":"у пациента уже есть действующий запрос согласия на сегодня",'
          '"requestId":"9f2c1a30-1111-2222-3333-444455556666","status":"pending"}';
      final api = clientFor((r) => utf8Response(body, 409));
      await expectLater(
        api.post('/api/v1/scribe-consents', const {'patientRef': 'SYN-75-028B-381-01'}),
        throwsA(isA<ApiException>()
            .having((e) => e.requestId, 'requestId', '9f2c1a30-1111-2222-3333-444455556666')
            .having((e) => e.stateCode, 'stateCode', 'pending')),
      );
    });

    test('requestId is null when absent', () async {
      final api = clientFor((r) => utf8Response('{"title":"x","status":409}', 409));
      await expectLater(api.get('/x'), throwsA(isA<ApiException>().having((e) => e.requestId, 'requestId', isNull)));
    });
  });

  group('permissions extension (§4.1, 403 permission_required)', () {
    test('permissions list is parsed from the body', () async {
      const body = '{"title":"Нет доступа к разделу","status":403,"detail":"permission_required",'
          '"permissions":["referral.confirm","worklist.view"]}';
      final api = clientFor((r) => utf8Response(body, 403));
      await expectLater(
        api.get('/api/v1/journal/worklist'),
        throwsA(isA<ApiException>()
            .having((e) => e.isForbidden, 'isForbidden', isTrue)
            .having((e) => e.permissions, 'permissions', ['referral.confirm', 'worklist.view'])),
      );
    });

    test('permissions is null for a plain 403 without the extension', () async {
      final api = clientFor((r) => utf8Response('{"title":"Данные другой организации","status":403}', 403));
      await expectLater(api.get('/x'), throwsA(isA<ApiException>().having((e) => e.permissions, 'permissions', isNull)));
    });
  });

  group('Retry-After header on 429 (§4.9)', () {
    test('retryAfterSeconds is parsed from the response header', () async {
      final api = clientFor((r) => utf8Response('{"title":"Слишком много запросов","status":429,"detail":"rate_limited"}', 429, headers: {'Retry-After': '42'}));
      await expectLater(
        api.get('/api/v1/queue/predict'),
        throwsA(isA<ApiException>().having((e) => e.retryAfterSeconds, 'retryAfterSeconds', 42).having((e) => e.detail, 'detail', 'rate_limited')),
      );
    });

    test('retryAfterSeconds is null when the header is absent or not a number', () async {
      final api = clientFor((r) => utf8Response('{"title":"x","status":429}', 429));
      await expectLater(api.get('/x'), throwsA(isA<ApiException>().having((e) => e.retryAfterSeconds, 'retryAfterSeconds', isNull)));
      // HTTP-дата вместо секунд — сервер так не отвечает; не угадываем, просто null
      final dated = clientFor((r) => utf8Response('{"title":"x","status":429}', 429, headers: {'Retry-After': 'Wed, 21 Oct 2026 07:28:00 GMT'}));
      await expectLater(dated.get('/x'), throwsA(isA<ApiException>().having((e) => e.retryAfterSeconds, 'retryAfterSeconds', isNull)));
    });

    test('isRateLimited is set for a real 429 problem', () async {
      final api = clientFor((r) => utf8Response('{"title":"Слишком много запросов","status":429,"detail":"rate_limited"}', 429, headers: {'Retry-After': '7'}));
      await expectLater(api.get('/x'), throwsA(isA<ApiException>().having((e) => e.isRateLimited, 'isRateLimited', isTrue)));
    });
  });

  group('tolerant detail (§4.10, §5.1: detail is a String or null)', () {
    // FastAPI шлёт detail списком технических сообщений на английском — §5.1: такой detail становится null,
    // а не TypeError и не текст для человека.
    test('a FastAPI detail list becomes null and the title falls back to HTTP n', () async {
      const body = '{"detail":[{"type":"string_too_short","loc":["body","text"],"msg":"String should have at least 1 character"}]}';
      final api = clientFor((r) => utf8Response(body, 422));
      await expectLater(
        api.post('/api/v1/scribe/sessions/x/transcript', const {'text': ''}),
        throwsA(isA<ApiException>()
            .having((e) => e.status, 'status', 422)
            .having((e) => e.isValidation, 'isValidation', isTrue)
            .having((e) => e.detail, 'detail', isNull)
            .having((e) => e.title, 'title', 'HTTP 422')),
      );
    });

    test('an empty FastAPI detail list is null as well', () async {
      final api = clientFor((r) => utf8Response('{"detail":[]}', 422));
      await expectLater(api.post('/x', const {}), throwsA(isA<ApiException>().having((e) => e.detail, 'detail', isNull)));
    });

    test('an empty or blank detail string is null, not an empty message', () async {
      final api = clientFor((r) => utf8Response('{"title":"x","status":409,"detail":"  "}', 409));
      await expectLater(api.get('/x'), throwsA(isA<ApiException>().having((e) => e.detail, 'detail', isNull)));
    });

    test('approve passthrough: a detail that is itself a scribe problem JSON is unwrapped to its inner detail (§4.2)', () async {
      // «Запись не утверждена»: API кладёт в detail сырое тело ответа сервиса скрайба — показывать его как есть нельзя
      final inner = jsonEncode({'title': 'Скрайб', 'detail': 'sections and patientLeaflet are required', 'status': 422});
      final body = jsonEncode({'title': 'Запись не утверждена', 'status': 422, 'detail': inner});
      final api = clientFor((r) => utf8Response(body, 422));
      await expectLater(
        api.post('/api/v1/scribe/sessions/s-1/approve', const {}),
        throwsA(isA<ApiException>()
            .having((e) => e.title, 'title', 'Запись не утверждена')
            .having((e) => e.detail, 'detail', 'sections and patientLeaflet are required')),
      );
    });

    test('approve passthrough of a FastAPI validation list gives a null detail, never the raw JSON', () async {
      final inner = jsonEncode({
        'detail': [
          {'msg': 'Field required'},
        ],
      });
      final api = clientFor((r) => utf8Response(jsonEncode({'title': 'Запись не утверждена', 'status': 422, 'detail': inner}), 422));
      await expectLater(
        api.post('/x', const {}),
        throwsA(isA<ApiException>().having((e) => e.title, 'title', 'Запись не утверждена').having((e) => e.detail, 'detail', isNull)),
      );
    });

    test('a detail that only looks like JSON but is not parseable is kept as-is', () async {
      final api = clientFor((r) => utf8Response(jsonEncode({'title': 'x', 'status': 409, 'detail': '{не json'}), 409));
      await expectLater(api.get('/x'), throwsA(isA<ApiException>().having((e) => e.detail, 'detail', '{не json')));
    });

    test('a plain string detail (the common case) is kept as-is', () async {
      final api = clientFor((r) => utf8Response('{"title":"Действие недоступно","status":409,"detail":"эта запись уже утверждена"}', 409));
      await expectLater(api.get('/x'), throwsA(isA<ApiException>().having((e) => e.detail, 'detail', 'эта запись уже утверждена')));
    });
  });

  group('tolerant errors (§4.10)', () {
    test('only Map values that are lists are kept; scalar items are stringified', () async {
      const body = '{"title":"Ошибка валидации","status":422,"errors":{"reason":["обязательное поле"],"weird":"not-a-list","count":[1,2]}}';
      final api = clientFor((r) => utf8Response(body, 422));
      await expectLater(
        api.post('/x', const {}),
        throwsA(isA<ApiException>()
            .having((e) => e.fieldError('reason'), 'fieldError(reason)', 'обязательное поле')
            .having((e) => e.errors?.containsKey('weird'), 'drops non-list weird', isFalse)
            .having((e) => e.errors?['count'], 'stringifies non-string list items', ['1', '2'])),
      );
    });
  });

  group('extension values of a wrong type are ignored, not crashed on', () {
    test('a numeric status extension, a non-string requestId and non-string permissions', () async {
      const body = '{"title":"x","status":409,"requestId":42,"permissions":["a",7,null]}';
      final api = clientFor((r) => utf8Response(body, 409));
      await expectLater(
        api.get('/x'),
        throwsA(isA<ApiException>()
            .having((e) => e.status, 'status', 409)
            .having((e) => e.stateCode, 'stateCode', isNull)
            .having((e) => e.requestId, 'requestId', isNull)
            .having((e) => e.permissions, 'permissions', ['a', '7'])),
      );
    });

    test('the HTTP status code wins even when the body claims another one', () async {
      final api = clientFor((r) => utf8Response('{"title":"x","status":400}', 409));
      await expectLater(api.get('/x'), throwsA(isA<ApiException>().having((e) => e.status, 'status', 409)));
    });

    test('errors that is not an object is dropped', () async {
      final api = clientFor((r) => utf8Response('{"title":"x","status":422,"errors":["a","b"]}', 422));
      await expectLater(api.get('/x'), throwsA(isA<ApiException>().having((e) => e.errors, 'errors', isNull)));
    });

    test('a JSON body that is not an object (array, string) still gives a plain ApiException', () async {
      final api = clientFor((r) => utf8Response('["oops"]', 500));
      await expectLater(api.get('/x'), throwsA(isA<ApiException>().having((e) => e.title, 'title', 'HTTP 500')));
    });

    test('an empty title falls back to HTTP n', () async {
      final api = clientFor((r) => utf8Response('{"title":"","status":409}', 409));
      await expectLater(api.get('/x'), throwsA(isA<ApiException>().having((e) => e.title, 'title', 'HTTP 409')));
    });
  });

  group('network failures are not wrapped (decision: callers see the transport exception)', () {
    test('a ClientException from the transport propagates as is', () async {
      final api = ApiClient(baseUrl: 'https://api.test', client: MockClient((r) async => throw http.ClientException('Connection refused', r.url)));
      await expectLater(api.get('/x'), throwsA(isA<http.ClientException>()));
    });

    test('a 2xx response with a non-JSON body (captive portal) is a FormatException, not an ApiException', () async {
      final api = clientFor((r) => utf8Response('<html>Wi-Fi login</html>', 200, headers: {'content-type': 'text/html'}));
      await expectLater(api.get('/x'), throwsA(isA<FormatException>()));
    });
  });

  group('non-JSON bodies (§4.10)', () {
    test('a non-JSON error body (e.g. an HTML page from a reverse proxy) becomes a plain ApiException', () async {
      final api = clientFor((r) => utf8Response('<html><body>502 Bad Gateway</body></html>', 502, headers: {'content-type': 'text/html'}));
      await expectLater(
        api.get('/x'),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 502).having((e) => e.title, 'title', 'HTTP 502').having((e) => e.detail, 'detail', isNull)),
      );
    });

    test('an empty error body also becomes a plain ApiException, not a crash', () async {
      final api = clientFor((r) => utf8Response('', 500));
      await expectLater(api.get('/x'), throwsA(isA<ApiException>().having((e) => e.status, 'status', 500).having((e) => e.title, 'title', 'HTTP 500')));
    });
  });

  group('real problem bodies of the running API (samples, 02.10.2026)', () {
    test('403 permission_required for a citizen on the worklist', () async {
      const body = '{"type":"https://tools.ietf.org/html/rfc9110#section-15.5.4","title":"Нет доступа к разделу","status":403,'
          '"detail":"permission_required","permissions":["worklist.view"],"traceId":"00-307f52aaf031c83f8efbf99748fec112-9816f9d82dcb275c-00"}';
      final api = clientFor((r) => utf8Response(body, 403, headers: {'content-type': 'application/problem+json'}));
      await expectLater(
        api.get('/api/v1/journal/worklist'),
        throwsA(isA<ApiException>()
            .having((e) => e.isForbidden, 'isForbidden', isTrue)
            .having((e) => e.title, 'title', 'Нет доступа к разделу')
            .having((e) => e.detail, 'detail', 'permission_required')
            .having((e) => e.permissions, 'permissions', ['worklist.view'])
            .having((e) => e.stateCode, 'stateCode', isNull)),
      );
    });

    test('422 «Нужна организация» from the incoming list has no errors map (fixture incoming.json)', () async {
      final body = File('test/fixtures/api/incoming.json').readAsStringSync();
      final api = clientFor((r) => utf8Response(body, 422, headers: {'content-type': 'application/problem+json'}));
      await expectLater(
        api.get('/api/v1/journal/referrals/incoming'),
        throwsA(isA<ApiException>()
            .having((e) => e.isValidation, 'isValidation', isTrue)
            .having((e) => e.title, 'title', 'Нужна организация')
            .having((e) => e.detail, 'detail', startsWith('укажите moCode'))
            .having((e) => e.errors, 'errors', isNull)
            .having((e) => e.fieldError('moCode'), 'fieldError(moCode)', isNull)),
      );
    });

    test('404 from the scribe proxy keeps its own title and detail', () async {
      final api = clientFor((r) => utf8Response('{"title":"Скрайб","detail":"leaflet not found","status":404}', 404));
      await expectLater(
        api.get('/api/v1/scribe/leaflets/nope'),
        throwsA(isA<ApiException>().having((e) => e.isNotFound, 'isNotFound', isTrue).having((e) => e.title, 'title', 'Скрайб')),
      );
    });
  });

  group('parsed values are immutable', () {
    test('errors, their message lists and permissions cannot be modified by a caller', () async {
      const body = '{"title":"x","status":422,"errors":{"reason":["обязательное поле"]},"permissions":["a"]}';
      final api = clientFor((r) => utf8Response(body, 422));
      final error = await api.get('/x').then<ApiException?>((_) => null, onError: (Object e) => e as ApiException);
      expect(() => error!.errors!['reason'] = const ['x'], throwsUnsupportedError);
      expect(() => error!.errors!['reason']!.add('x'), throwsUnsupportedError);
      expect(() => error!.permissions!.add('b'), throwsUnsupportedError);
    });
  });

  group('transport details', () {
    test('the Retry-After header is read case-insensitively (IOClient lowercases header names)', () async {
      final api = clientFor((r) => utf8Response('{"title":"x","status":429}', 429, headers: {'retry-after': ' 15 '}));
      await expectLater(api.get('/x'), throwsA(isA<ApiException>().having((e) => e.retryAfterSeconds, 'retryAfterSeconds', 15)));
    });

    test('a negative Retry-After is ignored', () async {
      final api = clientFor((r) => utf8Response('{"title":"x","status":429}', 429, headers: {'Retry-After': '-3'}));
      await expectLater(api.get('/x'), throwsA(isA<ApiException>().having((e) => e.retryAfterSeconds, 'retryAfterSeconds', isNull)));
    });

    test('an error body that is not valid UTF-8 still becomes an ApiException', () async {
      final api = clientFor((r) => http.Response.bytes([0xff, 0xfe, 0x7b], 502));
      await expectLater(api.get('/x'), throwsA(isA<ApiException>().having((e) => e.status, 'status', 502).having((e) => e.title, 'title', 'HTTP 502')));
    });

    test('a 401 without a body (expired session) is a plain ApiException with no helper flags set', () async {
      final api = clientFor((r) => utf8Response('', 401));
      await expectLater(
        api.get('/x'),
        throwsA(isA<ApiException>()
            .having((e) => e.status, 'status', 401)
            .having((e) => [e.isConflict, e.isValidation, e.isForbidden, e.isNotFound, e.isRateLimited, e.isServerError], 'flags', everyElement(isFalse))),
      );
    });
  });

  group('success bodies', () {
    test('204 / empty body decodes to null instead of throwing', () async {
      final api = clientFor((r) => utf8Response('', 204));
      expect(await api.post('/x', const {}), isNull);
      expect(await api.get('/y'), isNull);
    });

    test('a normal JSON success body still decodes as before', () async {
      final api = clientFor((r) => utf8Response('{"decisionId":"abc"}', 201));
      expect(await api.post('/x', const {}), {'decisionId': 'abc'});
    });

    test('a bare JSON array success body decodes as a List, not a Map', () async {
      final api = clientFor((r) => utf8Response('[]', 200));
      expect(await api.get('/x'), isA<List<dynamic>>());
    });
  });
}
