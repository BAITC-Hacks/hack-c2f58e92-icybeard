import 'package:darumen/app.dart';
import 'package:darumen/state/app_scope.dart';
import 'package:darumen/state/citizen_notifications_notifier.dart';
import 'package:darumen/state/citizen_route_controller.dart';
import 'package:darumen/state/service_status_notifier.dart';
import 'package:darumen/state/session.dart';
import 'package:darumen/state/staff_bell_notifier.dart';
import 'package:darumen/widgets/app_shell.dart';
import 'package:darumen/widgets/count_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'support/harness.dart';

const _feed = '/route/me/notifications';
const _bell = '/journal/notifications/bell';

T _read<T>(WidgetTester tester) => Provider.of<T>(tester.element(find.byType(Scaffold).first), listen: false);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('citizen: the «Уведомления» tab shows the unread count of the bell and reads it out', (tester) async {
    final handle = tester.ensureSemantics();
    final (session, backend) = await demoSession(DemoUser.citizen1, api: {_feed: fixtureMap('route-me-notifications')});
    final router = await pumpRouterApp(tester, session);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/home');
    expect(backend.calls('GET', _feed), hasLength(1));
    expect(find.descendant(of: find.byType(FloatingNav), matching: find.text('4')), findsOneWidget);
    expect(find.bySemanticsLabel('Уведомления, новых: 4'), findsOneWidget);
    expect(backend.calls('GET', _bell), isEmpty, reason: 'колокольчик персонала гражданину не положен');
    handle.dispose();
  });

  testWidgets('doctor: the «Входящие» tab shows transfers waiting for confirmation; the citizen bell is not polled', (tester) async {
    final (session, backend) = await demoSession(DemoUser.doctor1, api: {_bell: {'pendingIncomingCount': 2}});
    await pumpRouterApp(tester, session);
    expect(find.descendant(of: find.byType(FloatingNav), matching: find.text('2')), findsOneWidget);
    expect(tester.widget<FloatingNav>(find.byType(FloatingNav)).destinations[1].badgeLabel, 'Ожидают подтверждения: 2');
    expect(backend.calls('GET', _bell).single.url.queryParameters['moCode'], '028B');
    expect(backend.calls('GET', _feed), isEmpty);
  });

  testWidgets('all state holders are provided above the router; the poll interval is injectable and stops with the tree', (tester) async {
    final (session, backend) = await demoSession(DemoUser.doctor1);
    await pumpRouterApp(tester, session, pollInterval: const Duration(seconds: 5));
    expect(_read<Session>(tester), same(session));
    expect(_read<ServiceStatusNotifier>(tester), isNotNull);
    expect(_read<CitizenRouteController>(tester).session, same(session));
    expect(_read<CitizenNotificationsNotifier>(tester).active, isFalse);
    expect(_read<StaffBellNotifier>(tester).active, isTrue);
    final before = backend.calls('GET', _bell).length;
    await tester.pump(const Duration(seconds: 5));
    expect(backend.calls('GET', _bell).length, before + 1);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 5));
    expect(backend.calls('GET', _bell).length, before + 1, reason: 'AppScope освободил держателей вместе с деревом');
  });

  testWidgets('a citizen action refreshes the bell at once; a new bell item reloads the route a screen asked for', (tester) async {
    var ids = ['a'];
    final (session, backend) = await demoSession(DemoUser.citizen1, api: {
      '/route/me': fixtureMap('route-me'),
      'POST /route/me/signals': recorded(),
      _feed: (http.Request r) => {
            'unread': ids.length,
            'items': [for (final id in ids) {'id': id, 'kind': 'keep', 'at': '2026-09-25T19:14:39+00:00', 'needsAction': false, 'read': false}],
          },
    });
    await pumpScreen(tester, session, const Scaffold(body: SizedBox()), pollInterval: const Duration(seconds: 10));
    final route = _read<CitizenRouteController>(tester);
    await route.ensureLoaded();
    final feedCalls = backend.calls('GET', _feed).length;

    await route.withdraw();
    await tester.pump();
    expect(backend.calls('GET', _feed).length, feedCalls + 1, reason: 'после действия — колокольчик сразу');

    final routeCalls = backend.calls('GET', '/route/me').length;
    ids = ['b', 'a'];
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(backend.calls('GET', '/route/me').length, routeCalls + 1, reason: 'новое событие на маршруте — перечитать маршрут');
  });

  testWidgets('the harness: /me of the demo user, the language from the session, fixtures from test/fixtures', (tester) async {
    final (doctor, _) = await demoSession(DemoUser.doctor1);
    expect(doctor.grantsFromApi, isTrue);
    expect(doctor.moCode, '028B');
    expect(doctor.organizationName, demoOrganizations['028B']);
    expect(doctor.displayName, 'Айгерим Сейткали');

    final (orphan, _) = await demoSession(DemoUser.doctor1, claimOverrides: {'mo_code': null});
    expect(orphan.moCode, isNull);
    expect(orphan.isCitizen, isTrue, reason: 'врач без организации — гражданский кабинет (Q-20)');

    final (citizen, _) = await demoSession(DemoUser.citizen1);
    await pumpScreen(
      tester,
      citizen,
      Builder(builder: (context) => Text('${Localizations.localeOf(context).languageCode} ${MediaQuery.sizeOf(context).width.round()} ${MediaQuery.textScalerOf(context).scale(10)}')),
      locale: 'kk',
      size: phoneNarrow,
      textScale: 1.3,
    );
    expect(find.text('kk 360 13.0'), findsOneWidget, reason: 'язык из сессии, узкий телефон, масштаб шрифта');
    expect(citizen.locale, 'kk');

    expect(fixtureMap('route-me')['patientRef'], 'SYN-75-08IV-121-01');
    expect(fixtureMap('route-me-notifications')['unread'], 4);
  });

  testWidgets('the real app root under AppScope: splash, then the citizen home with the pill and a live badge', (tester) async {
    final (session, _) = await demoSession(DemoUser.citizen1, api: {_feed: fixtureMap('route-me-notifications')});
    await tester.pumpWidget(AppScope(session: session, child: const DarumenApp()));
    await tester.pump(const Duration(seconds: 5));
    await pumpFrames(tester);
    expect(find.byType(FloatingNav), findsOneWidget);
    expect(find.descendant(of: find.byType(FloatingNav), matching: find.byKey(CountBadge.pillKey)), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
