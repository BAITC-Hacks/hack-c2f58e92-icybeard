import 'package:darumen/screens/consents_screen.dart';
import 'package:darumen/screens/incoming_referrals_screen.dart';
import 'package:darumen/screens/leaflet_screen.dart';
import 'package:darumen/screens/staff_notifications_screen.dart';
import 'package:darumen/widgets/app_shell.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shell_test.dart' show pumpApp, settle;
import 'support/harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('citizen: the leaflet reader is nested under «Мой путь», without the pill, and «назад» returns to the route', (tester) async {
    final router = await pumpApp(tester, roles: ['citizen']);
    router.go('/home/route');
    await settle(tester);
    router.go('/home/route/leaflet/a1b2c3d4e5f6a7b8c9');
    await settle(tester);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/home/route/leaflet/a1b2c3d4e5f6a7b8c9');
    expect(tester.widget<LeafletScreen>(find.byType(LeafletScreen)).token, 'a1b2c3d4e5f6a7b8c9');
    expect(find.text('Памятка после приёма'), findsOneWidget);
    expect(find.text('памятка F6A7B8C9'), findsOneWidget, reason: 'номер — последние 8 символов токена, как в вебе');
    expect(find.byType(FloatingNav), findsNothing);
    await tester.tap(find.byTooltip('Назад'));
    await settle(tester);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/home/route');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a leaflet token that looks like a guarded screen name still opens the leaflet', (tester) async {
    final router = await pumpApp(tester, roles: ['citizen']);
    router.go('/home/route/leaflet/scribe');
    await settle(tester);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/home/route/leaflet/scribe');
    expect(find.byType(LeafletScreen), findsOneWidget);
  });

  testWidgets('«Данные и согласия» is an account screen under the profile of both shells', (tester) async {
    for (final (roles, claims, path) in [
      (['citizen'], const <String, Object?>{}, '/profile/consents'),
      (['doctor'], const <String, Object?>{'mo_code': '028B'}, '/doctor/profile/consents'),
    ]) {
      final router = await pumpApp(tester, roles: roles, region: '75', claims: claims);
      router.go(path);
      await settle(tester);
      expect(router.routerDelegate.currentConfiguration.uri.path, path);
      expect(find.byType(ConsentsScreen), findsOneWidget, reason: path);
      expect(find.text('Данные и согласия'), findsOneWidget);
      expect(find.byType(FloatingNav), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('citizen cannot open the doctor-only screens: incoming and staff notifications bounce to /home', (tester) async {
    final router = await pumpApp(tester, roles: ['citizen']);
    for (final path in ['/doctor/incoming', '/doctor/notifications']) {
      router.go(path);
      await settle(tester);
      expect(router.routerDelegate.currentConfiguration.uri.path, '/home', reason: path);
    }
    expect(find.byType(IncomingReferralsScreen), findsNothing);
    expect(find.byType(StaffNotificationsScreen), findsNothing);
  });

  testWidgets('incoming tab: title, the web empty state of an empty list and the pill; no back button at a tab root', (tester) async {
    final router = await pumpApp(tester, roles: ['chief'], claims: {'mo_code': '028B', 'region_kato': '75'}, api: {'/journal/referrals/incoming': <Object>[]});
    router.go('/doctor/incoming');
    await settle(tester);
    expect(find.text('Входящие направления'), findsOneWidget);
    expect(find.text('Входящих направлений нет'), findsOneWidget);
    expect(find.text('Здесь появятся направления из других организаций, как только врач их отправит.'), findsOneWidget);
    expect(find.byType(FloatingNav), findsOneWidget);
    expect(find.byTooltip('Назад'), findsNothing, reason: 'корень вкладки');
  });

  testWidgets('four doctor tabs in Kazakh at 1.3× on a 360 dp phone fit the pill without overflow; the badge stays visible', (tester) async {
    final (session, _) = await demoSession(DemoUser.doctor1, api: {
      '/journal/notifications/bell': {'pendingIncomingCount': 12},
    });
    await pumpRouterApp(tester, session, location: '/doctor/incoming', locale: 'kk', textScale: 1.3, size: phoneNarrow);
    final labels = tester.widget<FloatingNav>(find.byType(FloatingNav)).destinations.map((d) => d.label);
    expect(labels, ['Науқастар', 'Кіріс', 'Шешімдер', 'Профиль']);
    expect(find.text('Кіріс жолдамалар'), findsOneWidget);
    expect(find.descendant(of: find.byType(FloatingNav), matching: find.text('12')), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'без переполнения');
  });
}
