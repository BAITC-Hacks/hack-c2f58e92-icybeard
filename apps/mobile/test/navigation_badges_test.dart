import 'package:darumen/l10n/strings.dart';
import 'package:darumen/state/app_scope.dart';
import 'package:darumen/state/session.dart';
import 'package:darumen/theme/app_theme.dart';
import 'package:darumen/theme/tokens.dart';
import 'package:darumen/widgets/app_shell.dart';
import 'package:darumen/widgets/bell_button.dart';
import 'package:darumen/widgets/count_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/harness.dart';

Widget _themed(Widget child, {ThemeData? theme}) =>
    MaterialApp(theme: theme ?? AppTheme.light(), home: Scaffold(body: Center(child: child)));

BoxDecoration _pillDecoration(WidgetTester tester) =>
    tester.widget<Container>(find.descendant(of: find.byType(CountBadge), matching: find.byKey(CountBadge.pillKey))).decoration! as BoxDecoration;

void main() {
  group('CountBadge', () {
    testWidgets('shows the number on a dangerStrong pill, at least 16×16, white 11/700 text', (tester) async {
      await tester.pumpWidget(_themed(const CountBadge(count: 3)));
      expect(find.text('3'), findsOneWidget);
      expect(_pillDecoration(tester).color, ColorTokens.light.dangerStrong);
      final size = tester.getSize(find.byKey(CountBadge.pillKey));
      expect(size.height, greaterThanOrEqualTo(AppSizes.badge));
      expect(size.width, greaterThanOrEqualTo(AppSizes.badge));
      final text = tester.widget<Text>(find.text('3'));
      expect(text.style?.color, ColorTokens.light.onAccent);
      expect(text.style?.fontSize, 11);
      expect(text.style?.fontWeight, FontWeight.w700);
    });

    testWidgets('dark theme takes the dark dangerStrong token', (tester) async {
      await tester.pumpWidget(_themed(const CountBadge(count: 1), theme: AppTheme.dark()));
      expect(_pillDecoration(tester).color, ColorTokens.dark.dangerStrong);
    });

    testWidgets('hidden at zero and below; the child stays', (tester) async {
      await tester.pumpWidget(_themed(const CountBadge(count: 0, child: Icon(Icons.notifications_none))));
      expect(find.byKey(CountBadge.pillKey), findsNothing);
      expect(find.byIcon(Icons.notifications_none), findsOneWidget);
      await tester.pumpWidget(_themed(const CountBadge(count: -2)));
      expect(find.byKey(CountBadge.pillKey), findsNothing);
      expect(find.text('-2'), findsNothing);
    });

    testWidgets('caps at 99+ and grows sideways for long numbers', (tester) async {
      await tester.pumpWidget(_themed(const CountBadge(count: 120)));
      expect(find.text('99+'), findsOneWidget);
      final wide = tester.getSize(find.byKey(CountBadge.pillKey)).width;
      await tester.pumpWidget(_themed(const CountBadge(count: 5)));
      expect(tester.getSize(find.byKey(CountBadge.pillKey)).width, lessThan(wide));
    });

    testWidgets('with a child the pill sits at the top-right corner of the child and overflows it', (tester) async {
      await tester.pumpWidget(_themed(const CountBadge(count: 7, child: SizedBox(width: 22, height: 22, key: ValueKey('icon')))));
      final icon = tester.getRect(find.byKey(const ValueKey('icon')));
      final pill = tester.getRect(find.byKey(CountBadge.pillKey));
      expect(pill.top, lessThan(icon.top), reason: 'top: -4');
      expect(pill.right, greaterThan(icon.right), reason: 'right: -8');
      expect(tester.getSize(find.byType(CountBadge)), icon.size, reason: 'бейдж не меняет размер иконки');
    });

    testWidgets('the number is not read twice: the pill itself is excluded from semantics', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_themed(const CountBadge(count: 4)));
      expect(find.bySemanticsLabel('4'), findsNothing, reason: 'смысл счётчика озвучивает вкладка или кнопка');
      handle.dispose();
    });
  });

  group('FloatingNav badge', () {
    final s = S.of('ru');
    List<ShellDestination> destinations({int unread = 0}) => [
          ShellDestination(label: s.navHome, icon: Icons.home_outlined, path: '/home', branch: 0),
          ShellDestination(label: s.navUpdates, icon: Icons.notifications_none, path: '/updates', branch: 1, badge: unread, badgeLabel: s.bellUnread(unread)),
          ShellDestination(label: s.navProfile, icon: Icons.person_outline, path: '/profile', branch: 2),
        ];

    testWidgets('a destination with a count shows the badge on its icon and reads «Уведомления, новых: N»', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_themed(FloatingNav(selectedIndex: 0, destinations: destinations(unread: 5), onSelected: (_) {})));
      expect(find.byKey(CountBadge.pillKey), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.bySemanticsLabel('Уведомления, новых: 5'), findsOneWidget);
      expect(find.bySemanticsLabel('Главная'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('no count — no badge and the plain label', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_themed(FloatingNav(selectedIndex: 1, destinations: destinations(), onSelected: (_) {})));
      expect(find.byKey(CountBadge.pillKey), findsNothing);
      expect(find.bySemanticsLabel('Уведомления'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('tapping a destination with a badge still selects it', (tester) async {
      int? selected;
      await tester.pumpWidget(_themed(FloatingNav(selectedIndex: 0, destinations: destinations(unread: 2), onSelected: (i) => selected = i)));
      await tester.tap(find.text('Уведомления'));
      expect(selected, 1);
    });
  });

  group('BellButton', () {
    /// Колокольчик в шапке экрана и экран уведомлений — маленький роутер внутри настоящего AppScope.
    Future<GoRouter> pumpBell(WidgetTester tester, Session session) async {
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Center(child: BellButton()))),
        GoRoute(path: BellButton.target, builder: (_, _) => const Scaffold(body: Text('экран уведомлений'))),
      ]);
      await tester.pumpWidget(AppScope(session: session, child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router)));
      await pumpFrames(tester);
      return router;
    }

    const bell = {
      'pendingIncomingCount': 2,
      'unreadConfirmations': [
        {'decisionId': 'c1', 'patientRef': 'SYN-75-028B-381-01', 'toMoCode': '22GN', 'confirmedAt': '2026-10-01T09:00:00+00:00'},
      ],
      'unreadDischarges': [],
      'patientSignals': [
        {'id': 's1', 'patientRef': 'SYN-75-028B-381-03', 'kind': 'withdraw', 'at': '2026-10-01T11:00:00+00:00'},
      ],
    };

    testWidgets('a doctor of a hospital sees the bell with the total count; the tap pushes /doctor/notifications', (tester) async {
      final handle = tester.ensureSemantics();
      final (session, _) = await demoSession(DemoUser.doctor1, api: {'/journal/notifications/bell': bell});
      final router = await pumpBell(tester, session);
      expect(find.byType(BellButton), findsOneWidget);
      expect(find.byIcon(Icons.notifications_none), findsOneWidget);
      expect(find.text('4'), findsOneWidget, reason: 'ждут подтверждения 2 + подтверждение 1 + событие пациента 1');
      expect(find.byTooltip('Уведомления, новых: 4'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Уведомления, новых: 4')), findsWidgets);
      await tester.tap(find.byType(BellButton));
      await pumpFrames(tester);
      expect(router.state.uri.path, BellButton.target);
      expect(find.text('экран уведомлений'), findsOneWidget);
      expect(router.canPop(), isTrue, reason: 'push — «назад» вернёт к списку');
      handle.dispose();
    });

    testWidgets('no count — a plain bell labelled «Уведомления»', (tester) async {
      final (session, _) = await demoSession(DemoUser.chief1);
      await pumpBell(tester, session);
      expect(find.byIcon(Icons.notifications_none), findsOneWidget);
      expect(find.byKey(CountBadge.pillKey), findsNothing);
      expect(find.byTooltip('Уведомления'), findsOneWidget);
    });

    testWidgets('hidden without a hospital (admin), for a citizen and without the provider', (tester) async {
      for (final user in [DemoUser.admin1, DemoUser.citizen1]) {
        final (session, _) = await demoSession(user);
        await pumpBell(tester, session);
        expect(find.byIcon(Icons.notifications_none), findsNothing, reason: user.name);
      }
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: const Scaffold(body: BellButton())));
      expect(find.byIcon(Icons.notifications_none), findsNothing, reason: 'экран в тесте без AppScope');
    });

    testWidgets('Kazakh label at 1.3× text scale (the harness pumps the real providers, theme and localisation)', (tester) async {
      final (session, _) = await demoSession(DemoUser.doctor1, api: {'/journal/notifications/bell': bell});
      await pumpScreen(tester, session, const Scaffold(body: Center(child: BellButton())), locale: 'kk', textScale: 1.3);
      expect(find.byTooltip('Хабарламалар, жаңа: 4'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('shell strings', () {
    test('bell and badge texts follow the web dictionaries in both languages', () {
      final ru = S.of('ru');
      final kk = S.of('kk');
      expect(ru.navIncoming, 'Входящие');
      expect(kk.navIncoming, 'Кіріс');
      expect(ru.bellUnread(3), 'новых: 3');
      expect(kk.bellUnread(3), 'жаңа: 3');
      expect(ru.bellPendingIncoming(1), 'Ожидает подтверждения: 1');
      expect(ru.bellPendingIncoming(4), 'Ожидают подтверждения: 4');
      expect(kk.bellPendingIncoming(4), 'Растауды күтуде: 4');
      expect(ru.bellSemantics(0), 'Уведомления');
      expect(ru.bellSemantics(2), 'Уведомления, новых: 2');
      expect(kk.bellSemantics(2), 'Хабарламалар, жаңа: 2');
      expect(ru.leafletNumber(leafletId('a1b2c3d4e5f6a7b8c9')), 'памятка F6A7B8C9');
      expect(kk.leafletNumber(leafletId('abc')), 'жадынама ABC');
      for (final label in [ru.navIncoming, kk.navIncoming, ru.navDecisions, kk.navDecisions, ru.navPatients, kk.navPatients]) {
        expect(label.length, lessThanOrEqualTo(12), reason: 'подписи вкладок ≤ 12 символов: $label');
      }
    });
  });
}
