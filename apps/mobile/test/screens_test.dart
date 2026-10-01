import 'dart:convert';

import 'package:darumen/state/session.dart';
import 'package:darumen/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'session_test.dart' show fakeJwt;

/// Сессия с мок-Keycloak и мок-API в одном клиенте: токен с ролями, остальное — обработчик `api` по пути.
Future<Session> apiSession({required List<String> roles, required Map<String, Object> api, String? region, Map<String, Object?> claims = const {}}) async {
  FlutterSecureStorage.setMockInitialValues({});
  SharedPreferences.setMockInitialValues({});
  final client = MockClient((request) async {
    if (request.url.path.endsWith('/protocol/openid-connect/token')) {
      final token = fakeJwt({'preferred_username': 'doctor1', 'realm_access': {'roles': roles}, 'region_kato': ?region, ...claims});
      return http.Response(jsonEncode({'access_token': token, 'refresh_token': 'r', 'expires_in': 300}), 200);
    }
    for (final entry in api.entries) {
      if (request.url.path.endsWith(entry.key)) {
        return http.Response(jsonEncode(entry.value), 200, headers: {'content-type': 'application/json'});
      }
    }
    return http.Response(jsonEncode({'title': 'Not found'}), 404, headers: {'content-type': 'application/problem+json'});
  });
  final session = Session(httpClient: client);
  await session.load();
  if (roles.isNotEmpty) {
    await session.login('doctor1', 'darumen');
  }
  return session;
}

Widget app(Session session, Widget screen) => MaterialApp(
      theme: AppTheme.light(),
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru'), Locale('kk')],
      localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      home: ChangeNotifierProvider<Session>.value(value: session, child: screen),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
}
