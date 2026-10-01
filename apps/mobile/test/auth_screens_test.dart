import 'dart:convert';

import 'package:darumen/api/client.dart';
import 'package:darumen/router/app_router.dart';
import 'package:darumen/screens/forgot_password_screen.dart';
import 'package:darumen/screens/login_screen.dart';
import 'package:darumen/screens/otp_screen.dart';
import 'package:darumen/screens/web_only_screen.dart';
import 'package:darumen/screens/security_screen.dart';
import 'package:darumen/state/session.dart';
import 'package:darumen/theme/app_theme.dart';
import 'package:darumen/widgets/otp_field.dart';
import 'package:darumen/widgets/state_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens_test.dart' show app;
import 'session_test.dart' show fakeJwt;
import 'shell_test.dart' show settle;

typedef Handler = http.Response? Function(http.Request request);

/// Keycloak (TOTP «123456» при [otp]) и API из [handler]; все запросы пишутся в [requests].
Future<Session> backendSession({List<String> roles = const [], bool otp = false, Handler? handler, List<http.Request>? requests, bool signIn = false}) async {
  FlutterSecureStorage.setMockInitialValues({});
  SharedPreferences.setMockInitialValues({});
  final client = MockClient((request) async {
    requests?.add(request);
    final path = request.url.path;
    if (path.endsWith('/token')) {
      final body = request.bodyFields;
      final ok = body['password'] == 'darumen' && (!otp || body['totp'] == '123456');
      if (!ok) {
        return http.Response(jsonEncode({'error': 'invalid_grant', 'error_description': 'Invalid user credentials'}), 401);
      }
      final token = fakeJwt({'preferred_username': body['username'], 'realm_access': {'roles': roles}, 'region_kato': '75', 'mo_code': '028B', 'email': 'a@clinic.kz'});
      return http.Response(jsonEncode({'access_token': token, 'refresh_token': 'r', 'expires_in': 300}), 200);
    }
    return handler?.call(request) ?? http.Response(jsonEncode({'title': 'Not Found'}), 404, headers: {'content-type': 'application/problem+json'});
  });
  final session = Session(httpClient: client);
  await session.load();
  if (signIn) {
    await session.login('doctor1', 'darumen');
  }
  return session;
}

Future<GoRouter> pumpRouter(WidgetTester tester, Session session) async {
  final router = buildRouter(session);
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: session,
    child: MaterialApp.router(
      theme: AppTheme.light(),
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru'), Locale('kk')],
      localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      routerConfig: router,
    ),
  ));
  await settle(tester);
  return router;
}

http.Response json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

