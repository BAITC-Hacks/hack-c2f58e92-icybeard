import 'dart:async';

import 'package:darumen/screens/security_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/harness.dart';

/// «Безопасность» (§8): то, что добавлено к прежнему экрану по API — последние входы (дата, способ входа словами,
/// IP, чип «успешно» / «не удалось»), строка «Резервные коды», «Перенастроить» для настроенного аутентификатора;
/// ошибки действий — общим рецептом.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, Object?> security({bool otp = true, List<String>? codes, List<Map<String, Object?>>? logins, bool others = true}) => {
        'passwordChangedAt': null,
        'otpConfigured': otp,
        'smsAvailable': false,
        'recoveryCodes': codes,
        'recentLogins': logins ??
            [
              {'at': '2026-10-01T08:00:00+00:00', 'method': 'password', 'success': true, 'ip': '10.0.2.2'},
              {'at': '2026-09-30T21:15:00+00:00', 'method': 'otp', 'success': false, 'ip': '10.0.0.5'},
              {'at': '2026-09-29T07:00:00+00:00', 'method': 'saml-kz', 'success': true, 'ip': null},
            ],
        'sessions': [
          {'id': 's1', 'device': 'Android', 'browser': 'Darumen', 'ip': '10.0.2.2', 'lastAccess': '2026-10-01T08:00:00Z', 'current': true},
          if (others) {'id': 's2', 'device': 'Рабочий ПК', 'browser': 'Chrome', 'ip': '10.0.0.5', 'lastAccess': '2026-09-30T18:40:00Z', 'current': false},
        ],
      };

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).first);
    await tester.pump();
  }

  testWidgets('recent sign-ins: method in words (unknown as sent), IP and the result chip', (tester) async {
    final (session, _) = await demoSession(DemoUser.citizen1, api: {'GET /me/security': security()});
    await pumpScreen(tester, session, const SecurityScreen(), size: phoneTall);
    await scrollTo(tester, find.text('ПОСЛЕДНИЕ ВХОДЫ'));
    expect(find.text('по паролю · 10.0.2.2'), findsOneWidget);
    expect(find.text('пароль и код · 10.0.0.5'), findsOneWidget);
    expect(find.text('saml-kz'), findsOneWidget);
    expect(find.text('Успешно'), findsNWidgets(2));
    expect(find.text('Не удалось'), findsOneWidget);
  });

  testWidgets('no sign-ins yet; recovery codes absent in the sign-in system', (tester) async {
    final (session, _) = await demoSession(DemoUser.citizen1, api: {'GET /me/security': security(logins: const [])});
    await pumpScreen(tester, session, const SecurityScreen(), size: phoneTall);
    expect(find.text('Резервные коды'), findsOneWidget);
    expect(find.text('нет в системе входа'), findsOneWidget);
    await scrollTo(tester, find.text('Входов пока нет'));
    expect(find.text('Входов пока нет'), findsOneWidget);
  });

  testWidgets('recovery codes are counted when the server has them', (tester) async {
    final (session, _) = await demoSession(DemoUser.citizen1, api: {'GET /me/security': security(codes: ['a', 'b', 'c', 'd'])});
    await pumpScreen(tester, session, const SecurityScreen(), size: phoneTall);
    expect(find.text('кодов: 4'), findsOneWidget);
  });

  testWidgets('a configured authenticator offers «Перенастроить» and opens the Keycloak action', (tester) async {
    final opened = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/url_launcher'), (call) async {
      opened.add((call.arguments as Map<Object?, Object?>)['url']! as String);
      return true;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/url_launcher'), null));
    final (session, _) = await demoSession(DemoUser.citizen1, api: {'GET /me/security': security()});
    await pumpScreen(tester, session, const SecurityScreen(), size: phoneTall);
    expect(find.text('Настроено'), findsOneWidget);
    expect(find.text('Перенастроить'), findsOneWidget);
    await tester.tap(find.text('Приложение-аутентификатор'));
    await pumpFrames(tester);
    expect(opened.single, contains('kc_action=CONFIGURE_TOTP'));
  });

  testWidgets('ending a session that is already gone shows the server text and reloads the list', (tester) async {
    final (session, backend) = await demoSession(DemoUser.citizen1, api: {
      'GET /me/security': security(),
      'DELETE /me/sessions/s2': problem(404, 'Сессия не найдена', detail: 'у вас нет такой активной сессии'),
    });
    await pumpScreen(tester, session, const SecurityScreen(), size: phoneTall);
    await tester.tap(find.text('Завершить'));
    await pumpFrames(tester);
    expect(find.text('Сессия не найдена — у вас нет такой активной сессии'), findsOneWidget);
    expect(find.text('Сеанс завершён'), findsNothing);
    expect(backend.calls('GET', '/me/security'), hasLength(2), reason: 'список перечитан');
  });

  testWidgets('while a session is being ended every end button is disabled', (tester) async {
    final gate = Completer<http.Response>();
    final (session, backend) = await demoSession(DemoUser.citizen1, api: {
      'GET /me/security': security(),
      'DELETE /me/sessions/s2': (http.Request _) => gate.future,
    });
    await pumpScreen(tester, session, const SecurityScreen(), size: phoneTall);
    await tester.tap(find.text('Завершить'));
    await tester.pump();
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Завершить')).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Завершить все, кроме этого')).onPressed, isNull);
    gate.complete(noContent());
    await pumpFrames(tester);
    expect(backend.calls('DELETE', '/me/sessions/s2'), hasLength(1));
    expect(find.text('Сеанс завершён'), findsOneWidget);
  });

  testWidgets('a network failure while ending others says the server is unavailable', (tester) async {
    final (session, _) = await demoSession(DemoUser.citizen1, api: {
      'GET /me/security': security(),
      'DELETE /me/sessions': (http.Request _) => throw http.ClientException('reset by peer'),
    });
    await pumpScreen(tester, session, const SecurityScreen(), size: phoneTall);
    await tester.tap(find.text('Завершить все, кроме этого'));
    await pumpFrames(tester);
    expect(find.text('Сервер недоступен. Повторите попытку позже.'), findsOneWidget);
    expect(find.textContaining('reset by peer'), findsNothing);
  });

  testWidgets('kazakh at text scale 1.3 on a 360 dp phone without overflow', (tester) async {
    final (session, _) = await demoSession(DemoUser.citizen1, locale: 'kk', api: {'GET /me/security': security()});
    await pumpScreen(tester, session, const SecurityScreen(), locale: 'kk', textScale: 1.3, size: phoneNarrow);
    expect(find.text('Қауіпсіздік'), findsOneWidget);
    expect(find.text('Қайта баптау'), findsOneWidget);
    expect(find.text('Резервтік кодтар'), findsOneWidget);
    await scrollTo(tester, find.text('СОҢҒЫ КІРУЛЕР'));
    expect(find.text('құпиясөзбен · 10.0.2.2'), findsOneWidget);
    expect(find.text('Сәтсіз'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
