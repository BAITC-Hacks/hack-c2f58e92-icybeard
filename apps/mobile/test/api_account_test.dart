import 'package:darumen/api/client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

/// Аккаунт в `ApiClient` (`/me/consents`, `/me/access-log`, `/me/deletion-request`, `/me/profile`, `/me/security`
/// с последними входами и резервными кодами) — над мок-бэкендом обвязки, с настоящими формами ответов API.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const consents = {
    'items': [
      {
        'code': 'forecasts',
        'titleRu': 'Использование моих данных для прогноза сроков ожидания (обязательное)',
        'titleKk': 'Күту мерзімдерін болжау үшін деректерімді пайдалану (міндетті)',
        'required': true,
        'granted': true,
        'updatedAt': null,
      },
      {
        'code': 'anonymized_stats',
        'titleRu': 'Обезличенная статистика для улучшения сервиса',
        'titleKk': '',
        'required': false,
        'granted': false,
        'updatedAt': '2026-09-30T10:15:00+00:00',
      },
    ],
  };

  group('consents', () {
    test('GET /me/consents parses rows; the Kazakh title falls back to Russian when empty', () async {
      final (session, _) = await demoSession(DemoUser.citizen1, api: {'GET /me/consents': consents});
      final items = await session.api.myConsents();
      expect(items, hasLength(2));
      expect(items.first.code, 'forecasts');
      expect(items.first.required, isTrue);
      expect(items.first.granted, isTrue);
      expect(items.first.updatedAt, isNull);
      expect(items.first.title('kk'), 'Күту мерзімдерін болжау үшін деректерімді пайдалану (міндетті)');
      expect(items.last.title('kk'), 'Обезличенная статистика для улучшения сервиса');
      expect(items.last.title('ru'), 'Обезличенная статистика для улучшения сервиса');
      expect(items.last.updatedAt, '2026-09-30T10:15:00+00:00');
      expect(() => items.add(items.first), throwsUnsupportedError, reason: 'список неизменяемый');
    });

    test('a row without titles shows its code; a missing list is empty', () async {
      final (session, _) = await demoSession(DemoUser.citizen1, api: {
        'GET /me/consents': {
          'items': [
            {'code': 'research_exports', 'granted': true},
          ],
        },
      });
      final items = await session.api.myConsents();
      expect(items.single.title('ru'), 'research_exports');
      expect(items.single.required, isFalse);

      final (empty, _) = await demoSession(DemoUser.citizen1, api: {'GET /me/consents': <String, Object?>{}});
      expect(await empty.api.myConsents(), isEmpty);
    });

    test('PUT /me/consents/{code} sends {granted} and returns the list the server stored', () async {
      final (session, backend) = await demoSession(DemoUser.citizen1, api: {'PUT /me/consents/anonymized_stats': consents});
      final items = await session.api.setConsent('anonymized_stats', granted: true);
      expect(backend.calls('PUT', '/api/v1/me/consents/anonymized_stats'), hasLength(1));
      expect(backend.lastBody('PUT', '/me/consents/anonymized_stats'), {'granted': true});
      expect(items, hasLength(2));
    });

    test('the code is escaped in the path', () async {
      final (session, backend) = await demoSession(DemoUser.citizen1, api: {'PUT /me/consents/a%2Fb': consents});
      await session.api.setConsent('a/b', granted: false);
      expect(backend.requests.last.url.path, '/api/v1/me/consents/a%2Fb');
    });

    test('422 «обязательное согласие нельзя отозвать» comes back as ApiException with the field', () async {
      final (session, _) = await demoSession(DemoUser.citizen1, api: {
        'PUT /me/consents/forecasts': problem(422, 'Проверьте поля', errors: {
          'granted': ['обязательное согласие нельзя отозвать'],
        }),
      });
      await expectLater(
        session.api.setConsent('forecasts', granted: false),
        throwsA(isA<ApiException>().having((e) => e.fieldError('granted'), 'granted', 'обязательное согласие нельзя отозвать')),
      );
    });
  });

  group('access log', () {
    test('GET /me/access-log parses rows and shortens the path', () async {
      final (session, _) = await demoSession(DemoUser.citizen1, api: {
        'GET /me/access-log': {
          'items': [
            {'at': '2026-10-01T08:00:00+00:00', 'actor': 'doctor1', 'role': 'doctor', 'method': 'GET', 'path': '/api/v1/route/SYN-75-028B-1-01', 'status': 200},
            {'at': '2026-09-30T08:00:00+00:00', 'actor': 'doctor2', 'role': 'doctor', 'method': 'POST', 'path': '/journal/x', 'status': 409},
          ],
        },
      });
      final rows = await session.api.myAccessLog();
      expect(rows, hasLength(2));
      expect(rows.first.actor, 'doctor1');
      expect(rows.first.what, 'GET /route/SYN-75-028B-1-01');
      expect(rows.last.what, 'POST /journal/x');
      expect(rows.last.status, 409);
    });
  });

  group('deletion request', () {
    test('POST /me/deletion-request sends an empty object and the idempotency key', () async {
      final (session, backend) = await demoSession(DemoUser.citizen1, api: {'POST /me/deletion-request': json({'accepted': true}, 202)});
      await session.api.requestDeletion(idempotencyKey: 'key-1');
      final call = backend.calls('POST', '/api/v1/me/deletion-request').single;
      expect(call.body, '{}');
      expect(call.headers['Idempotency-Key'], 'key-1');
    });
  });

  group('profile', () {
    const stored = {
      'displayName': 'Ерлан Жумабеков',
      'position': null,
      'specialty': null,
      'email': 'citizen1@darumen.local',
      'phone': '+77010000000',
      'language': 'kk',
      'timeZone': 'Asia/Qostanay',
      'moCode': null,
      'moName': null,
      'regionKato': '75',
      'iinMasked': '00••••••••01',
      'readOnlyFields': ['displayName', 'position', 'specialty', 'moCode'],
    };

    test('GET /me/profile parses the fields; missing language and time zone get the server defaults', () async {
      final (session, _) = await demoSession(DemoUser.citizen1, api: {'GET /me/profile': stored});
      final profile = await session.api.myProfile();
      expect(profile.displayName, 'Ерлан Жумабеков');
      expect(profile.phone, '+77010000000');
      expect(profile.language, 'kk');
      expect(profile.timeZone, 'Asia/Qostanay');
      expect(profile.hasJob, isFalse);

      final (bare, _) = await demoSession(DemoUser.doctor1, api: {
        'GET /me/profile': {'displayName': 'Айгерим', 'position': 'Офтальмолог', 'moCode': '028B'},
      });
      final doctor = await bare.api.myProfile();
      expect(doctor.language, 'ru');
      expect(doctor.timeZone, 'Asia/Almaty');
      expect(doctor.hasJob, isTrue);
    });

    test('PUT /me/profile sends phone, language and time zone; an empty phone is sent as null', () async {
      final (session, backend) = await demoSession(DemoUser.citizen1, api: {'PUT /me/profile': stored});
      await session.api.saveProfile(phone: '+77010000000', language: 'kk', timeZone: 'Asia/Almaty');
      expect(backend.lastBody('PUT', '/me/profile'), {'phone': '+77010000000', 'language': 'kk', 'timeZone': 'Asia/Almaty'});
      await session.api.saveProfile(phone: null, language: 'ru', timeZone: 'Asia/Almaty');
      expect(backend.lastBody('PUT', '/me/profile'), {'phone': null, 'language': 'ru', 'timeZone': 'Asia/Almaty'});
    });
  });

  group('security', () {
    test('GET /me/security gives the sessions and the recent sign-ins with recovery codes', () async {
      final (session, _) = await demoSession(DemoUser.citizen1, api: {
        'GET /me/security': {
          'passwordChangedAt': '2026-09-20T08:00:00+00:00',
          'otpConfigured': true,
          'smsAvailable': false,
          'recoveryCodes': null,
          'recentLogins': [
            {'at': '2026-10-01T08:00:00+00:00', 'method': 'password', 'success': true, 'ip': '10.0.2.2'},
            {'at': '2026-09-30T08:00:00+00:00', 'method': 'keycloak-oidc', 'success': false, 'ip': null},
          ],
          'sessions': [
            {'id': 's1', 'device': 'Android', 'browser': 'Darumen', 'ip': '10.0.2.2', 'lastAccess': '2026-10-01T08:00:00Z', 'current': true},
          ],
        },
      });
      final details = await session.api.mySecurity();
      expect(details.otpConfigured, isTrue);
      expect(details.sessions.single.current, isTrue);
      expect(details.recoveryCodes, isNull);
      expect(details.recentLogins, hasLength(2));
      expect(details.recentLogins.first.method, 'password');
      expect(details.recentLogins.first.success, isTrue);
      expect(details.recentLogins.last.ip, isNull);
    });

    test('recovery codes, when the server has them, are counted', () async {
      final (session, _) = await demoSession(DemoUser.citizen1, api: {
        'GET /me/security': {'otpConfigured': false, 'recoveryCodes': ['a', 'b', 'c'], 'sessions': <Object?>[]},
      });
      final details = await session.api.mySecurity();
      expect(details.recoveryCodes, hasLength(3));
      expect(details.recentLogins, isEmpty);
    });
  });
}