/// Экран телефона 390×1200: формы входа целиком помещаются, тапы не уходят за край.
Future<void> tallPhone(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('login follows M-Auth-Login: language, heading, eGov, «или по логину», fields, remember, forgot, signup; no carousel or guest', (tester) async {
    await tallPhone(tester);
    final session = await backendSession();
    await tester.pumpWidget(app(session, const LoginScreen()));
    await tester.pump();
    for (final text in ['ҚАЗ', 'darumen', 'Вход', 'Кабинет', 'Войти через eGov mobile', 'или по логину', 'РАБОЧАЯ ПОЧТА ИЛИ ЛОГИН', 'ПАРОЛЬ', 'Показать',
      'Запомнить на 30 дней', 'Забыли пароль?', 'Войти', 'Нет аккаунта?', 'Зарегистрировать организацию']) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    expect(find.byType(PageView), findsNothing, reason: 'карусель снята — приоритет у доски M-Auth-Login');
    expect(find.text('Продолжить как гость'), findsNothing);
    expect(find.byType(TextField), findsNWidgets(2));

    await tester.tap(find.text('Войти'));
    await tester.pump();
    expect(find.text('Введите почту или логин'), findsOneWidget, reason: 'ошибки — у поля');
    expect(find.text('Введите пароль'), findsOneWidget);

    await tester.tap(find.text('Показать'));
    await tester.pump();
    expect(find.text('Скрыть'), findsOneWidget);

    await tester.tap(find.text('ҚАЗ'));
    await tester.pumpAndSettle();
    expect(session.locale, 'kk');
    expect(tester.takeException(), isNull);
  });

  testWidgets('wrong password: error under the field and an offer to sign in with the authenticator code', (tester) async {
    await tallPhone(tester);
    final session = await backendSession(roles: ['doctor']);
    await tester.pumpWidget(app(session, const LoginScreen()));
    await tester.enterText(find.byType(TextField).at(0), 'doctor1');
    await tester.enterText(find.byType(TextField).at(1), 'wrong');
    await tester.tap(find.text('Войти'));
    await tester.pumpAndSettle();
    expect(find.text('Неверный логин или пароль'), findsOneWidget);
    expect(find.text('Войти с кодом из приложения'), findsOneWidget);
    expect(session.isAuthenticated, isFalse);
  });

  testWidgets('second factor: login without a code fails, the code screen accepts pasted digits, a wrong code errs at the field, the right one signs in',
      (tester) async {
    await tallPhone(tester);
    final requests = <http.Request>[];
    final session = await backendSession(roles: ['doctor'], otp: true, requests: requests);
    final router = await pumpRouter(tester, session);
    await tester.enterText(find.byType(TextField).at(0), 'doctor1');
    await tester.enterText(find.byType(TextField).at(1), 'darumen');
    await tester.tap(find.text('Войти'));
    await settle(tester);
    expect(find.text('Неверный логин или пароль'), findsOneWidget, reason: 'Keycloak не отличает пропущенный код от неверного пароля');

    await tester.tap(find.text('Войти с кодом из приложения'));
    await settle(tester);
    expect(router.routerDelegate.currentConfiguration.matches.last.matchedLocation, '/login/otp');
    for (final text in ['Подтвердите вход', 'Введите 6 цифр из приложения-аутентификатора', 'Код обновляется каждые 30 секунд', 'ДРУГОЙ СПОСОБ', 'Код из приложения',
      'Текущий', 'SMS-код', 'Резервный код', 'Подтвердить']) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    expect(find.textContaining('Отправить повторно'), findsNothing, reason: 'TOTP не отправляется — таймера нет');
    // SMS — шлюз не подключён (как у каналов уведомлений), резервные коды — после интеграции
    expect(find.text('Сервис ещё не подключён'), findsOneWidget);
    expect(find.text('после интеграции'), findsOneWidget);

    await tester.tap(find.text('Подтвердить'));
    await tester.pump();
    expect(find.text('Введите все 6 цифр'), findsOneWidget);

    await tester.enterText(find.descendant(of: find.byType(OtpField), matching: find.byType(TextField)), '000 000');
    await settle(tester);
    expect(find.byKey(const ValueKey('otp-error')), findsOneWidget, reason: 'неверный код — ошибка у поля, код очищен');
    expect(find.textContaining('Код не подошёл'), findsOneWidget);

    await tester.enterText(find.descendant(of: find.byType(OtpField), matching: find.byType(TextField)), '12 34 56');
    await settle(tester);
    expect(session.isAuthenticated, isTrue);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/doctor/patients');
    final last = requests.where((r) => r.url.path.endsWith('/token')).last;
    expect(last.bodyFields['totp'], '123456', reason: 'вставка «12 34 56» раскладывается по ячейкам и уходит цифрами');
    expect(session.needsOtp('doctor1'), isTrue);
  });

  testWidgets('a login that needed a code on this device goes straight to the code screen', (tester) async {
    await tallPhone(tester);
    final session = await backendSession(roles: ['doctor'], otp: true);
    await session.login('doctor1', 'darumen', otp: '123456');
    await session.logout();
    final router = await pumpRouter(tester, session);
    await tester.enterText(find.byType(TextField).at(0), 'DOCTOR1');
    await tester.enterText(find.byType(TextField).at(1), 'darumen');
    await tester.tap(find.text('Войти'));
    await settle(tester);
    expect(router.routerDelegate.currentConfiguration.matches.last.matchedLocation, '/login/otp', reason: 'экран кода кладётся поверх входа');
    expect(find.text('Подтвердите вход'), findsOneWidget);
  });

  testWidgets('forgot password: format error at the field, missing endpoint shows an error, 202 shows «Проверьте почту»', (tester) async {
    await tallPhone(tester);
    final requests = <http.Request>[];
    var endpoint = false;
    final session = await backendSession(
      requests: requests,
      handler: (r) => endpoint && r.url.path.endsWith('/public/password-reset') ? http.Response('', 202) : null,
    );
    await tester.pumpWidget(app(session, const ForgotPasswordScreen()));
    await tester.pump();
    expect(find.text('Восстановление пароля'), findsOneWidget);
    expect(find.text('ссылка действует 60 минут'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'not-an-email');
    await tester.tap(find.text('Отправить ссылку'));
    await tester.pump();
    expect(find.text('Укажите почту в формате name@example.kz'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'a.seitkali@almaty-onco.kz');
    await tester.tap(find.text('Отправить ссылку'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Восстановление пароля пока недоступно'), findsOneWidget, reason: 'эндпоинта нет — ошибка, не падение');
    expect(find.text('Проверьте почту'), findsNothing);

    endpoint = true;
    await tester.tap(find.text('Отправить ссылку'));
    await tester.pumpAndSettle();
    expect(find.text('Проверьте почту'), findsOneWidget);
    expect(find.textContaining('a.seitkali@almaty-onco.kz'), findsWidgets);
    expect(find.text('Ко входу'), findsOneWidget);
    final sent = requests.lastWhere((r) => r.url.path.endsWith('/public/password-reset'));
    expect(jsonDecode(sent.body), {'email': 'a.seitkali@almaty-onco.kz'});
  });

  testWidgets('security: password age, SMS not connected, authenticator status, devices with «Завершить» and «Завершить все, кроме этого»', (tester) async {
    await tallPhone(tester);
    final requests = <http.Request>[];
    final changed = DateTime.now().subtract(const Duration(days: 12, hours: 1)).toUtc().toIso8601String();
    final session = await backendSession(
      roles: ['doctor'],
      signIn: true,
      requests: requests,
      handler: (r) => switch ((r.method, r.url.path)) {
        ('GET', '/api/v1/me/security') => json({
            'passwordChangedAt': changed,
            'otpConfigured': false,
            'smsAvailable': false,
            'recoveryCodes': null,
            'recentLogins': [],
            'sessions': [
              {'id': 's1', 'device': 'Android', 'browser': 'Darumen', 'ip': '10.0.2.2', 'lastAccess': '2026-09-28T09:00:00Z', 'current': true},
              {'id': 's2', 'device': 'Рабочий ПК', 'browser': 'Chrome', 'ip': '10.0.0.5', 'lastAccess': '2026-09-27T18:40:00Z', 'current': false},
            ],
          }),
        ('DELETE', _) => http.Response('', 204),
        _ => null,
      },
    );
    await tester.pumpWidget(app(session, const SecurityScreen()));
    await tester.pumpAndSettle();
    for (final text in ['Безопасность', 'ВХОД', 'Пароль', 'изменён 12 дн. назад', 'Сменить', 'SMS-код', 'Сервис ещё не подключён', 'Приложение-аутентификатор', 'Не настроено', 'Настроить',
      'УСТРОЙСТВА', 'Android · Darumen', 'Это устройство', 'Рабочий ПК · Chrome', 'Завершить', 'Завершить все, кроме этого']) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    await tester.tap(find.text('Завершить'));
    await tester.pumpAndSettle();
    expect(requests.any((r) => r.method == 'DELETE' && r.url.path == '/api/v1/me/sessions/s2'), isTrue);
    expect(find.text('Сеанс завершён'), findsOneWidget);

    await tester.tap(find.text('Завершить все, кроме этого'));
    await tester.pumpAndSettle();
    expect(requests.any((r) => r.method == 'DELETE' && r.url.path == '/api/v1/me/sessions' && r.url.queryParameters['keepCurrent'] == 'true'), isTrue);
  });

  testWidgets('security: API error shows the W-States error with «Повторить», 403 shows «нет доступа»', (tester) async {
    await tallPhone(tester);
    var status = 500;
    final session = await backendSession(roles: ['doctor'], signIn: true, handler: (r) => r.url.path.endsWith('/me/security') ? json({'title': 'Ошибка'}, status) : null);
    await tester.pumpWidget(app(session, const SecurityScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Не удалось загрузить данные'), findsOneWidget);
    expect(find.text('Повторить'), findsOneWidget);

    status = 403;
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();
    expect(find.text('Нет доступа к разделу'), findsOneWidget);
  });

  testWidgets('state views: forbidden reasons from rbac.md codes, filtered empty resets, stale data banner', (tester) async {
    await tallPhone(tester);
    var reset = false;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: ListView(children: [
          ErrorState(error: ApiException(403, 'Forbidden', detail: 'no_organization')),
          ForbiddenState(error: ApiException(403, 'Пациент другого региона')),
          ErrorState(error: Exception('socket'), onRetry: () {}),
          FilteredEmptyState(onReset: () => reset = true),
          const StaleDataBanner(asOf: '2025-03-31'),
        ]),
      ),
    ));
    expect(find.text('Нет доступа к разделу'), findsNWidgets(2));
    expect(find.text('К учётной записи не привязана организация: раздел откроется, когда администратор её укажет.'), findsOneWidget);
    expect(find.text('Пациент другого региона'), findsOneWidget);
    expect(find.text('Сервер не отвечает — проверьте соединение.'), findsOneWidget);
    await tester.tap(find.text('Сбросить фильтры'));
    expect(reset, isTrue);
    expect(find.text('Данные на 31.03.2025'), findsOneWidget);
    expect(StaleDataBanner.isStale('2025-03-31', now: DateTime(2026, 9, 28)), isTrue);
    expect(StaleDataBanner.isStale('2026-09-27', now: DateTime(2026, 9, 28)), isFalse);
    expect(StaleDataBanner.isStale(''), isFalse);
  });

  testWidgets('kazakh labels at 1.3x text scale on a 360 dp phone do not overflow login, code, reset, security and web-only screens', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = await backendSession(
      roles: ['regulator'],
      signIn: true,
      handler: (r) => r.url.path.endsWith('/me/security')
          ? json({'passwordChangedAt': null, 'otpConfigured': true, 'smsAvailable': false, 'sessions': [
              {'id': 's1', 'device': 'Android', 'browser': 'Darumen', 'ip': '10.0.2.2', 'lastAccess': '2026-09-28T09:00:00Z', 'current': true},
              {'id': 's2', 'device': 'Ординатордағы планшет', 'browser': 'Chrome', 'ip': '10.0.0.5', 'lastAccess': '2026-09-27T18:40:00Z', 'current': false},
            ]})
          : null,
    );
    for (final screen in <Widget>[
      const LoginScreen(),
      const OtpScreen(request: OtpRequest(username: 'u', password: 'p', remember: true)),
      const ForgotPasswordScreen(),
      const SecurityScreen(),
      const WebOnlyScreen(),
    ]) {
      await tester.pumpWidget(ChangeNotifierProvider<Session>.value(
        value: session,
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('kk'),
          supportedLocales: const [Locale('ru'), Locale('kk')],
          localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
          builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)), child: child!),
          home: screen,
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: screen.runtimeType.toString());
    }
  });
}
