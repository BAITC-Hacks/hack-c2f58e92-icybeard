import 'dart:convert';

import 'package:darumen/state/session.dart';
import 'package:darumen/state/token_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'session_test.dart' show fakeJwt;

/// Keycloak + API в одном мок-клиенте: запоминает запросы, `/me` отвечает [me] (null — 404, как сейчас на стенде).
class FakeBackend {
  FakeBackend({required this.roles, this.me, this.claims = const {}, this.otpSecret});

  final List<String> roles;
  final Map<String, Object?>? me;
  final Map<String, Object?> claims;

  /// Если задан — Keycloak требует `totp` с этим значением (как direct grant при настроенном OTP).
  final String? otpSecret;
  final requests = <http.Request>[];

  MockClient get client => MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        if (path.endsWith('/token')) {
          final body = request.bodyFields;
          final otpOk = otpSecret == null || body['totp'] == otpSecret || body['grant_type'] == 'refresh_token';
          if (body['grant_type'] == 'password' && (body['password'] != 'darumen' || !otpOk)) {
            return http.Response(jsonEncode({'error': 'invalid_grant', 'error_description': 'Invalid user credentials'}), 401);
          }
          final token = fakeJwt({'preferred_username': body['username'] ?? 'u', 'realm_access': {'roles': roles}, ...claims});
          return http.Response(jsonEncode({'access_token': token, 'refresh_token': 'refresh-1', 'expires_in': 300}), 200);
        }
        if (path.endsWith('/logout')) {
          return http.Response('', 204);
        }
        if (path.endsWith('/api/v1/me') && me != null) {
          return http.Response(jsonEncode(me), 200, headers: {'content-type': 'application/json'});
        }
        return http.Response(jsonEncode({'title': 'Not found'}), 404);
      });
}

Future<Session> signedIn(FakeBackend backend, {String username = 'user1', String? otp, bool remember = true}) async {
  FlutterSecureStorage.setMockInitialValues({});
  SharedPreferences.setMockInitialValues({});
  final s = Session(httpClient: backend.client);
  await s.load();
  await s.login(username, 'darumen', otp: otp, remember: remember);
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('without /me (404) permissions come from token roles by the rbac.md matrix', () async {
    final doctor = await signedIn(FakeBackend(roles: ['doctor'], claims: {'region_kato': '75'}));
    expect(doctor.grantsFromApi, isFalse);
    expect(doctor.shell, ShellKind.doctor);
    for (final code in ['worklist.view', 'referral.assist', 'referral.confirm', 'scribe.use', 'decisions.own']) {
      expect(doctor.can(code), isTrue, reason: code);
    }
    expect(doctor.can('decisions.all'), isFalse);
    expect(doctor.can('gov.map'), isFalse);
  });

  test('legacy chief is org_admin: doctor shell with confirm and journal, no assistant or scribe; without mo_code — web', () async {
    final chief = await signedIn(FakeBackend(roles: ['chief'], claims: {'mo_code': '028B'}));
    expect(chief.primaryRoleKey, 'org_admin');
    expect(chief.shell, ShellKind.doctor);
    expect(chief.can('referral.confirm'), isTrue);
    expect(chief.can('decisions.all'), isTrue);
    expect(chief.can('referral.assist'), isFalse);
    expect(chief.can('scribe.use'), isFalse);

    final orphan = await signedIn(FakeBackend(roles: ['org_admin']));
    expect(orphan.shell, ShellKind.web, reason: 'own-разрешения без mo_code пустые');
  });

  test('/me permissions replace the token fallback and fill the display name', () async {
    final s = await signedIn(FakeBackend(roles: ['doctor'], me: {
      'userId': 'u-1',
      'displayName': 'Сейткали А.',
      'email': 'a@clinic.kz',
      'roles': ['doctor'],
      'permissions': [
        {'code': 'route.own', 'scope': 'all'},
        {'code': 'wait.public', 'scope': 'all'},
      ],
      'moName': 'Алматинский онкологический центр',
      'onboarding': {'otpConfigured': true},
    }));
    expect(s.grantsFromApi, isTrue);
    expect(s.shell, ShellKind.citizen, reason: 'API — источник истины: без worklist.view врачебного кабинета нет');
    expect(s.can('worklist.view'), isFalse);
    expect(s.displayName, 'Сейткали А.');
    expect(s.organizationName, 'Алматинский онкологический центр');
    expect(s.needsOtp('user1'), isTrue, reason: 'onboarding.otpConfigured запоминается для следующего входа');
  });

  test('a /me response without permissions keeps the fallback instead of locking the user out', () async {
    final s = await signedIn(FakeBackend(roles: ['doctor'], me: {'userId': 'u', 'displayName': 'D', 'roles': ['doctor']}));
    expect(s.grantsFromApi, isFalse);
    expect(s.shell, ShellKind.doctor);
  });

  test('regulator, steward and auditor get the web-only screen, admin gets everything', () async {
    for (final role in ['regulator', 'steward', 'auditor']) {
      final s = await signedIn(FakeBackend(roles: [role]));
      expect(s.shell, ShellKind.web, reason: role);
      expect(s.home, '/web', reason: role);
    }
    final admin = await signedIn(FakeBackend(roles: ['admin']));
    expect(admin.shell, ShellKind.doctor);
    expect(admin.can('admin.roles'), isTrue);
  });

  test('TOTP: the code goes as the totp parameter and the login is remembered as needing a code', () async {
    final backend = FakeBackend(roles: ['doctor'], otpSecret: '123456');
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    final s = Session(httpClient: backend.client);
    await s.load();
    await expectLater(s.login('doc', 'darumen'), throwsA(anything), reason: 'без кода Keycloak отвечает invalid_grant');
    expect(s.isAuthenticated, isFalse);
    await s.login('Doc', 'darumen', otp: '123456');
    expect(s.isAuthenticated, isTrue);
    final token = backend.requests.where((r) => r.url.path.endsWith('/token')).last;
    expect(token.bodyFields['totp'], '123456');
    expect(s.needsOtp('doc'), isTrue);
    expect(s.needsOtp('other'), isFalse);
  });

  test('«remember for 30 days» off keeps tokens in memory only; on — in secure storage', () async {
    final forget = await signedIn(FakeBackend(roles: ['citizen']), remember: false);
    expect(forget.isAuthenticated, isTrue);
    expect(await TokenStore().read(), isNull);

    final remember = await signedIn(FakeBackend(roles: ['citizen']));
    expect((await TokenStore().read())?.refresh, 'refresh-1');
    expect(remember.rememberMe, isTrue);
  });

  test('logout ends the Keycloak session with the refresh token', () async {
    final backend = FakeBackend(roles: ['citizen']);
    final s = await signedIn(backend);
    await s.logout();
    await Future<void>.delayed(Duration.zero);
    final logout = backend.requests.where((r) => r.url.path.endsWith('/logout')).single;
    expect(logout.bodyFields['refresh_token'], 'refresh-1');
    expect(s.isAuthenticated, isFalse);
  });
}
