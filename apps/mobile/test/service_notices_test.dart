import 'dart:convert';

import 'package:darumen/api/models.dart';
import 'package:darumen/router/app_router.dart';
import 'package:darumen/screens/forgot_password_screen.dart';
import 'package:darumen/screens/login_screen.dart';
import 'package:darumen/screens/notification_settings_screen.dart';
import 'package:darumen/screens/updates_screen.dart';
import 'package:darumen/state/service_status_notifier.dart';
import 'package:darumen/state/session.dart';
import 'package:darumen/theme/app_theme.dart';
import 'package:darumen/widgets/app_card.dart';
import 'package:darumen/widgets/notice_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'auth_screens_test.dart' show backendSession, json, tallPhone;
import 'screens_test.dart' show apiSession, app;
import 'service_status_test.dart' show allDown, allUp, contractSample, parse;
import 'shell_test.dart' show settle;

const emailBanner = 'Почтовый сервер недоступен. Письма — приглашения, сброс пароля, уведомления — сейчас не отправляются.';
const localizations = [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate];

/// Статус, который уже загружен: [fetch] отдаёт [status], `refresh` выполнен.
Future<ServiceStatusNotifier> loadedStatus(ServiceStatus status) async {
  final notifier = ServiceStatusNotifier(fetch: () async => status);
  await notifier.refresh();
  return notifier;
}

/// Сессия и статус над MaterialApp — листы и диалоги тоже их видят; [scale] — масштаб шрифта.
Widget providedApp(Session session, ServiceStatusNotifier status, Widget screen, {String locale = 'ru', double scale = 1}) => MultiProvider(
      providers: [ChangeNotifierProvider<Session>.value(value: session), ChangeNotifierProvider<ServiceStatusNotifier>.value(value: status)],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: Locale(locale),
        supportedLocales: const [Locale('ru'), Locale('kk')],
        localizationsDelegates: localizations,
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
        home: screen,
      ),
    );

/// Роутер целиком (оба shell'а) с сессией и статусом сервисов.
Future<GoRouter> pumpShell(WidgetTester tester, Session session, ServiceStatusNotifier status, {String locale = 'ru', double scale = 1}) async {
  final router = buildRouter(session);
  await tester.pumpWidget(MultiProvider(
    providers: [ChangeNotifierProvider<Session>.value(value: session), ChangeNotifierProvider<ServiceStatusNotifier>.value(value: status)],
    child: MaterialApp.router(
      theme: AppTheme.light(),
      locale: Locale(locale),
      supportedLocales: const [Locale('ru'), Locale('kk')],
      localizationsDelegates: localizations,
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
      routerConfig: router,
    ),
  ));
  await settle(tester);
  return router;
}

/// Сохранённые настройки: у изменяемых событий почта и push включены, SMS выключен; `security` закреплён.
Map<String, Object?> storedSettings({bool email = true, bool sms = false, bool push = true}) => {
      'events': [
        {'code': 'security', 'titleRu': 'Безопасность', 'titleKk': 'Қауіпсіздік', 'inApp': true, 'email': true, 'sms': false, 'push': false, 'locked': true},
        {'code': 'route_updates', 'titleRu': 'Изменения маршрута', 'titleKk': 'Маршрут өзгерістері', 'inApp': true, 'email': email, 'sms': sms, 'push': push, 'locked': false},
        {'code': 'referral_decisions', 'titleRu': 'Решения', 'titleKk': 'Шешімдер', 'inApp': true, 'email': false, 'sms': false, 'push': false, 'locked': false},
      ],
      'quietFrom': '22:00',
      'quietTo': '07:00',
      'quietExceptRegulator': true,
      'digest': 'weekly',
    };

/// Ответ `PUT /me/notifications`, как у API: сохранённое тело и признак `locked` у `security`.
Map<String, Object?> savedEcho(String body) {
  final saved = jsonDecode(body) as Map<String, dynamic>;
  return {
    ...saved,
    'events': [for (final e in (saved['events'] as List<dynamic>).cast<Map<String, dynamic>>()) {...e, 'locked': e['code'] == 'security'}],
  };
}

