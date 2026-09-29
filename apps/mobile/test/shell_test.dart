import 'package:darumen/router/app_router.dart';
import 'package:darumen/theme/app_theme.dart';
import 'package:darumen/widgets/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'screens_test.dart' show apiSession;

/// Роутер целиком поверх мок-сессии: экраны получают 404 от мок-API и показывают ErrorBox, что для проверки
/// навигации достаточно. Скелетоны пульсируют бесконечно, поэтому вместо pumpAndSettle — фиксированные кадры.
Future<GoRouter> pumpApp(WidgetTester tester, {required List<String> roles, String? region, Map<String, Object?> claims = const {}, Map<String, Object> api = const {}}) async {
  final session = await apiSession(roles: roles, api: api, region: region, claims: claims);
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

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('citizen shell: floating pill with three tabs, hidden on nested screens, tabs switch branches', (tester) async {
    final router = await pumpApp(tester, roles: ['citizen']);
    expect(find.byType(FloatingNav), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing, reason: 'системный NavigationBar заменён плавающей пилюлей');
    expect(find.text('Уведомления'), findsOneWidget);
    expect(find.text('Профиль'), findsOneWidget);
    expect(find.text('Главная'), findsNWidgets(2), reason: 'H1 экрана и подпись вкладки');
    expect(find.text('Продолжить как гость'), findsNothing);

    router.go('/home/route');
    await settle(tester);
    expect(find.byType(FloatingNav), findsNothing, reason: 'на вложенных экранах вместо навигации — нижняя кнопка');
    expect(find.text('Мой путь'), findsOneWidget);
    expect(find.byTooltip('Назад'), findsOneWidget);

    router.go('/home');
    await settle(tester);
    await tester.tap(find.text('Профиль'));
    await settle(tester);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/profile');
    expect(find.text('Профиль'), findsNWidgets(2));
    expect(find.text('Выйти'), findsOneWidget);
    expect(find.text('Вакцинация'), findsNothing, reason: 'вакцинация — плитка на главной, не строка профиля');
    expect(tester.takeException(), isNull);
  });

  testWidgets('doctor shell: Пациенты · Решения · Профиль, assistant and scribe open without tabs', (tester) async {
    final router = await pumpApp(tester, roles: ['doctor'], region: '75');
    expect(router.routerDelegate.currentConfiguration.uri.path, '/doctor/patients');
    expect(find.byType(FloatingNav), findsOneWidget);
    expect(find.text('Пациенты'), findsNWidgets(2));
    expect(find.text('Решения'), findsOneWidget);
    expect(find.text('Профиль'), findsOneWidget);
    expect(find.text('Скрайб'), findsNothing);
    expect(find.text('Направление'), findsNothing);

    await tester.tap(find.text('Решения'));
    await settle(tester);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/doctor/decisions');
    expect(find.text('Журнал решений'), findsOneWidget);

    router.go('/doctor/scribe');
    await settle(tester);
    expect(find.byType(FloatingNav), findsNothing);
    expect(find.text('AI-скрайб'), findsOneWidget);

    router.go('/doctor/referral');
    await settle(tester);
    expect(find.byType(FloatingNav), findsNothing);
    expect(find.text('Подтвердить направление'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('regulator, steward and auditor see «Кабинет доступен в веб-версии» with «Открыть веб» and «Выйти», no tabs', (tester) async {
    for (final (role, title) in [('regulator', 'Регулятор (Минздрав)'), ('steward', 'Оператор данных'), ('auditor', 'Аудитор')]) {
      final router = await pumpApp(tester, roles: [role]);
      expect(router.routerDelegate.currentConfiguration.uri.path, '/web', reason: role);
      expect(find.text('Кабинет доступен в веб-версии'), findsOneWidget);
      expect(find.textContaining('«$title»'), findsOneWidget, reason: role);
      expect(find.text('Открыть веб'), findsOneWidget);
      expect(find.text('Выйти'), findsOneWidget);
      expect(find.byType(FloatingNav), findsNothing);
      router.go('/doctor/patients');
      await settle(tester);
      expect(router.routerDelegate.currentConfiguration.uri.path, '/web', reason: 'guard не пускает в чужой кабинет');
    }
    await tester.tap(find.text('Выйти'));
    await settle(tester);
    expect(find.text('Войти через eGov mobile'), findsOneWidget);
  });

  testWidgets('org_admin (legacy chief with mo_code) gets the doctor shell with the journal tab', (tester) async {
    final router = await pumpApp(tester, roles: ['chief'], claims: {'mo_code': '028B', 'region_kato': '75'});
    expect(router.routerDelegate.currentConfiguration.uri.path, '/doctor/patients');
    expect(find.text('Решения'), findsOneWidget);
    router.go('/doctor/scribe');
    await settle(tester);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/doctor/patients', reason: 'без scribe.use скрайб закрыт');
  });

  testWidgets('/me without decisions permissions hides the «Решения» tab, the other tabs still switch branches', (tester) async {
    final router = await pumpApp(tester, roles: ['doctor'], region: '75', api: {
      '/api/v1/me': {
        'userId': 'u',
        'displayName': 'Врач',
        'roles': ['doctor'],
        'permissions': [
          {'code': 'worklist.view', 'scope': 'all'},
          {'code': 'referral.confirm', 'scope': 'all'},
        ],
      },
    });
    expect(find.text('Решения'), findsNothing);
    expect(find.text('Профиль'), findsOneWidget);
    await tester.tap(find.text('Профиль'));
    await settle(tester);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/doctor/profile');
    expect(find.text('Безопасность'), findsOneWidget);
    router.go('/doctor/decisions');
    await settle(tester);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/doctor/patients');
  });

  testWidgets('without a session the router lands on the login screen only', (tester) async {
    final router = await pumpApp(tester, roles: []);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/login');
    expect(find.text('Войти через eGov mobile'), findsOneWidget);
    expect(find.text('Продолжить как гость'), findsNothing);
    expect(find.byType(FloatingNav), findsNothing);
  });
}
