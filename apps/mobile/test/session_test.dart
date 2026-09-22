import 'dart:convert';

import 'package:darumen/api/client.dart';
import 'package:darumen/state/session.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Токен с нужными клеймами без подписи — Session подпись не проверяет, это делает API.
String fakeJwt(Map<String, dynamic> claims) =>
    'header.${base64Url.encode(utf8.encode(jsonEncode(claims))).replaceAll('=', '')}.signature';

/// Keycloak-заглушка: password grant отдаёт токен с ролями, refresh — по флагу, остальное — 400 invalid_grant.
MockClient keycloak({required List<String> roles, String? region, String? iin, int expiresIn = 300, bool refreshOk = true}) =>
    MockClient((request) async {
      final body = request.bodyFields;
      final grant = body['grant_type'];
      if (grant == 'refresh_token' && !refreshOk) {
        return http.Response(jsonEncode({'error': 'invalid_grant', 'error_description': 'Token is not active'}), 400);
      }
      if (grant == 'password' && body['password'] != 'darumen') {
        return http.Response(jsonEncode({'error': 'invalid_grant', 'error_description': 'Invalid user credentials'}), 401);
      }
      final token = fakeJwt({
        'preferred_username': body['username'] ?? 'refreshed',
        'realm_access': {'roles': roles},
        'region_kato': ?region,
        'iin': ?iin,
      });
      return http.Response(jsonEncode({'access_token': token, 'refresh_token': 'refresh-1', 'expires_in': expiresIn}), 200);
    });

Future<Session> session({required List<String> roles, String? region, String? iin, int expiresIn = 300, bool refreshOk = true}) async {
  FlutterSecureStorage.setMockInitialValues({});
  SharedPreferences.setMockInitialValues({});
  final s = Session(httpClient: keycloak(roles: roles, region: region, iin: iin, expiresIn: expiresIn, refreshOk: refreshOk));
  await s.load();
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('jwt claims are decoded without verifying the signature', () {
    final claims = Session.jwtClaims(fakeJwt({'preferred_username': 'citizen1', 'iin': '000000000001'}));
    expect(claims['preferred_username'], 'citizen1');
    expect(claims['iin'], '000000000001');
    expect(Session.jwtClaims('garbage'), isEmpty);
  });

  test('fresh session is a guest with the default region and home', () async {
    final s = await session(roles: []);
    expect(s.isAuthenticated, isFalse);
    expect(s.role, AuthRole.guest);
    expect(s.region, '75');
    expect(s.home, '/home');
    expect(await s.freshToken(), isNull);
  });

  test('doctor login derives role and region from claims', () async {
    final s = await session(roles: ['doctor'], region: '75');
    await s.login('doctor1', 'darumen');
    expect(s.isDoctor, isTrue);
    expect(s.username, 'doctor1');
    expect(s.region, '75');
    expect(s.regionFromAccount, isTrue);
    expect(s.home, '/doctor/patients');
    expect(await s.freshToken(), isNotNull);
  });

  test('citizen login exposes the iin claim and admin counts as doctor', () async {
    final citizen = await session(roles: ['citizen'], iin: '000000000001');
    await citizen.login('citizen1', 'darumen');
    expect(citizen.isCitizen, isTrue);
    expect(citizen.iin, '000000000001');
    expect(citizen.regionFromAccount, isFalse);
    expect(citizen.home, '/home');

    final admin = await session(roles: ['admin']);
    await admin.login('admin1', 'darumen');
    expect(admin.isDoctor, isTrue);
  });

  test('wrong password surfaces invalid_grant and leaves the session a guest', () async {
    final s = await session(roles: ['citizen']);
    await expectLater(s.login('citizen1', 'wrong'), throwsA(isA<ApiException>().having((e) => e.title, 'title', 'invalid_grant')));
    expect(s.isAuthenticated, isFalse);
  });

  test('logout clears identity', () async {
    final s = await session(roles: ['doctor'], region: '75');
    await s.login('doctor1', 'darumen');
    await s.logout();
    expect(s.isAuthenticated, isFalse);
    expect(s.username, isNull);
    expect(s.regionFromAccount, isFalse);
  });

  test('an expired token is refreshed silently, a failed refresh drops to guest', () async {
    final refreshed = await session(roles: ['doctor'], expiresIn: 0);
    await refreshed.login('doctor1', 'darumen');
    expect(await refreshed.freshToken(), isNotNull);
    expect(refreshed.isDoctor, isTrue);

    final dropped = await session(roles: ['doctor'], expiresIn: 0, refreshOk: false);
    await dropped.login('doctor1', 'darumen');
    expect(await dropped.freshToken(), isNull);
    expect(dropped.isAuthenticated, isFalse);
  });

  test('locale and remembered choices persist through preferences', () async {
    final s = await session(roles: []);
    await s.setLocale('kk');
    await s.rememberProfile('381');
    await s.rememberNosology('110');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('locale'), 'kk');
    expect(prefs.getString('lastProfile'), '381');
    expect(prefs.getString('lastNosology'), '110');
    expect(s.api.locale, 'kk');
  });
}