Switch switchOf(WidgetTester tester, String channel) =>
    tester.widget<Switch>(find.descendant(of: find.byKey(ValueKey('channel-$channel')), matching: find.byType(Switch)));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('email banner in the shells', () {
    testWidgets('citizen shell: banner over every tab while mail is down, the cross hides it for the app session', (tester) async {
      final session = await apiSession(roles: ['citizen'], api: const {});
      final status = await loadedStatus(allDown);
      final router = await pumpShell(tester, session, status);
      expect(find.text(emailBanner), findsOneWidget);
      expect(find.byKey(const ValueKey('email-outage-banner')), findsOneWidget);

      await tester.tap(find.text('Уведомления').last);
      await settle(tester);
      expect(router.routerDelegate.currentConfiguration.uri.path, '/updates');
      expect(find.text(emailBanner), findsOneWidget, reason: 'баннер над всеми экранами shell');

      await tester.tap(find.byTooltip('Скрыть уведомление'));
      await settle(tester);
      expect(find.text(emailBanner), findsNothing);
      expect(status.showEmailBanner, isFalse);

      router.go('/profile');
      await settle(tester);
      await status.refresh();
      await settle(tester);
      expect(find.text(emailBanner), findsNothing, reason: 'закрытый баннер не возвращается при опросе');
      expect(tester.takeException(), isNull);
    });

    testWidgets('doctor shell shows the same banner; with working or unknown mail there is none', (tester) async {
      final session = await apiSession(roles: ['doctor'], region: '75', api: const {}, claims: const {'mo_code': '028B'});
      await pumpShell(tester, session, await loadedStatus(allDown));
      expect(find.text(emailBanner), findsOneWidget);
      expect(find.text('Пациенты'), findsWidgets);

      await pumpShell(tester, session, await loadedStatus(parse({...contractSample, 'email': {'available': true, 'reason': null}})));
      expect(find.text(emailBanner), findsNothing, reason: 'почта работает');

      await pumpShell(tester, session, await loadedStatus(ServiceStatus.fallback));
      expect(find.text(emailBanner), findsNothing, reason: 'статус не получен — про почту ничего не утверждаем');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the smtp_unreachable reason shows the same banner', (tester) async {
      final session = await apiSession(roles: ['citizen'], api: const {});
      await pumpShell(tester, session, await loadedStatus(parse({...contractSample, 'email': {'available': false, 'reason': 'smtp_unreachable'}})));
      expect(find.text(emailBanner), findsOneWidget);
    });
  });

  group('notification channels', () {
    testWidgets('profile says «только в приложении» and opens the channels screen in both shells', (tester) async {
      for (final (role, profile) in [('citizen', '/profile'), ('doctor', '/doctor/profile')]) {
        final session = await apiSession(roles: [role], region: '75', api: {'/me/notifications': storedSettings()}, claims: const {'mo_code': '028B'});
        final router = await pumpShell(tester, session, await loadedStatus(allDown));
        router.go(profile);
        await settle(tester);
        expect(find.text('только в приложении'), findsOneWidget, reason: role);
        await tester.tap(find.widgetWithText(ListRow, 'Уведомления'));
        await settle(tester);
        expect(router.routerDelegate.currentConfiguration.uri.path, '$profile/notifications', reason: role);
        expect(find.text('КАНАЛЫ ДОСТАВКИ'), findsOneWidget);
      }
    });

    testWidgets('email, SMS and push are disabled with reasons, stored values are shown as they are and nothing is sent', (tester) async {
      await tallPhone(tester);
      final requests = <http.Request>[];
      final session = await backendSession(
        roles: ['citizen'],
        signIn: true,
        requests: requests,
        handler: (r) => r.url.path == '/api/v1/me/notifications' ? json(storedSettings()) : null,
      );
      await tester.pumpWidget(providedApp(session, await loadedStatus(allDown), const NotificationSettingsScreen()));
      await tester.pumpAndSettle();
      for (final text in ['Уведомления', 'КАНАЛЫ ДОСТАВКИ', 'В приложении', 'Работает', 'Почта', 'Почтовый сервер не настроен', 'SMS', 'Push-уведомления',
        'Сейчас доставляются только уведомления в приложении.', 'Настроить по событиям в веб-кабинете']) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      expect(find.text('Сервис ещё не подключён'), findsNWidgets(2), reason: 'SMS и push');
      expect(find.textContaining('не сбрасываются'), findsOneWidget);
      expect(find.byType(Switch), findsNWidgets(4), reason: 'три канала и событие «Изменения моего маршрута» гражданина');
      expect(switchOf(tester, 'email').onChanged, isNull);
      expect(switchOf(tester, 'sms').onChanged, isNull);
      expect(switchOf(tester, 'push').onChanged, isNull);
      expect(switchOf(tester, 'email').value, isTrue, reason: 'сохранённое значение не сброшено');
      expect(switchOf(tester, 'sms').value, isFalse);
      expect(switchOf(tester, 'push').value, isTrue);

      await tester.tap(find.descendant(of: find.byKey(const ValueKey('channel-email')), matching: find.byType(Switch)));
      await tester.pumpAndSettle();
      expect(switchOf(tester, 'email').value, isTrue);
      expect(requests.where((r) => r.method == 'PUT'), isEmpty, reason: 'мобилка ничего не перезаписывает');
      expect(tester.takeException(), isNull);
    });

    testWidgets('with an unknown status the switches stay locked and say the service could not be checked', (tester) async {
      await tallPhone(tester);
      final session = await apiSession(roles: ['citizen'], api: {'/me/notifications': storedSettings()});
      await tester.pumpWidget(app(session, const NotificationSettingsScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Не удалось проверить работу сервиса'), findsOneWidget, reason: 'почта: статус неизвестен');
      expect(find.text('Сервис временно недоступен'), findsNWidgets(2), reason: 'SMS и push без статуса — недоступны');
      expect(switchOf(tester, 'email').onChanged, isNull);
      expect(find.text('Сейчас доставляются только уведомления в приложении.'), findsOneWidget);
    });

    testWidgets('a working channel saves through PUT and keeps the locked event, quiet hours, digest and other channels; a failure rolls back',
        (tester) async {
      await tallPhone(tester);
      final requests = <http.Request>[];
      var failPut = false;
      final session = await backendSession(
        roles: ['citizen'],
        signIn: true,
        requests: requests,
        handler: (r) => switch ((r.method, r.url.path)) {
          ('GET', '/api/v1/me/notifications') => json(storedSettings()),
          ('PUT', '/api/v1/me/notifications') => failPut ? json({'title': 'Ошибка сохранения'}, 500) : json(savedEcho(r.body)),
          _ => null,
        },
      );
      await tester.pumpWidget(providedApp(session, await loadedStatus(allUp), const NotificationSettingsScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Сейчас доставляются только уведомления в приложении.'), findsNothing);
      expect(find.textContaining('не сбрасываются'), findsNothing);
      expect(switchOf(tester, 'email').onChanged, isNotNull);

      await tester.tap(find.descendant(of: find.byKey(const ValueKey('channel-email')), matching: find.byType(Switch)));
      await tester.pumpAndSettle();
      final put = requests.singleWhere((r) => r.method == 'PUT');
      final body = jsonDecode(put.body) as Map<String, dynamic>;
      expect(body['quietFrom'], '22:00');
      expect(body['quietTo'], '07:00');
      expect(body['quietExceptRegulator'], isTrue);
      expect(body['digest'], 'weekly');
      expect(body['events'], [
        {'code': 'security', 'inApp': true, 'email': true, 'sms': false, 'push': false},
        {'code': 'route_updates', 'inApp': true, 'email': false, 'sms': false, 'push': true},
        {'code': 'referral_decisions', 'inApp': true, 'email': false, 'sms': false, 'push': false},
      ]);
      expect(switchOf(tester, 'email').value, isFalse);

      failPut = true;
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('channel-push')), matching: find.byType(Switch)));
      await tester.pumpAndSettle();
      expect(switchOf(tester, 'push').value, isTrue, reason: 'ошибка — откат');
      expect(find.textContaining('Сервер недоступен'), findsOneWidget);
    });
  });

  group('eGov sign-in', () {
    testWidgets('unavailable: secondary button with a caption; the sheet says the Smart Bridge endpoint was not provided', (tester) async {
      await tallPhone(tester);
      final session = await backendSession();
      await tester.pumpWidget(providedApp(session, await loadedStatus(allDown), const LoginScreen()));
      await tester.pump();
      expect(find.widgetWithText(OutlinedButton, 'Войти через eGov mobile'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Войти через eGov mobile'), findsNothing, reason: 'главным становится вход по логину');
      expect(find.text('Сервис eGov mobile сейчас недоступен'), findsOneWidget);

      await tester.tap(find.text('Войти через eGov mobile'));
      await tester.pumpAndSettle();
      expect(find.text('Вход через eGov mobile недоступен'), findsOneWidget);
      expect(
        find.text('Адрес сервиса eGov mobile (Smart Bridge) не предоставлен, поэтому вход через eGov сейчас недоступен. Войдите по логину и паролю.'),
        findsOneWidget,
      );
      expect(find.textContaining('Скоро'), findsNothing);
      expect(find.textContaining('НИТ'), findsNothing);

      await tester.tap(find.text('Войти по логину'));
      await tester.pumpAndSettle();
      expect(find.text('Вход через eGov mobile недоступен'), findsNothing);
      final focused = FocusManager.instance.primaryFocus;
      expect(focused?.context?.findAncestorWidgetOfExactType<TextField>()?.keyboardType, TextInputType.emailAddress, reason: 'фокус — в поле логина');
    });

    testWidgets('available: primary button without a caption; the sheet does not pretend sign-in works in the app', (tester) async {
      await tallPhone(tester);
      final session = await backendSession();
      await tester.pumpWidget(providedApp(session, await loadedStatus(allUp), const LoginScreen()));
      await tester.pump();
      expect(find.widgetWithText(FilledButton, 'Войти через eGov mobile'), findsOneWidget);
      expect(find.byKey(const ValueKey('egov-unavailable')), findsNothing);
      await tester.tap(find.text('Войти через eGov mobile'));
      await tester.pumpAndSettle();
      expect(find.textContaining('ещё не реализован'), findsOneWidget);
    });

    testWidgets('without a status eGov counts as unavailable with a generic reason; status changes update the button', (tester) async {
      await tallPhone(tester);
      final session = await backendSession();
      var next = ServiceStatus.fallback;
      final status = ServiceStatusNotifier(fetch: () async => next);
      addTearDown(status.dispose);
      await tester.pumpWidget(providedApp(session, status, const LoginScreen()));
      await tester.pump();
      expect(find.text('Сервис eGov mobile сейчас недоступен'), findsOneWidget);
      await tester.tap(find.text('Войти через eGov mobile'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Сервис eGov mobile сейчас недоступен, поэтому вход через eGov не работает.'), findsOneWidget);
      await tester.tap(find.text('Войти по логину'));
      await tester.pumpAndSettle();

      next = allUp;
      await status.refresh();
      await tester.pump();
      expect(find.text('Сервис eGov mobile сейчас недоступен'), findsNothing, reason: 'статус пришёл — подпись ушла');
      expect(find.widgetWithText(FilledButton, 'Войти через eGov mobile'), findsOneWidget);
    });
  });

  group('forgot password', () {
    testWidgets('mail down: attention card at the top, the action stays available and the result does not promise a letter', (tester) async {
      await tallPhone(tester);
      final requests = <http.Request>[];
      final session = await backendSession(requests: requests, handler: (r) => r.url.path.endsWith('/public/password-reset') ? http.Response('', 202) : null);
      await tester.pumpWidget(providedApp(session, await loadedStatus(allDown), const ForgotPasswordScreen()));
      await tester.pump();
      expect(find.byKey(const ValueKey('reset-mail-down')), findsOneWidget);
      expect(find.text('Письмо сейчас не придёт'), findsOneWidget);
      expect(find.textContaining('Обратитесь к администратору своей организации'), findsOneWidget);
      final cardTop = tester.getTopLeft(find.byKey(const ValueKey('reset-mail-down'))).dy;
      expect(cardTop, lessThan(tester.getTopLeft(find.text('РАБОЧАЯ ПОЧТА')).dy), reason: 'карточка — над формой');
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Отправить ссылку')).enabled, isTrue);

      await tester.enterText(find.byType(TextField), 'a.seitkali@almaty-onco.kz');
      await tester.tap(find.text('Отправить ссылку'));
      await tester.pumpAndSettle();
      expect(requests.where((r) => r.url.path.endsWith('/public/password-reset')), hasLength(1));
      expect(find.text('Запрос принят'), findsOneWidget);
      expect(find.text('Письмо на a.seitkali@almaty-onco.kz сейчас не отправится: почтовый сервер недоступен.'), findsOneWidget);
      expect(find.text('Проверьте почту'), findsNothing, reason: 'письмо не уйдёт — не обещаем');
      expect(tester.takeException(), isNull);
    });

    testWidgets('no card when mail works or its status is unknown', (tester) async {
      await tallPhone(tester);
      final session = await backendSession();
      for (final status in [allUp, ServiceStatus.fallback]) {
        await tester.pumpWidget(providedApp(session, await loadedStatus(status), const ForgotPasswordScreen()));
        await tester.pump();
        expect(find.byType(NoticeCard), findsNothing, reason: '$status');
      }
    });
  });

  testWidgets('updates: the push note follows the status and disappears once push works', (tester) async {
    final session = await apiSession(roles: ['citizen'], api: const {});
    await tester.pumpWidget(providedApp(session, await loadedStatus(allDown), const UpdatesScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Push-уведомления пока не приходят: сервис ещё не подключён. Новые события появляются здесь.'), findsOneWidget);
    expect(find.textContaining('eGov'), findsNothing);
    await tester.pumpWidget(providedApp(session, await loadedStatus(allUp), const UpdatesScreen()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Push-уведомления'), findsNothing);
  });

  testWidgets('kazakh at 1.3x on a 360 dp phone: banner, eGov caption and sheet, reset card, channels and updates do not overflow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = await backendSession(
      roles: ['citizen'],
      signIn: true,
      handler: (r) => r.url.path == '/api/v1/me/notifications' ? json(storedSettings()) : null,
    );
    final status = await loadedStatus(allDown);

    await tester.pumpWidget(providedApp(session, status, const LoginScreen(), locale: 'kk', scale: 1.3));
    await tester.pumpAndSettle();
    expect(find.text('eGov mobile қызметі қазір қолжетімсіз'), findsOneWidget);
    await tester.tap(find.text('eGov mobile арқылы кіру'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Smart Bridge'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'LoginScreen + лист eGov');

    for (final screen in <Widget>[const ForgotPasswordScreen(), const NotificationSettingsScreen(), const UpdatesScreen()]) {
      await tester.pumpWidget(providedApp(session, status, screen, locale: 'kk', scale: 1.3));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: screen.runtimeType.toString());
    }

    await pumpShell(tester, session, status, locale: 'kk', scale: 1.3);
    expect(find.text('Пошта сервері қолжетімсіз. Хаттар — шақырулар, құпия сөзді қалпына келтіру, хабарламалар — қазір жіберілмейді.'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'баннер в shell');
  });
}
