import 'package:darumen/screens/updates_screen.dart';
import 'package:darumen/widgets/state_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'citizen_route_test.dart' show tapAction;
import 'citizen_support.dart';
import 'support/harness.dart';

/// «Уведомления» гражданина — колокольчик сервера (`GET /route/me/notifications`, F13): порядок сервера, «новых: N»,
/// метка «нужен ответ», непрочитанные — точкой и жирным; тап отмечает прочитанным и открывает «Мой путь» или читалку
/// памятки (Q9); тексты всех видов в двух языках; заметка о push.
const bellPath = '/route/me/notifications';

Future<DemoBackend> pumpUpdates(WidgetTester tester, Object bell, {Map<String, Object?> api = const {}, String locale = 'ru', double textScale = 1, Size size = phoneTall}) async {
  final (session, backend) = await demoSession(DemoUser.citizen1, api: {bellPath: bell, ...api}, locale: locale);
  await pumpScreen(tester, session, const UpdatesScreen(), locale: locale, textScale: textScale, size: size);
  return backend;
}

void main() {
  testWidgets('the server list in server order: «новых: 4», needs-answer first with its marker, the expiring tests without a time', (tester) async {
    await pumpUpdates(tester, fixtureMap('route-me-notifications'));
    expect(find.text('новых: 4'), findsOneWidget);
    expect(find.textContaining('Врач предлагает перевод: Региональный военный госпиталь'), findsOneWidget);
    expect(find.textContaining('Нужен ваш ответ'), findsOneWidget);
    expect(find.textContaining('нужен ответ'), findsOneWidget);
    expect(find.text('Анализы истекут до госпитализации: 7'), findsOneWidget);
    expect(find.text('Врач предложил перевод: Достар Мед'), findsOneWidget, reason: 'на уже отвеченный перевод — без призыва (Q15)');
    expect(find.text('Врач оставил вас в вашей больнице'), findsOneWidget);
    expect(find.text('«профиль требует именно этой клиники»'), findsOneWidget);
    final order = ['Врач предлагает перевод', 'Анализы истекут', 'Врач предложил перевод', 'Врач оставил вас']
        .map((t) => tester.getTopLeft(find.textContaining(t).first).dy)
        .toList();
    expect(order, [...order]..sort(), reason: 'порядок сервера, без перегруппировки по дням');
    expect(find.text('Push-уведомления сейчас не приходят. Новые события появляются здесь.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tap on an unread item marks it read on the server and opens «Мой путь»', (tester) async {
    final (session, backend) = await demoSession(DemoUser.citizen1, api: {
      bellPath: fixtureMap('route-me-notifications'),
      'POST /read': noContent(),
      '/route/me': routeMe(),
    });
    final router = await pumpRouterApp(tester, session, location: '/updates', size: phoneTall);
    await tapAction(tester, 'Анализы истекут до госпитализации: 7');
    expect(backend.calls('POST', '/read'), hasLength(1));
    expect(backend.calls('POST', '/read').single.url.path, endsWith('/route/me/notifications/733d41f7-fa74-164e-b0f5-6fe56cf7d470/read'));
    expect(router.state.uri.path, '/home/route');
    expect(find.text('Врач предлагает перевод'), findsOneWidget);
  });

  testWidgets('a read item is muted and opening it sends no second «read»', (tester) async {
    final (session, backend) = await demoSession(DemoUser.citizen1, api: {
      bellPath: {
        'unread': 0,
        'items': [notification('n-keep', 'keep', moName: dostar, read: true)],
      },
      '/route/me': routeMe(status: 'kept', decisions: [], signals: []),
    });
    final router = await pumpRouterApp(tester, session, location: '/updates', size: phoneTall);
    expect(find.textContaining('новых'), findsNothing);
    await tapAction(tester, 'Врач оставил вас в вашей больнице');
    expect(backend.calls('POST', '/read'), isEmpty);
    expect(router.state.uri.path, '/home/route');
  });

  testWidgets('a leaflet notification opens the leaflet reader (Q9)', (tester) async {
    final (session, _) = await demoSession(DemoUser.citizen1, api: {
      bellPath: {
        'unread': 1,
        'items': [notification('n-leaf', 'scribe_leaflet', at: '2026-09-30T07:00:00+00:00', moName: 'ГКБ №7')],
      },
      'POST /read': noContent(),
      '/route/me': routeMe(status: 'waiting', decisions: [], signals: []),
      '/route/me/scribe': [scribeConsent('req-1', 'completed', token: 'tok-leaf', approvedAt: '2026-09-30T07:00:00+00:00')],
      '/scribe/leaflets/tok-leaf': {'text': 'Отдыхайте.', 'language': 'ru', 'approvedAt': '2026-09-30T07:00:00+00:00'},
    });
    final router = await pumpRouterApp(tester, session, location: '/updates', size: phoneTall);
    expect(find.text('Памятка врача готова: ГКБ №7'), findsOneWidget);
    await tapAction(tester, 'Памятка врача готова: ГКБ №7');
    expect(router.state.uri.path, '/home/route/leaflet/tok-leaf');
    expect(find.textContaining('Отдыхайте.'), findsOneWidget);
  });

  testWidgets('every kind has its text; confirm and reschedule carry the date', (tester) async {
    await pumpUpdates(tester, {
      'unread': 9,
      'items': [
        notification('1', 'scribe_consent', moName: 'ГКБ №7', needsAction: true),
        notification('2', 'cancel'),
        notification('3', 'confirm', moName: dostar, plannedAt: '2026-10-05'),
        notification('4', 'reject', moName: dostar),
        notification('5', 'reschedule', moName: dostar, plannedAt: '2026-10-07'),
        notification('6', 'admit', moName: dostar),
        notification('7', 'no_show', moName: dostar),
        notification('8', 'discharge', moName: dostar),
        notification('9', 'close'),
      ],
    });
    for (final text in [
      'ГКБ №7 просит разрешение записать приём',
      'Врач отменил перевод',
      'Достар Мед: дата госпитализации 05.10.2026',
      'Достар Мед: не могут принять',
      'Достар Мед: новая дата 07.10.2026',
      'Вы госпитализированы: Достар Мед',
      'Отмечено, что вы не пришли: Достар Мед',
      'Вы выписаны: Достар Мед',
      'Вас сняли с листа ожидания',
    ]) {
      await tester.scrollUntilVisible(find.text(text), 200);
      expect(find.text(text), findsOneWidget, reason: text);
    }
  });

  testWidgets('empty bell: «Новых уведомлений нет»', (tester) async {
    await pumpUpdates(tester, {'unread': 0, 'items': <Object?>[]});
    expect(find.text('Новых уведомлений нет'), findsOneWidget);
  });

  testWidgets('a failed first read shows the load error; «Повторить» reads again', (tester) async {
    var reads = 0;
    await pumpUpdates(tester, (_) => ++reads == 1 ? problem(503, 'Service Unavailable') : json(fixtureMap('route-me-notifications')));
    expect(find.byType(ErrorState), findsOneWidget);
    await tapAction(tester, 'Повторить');
    expect(find.text('новых: 4'), findsOneWidget);
  });

  testWidgets('kazakh at 1.3 on a 360 dp phone: all kinds fit and read in Kazakh', (tester) async {
    await pumpUpdates(
      tester,
      {
        'unread': 4,
        'items': [
          notification('a', 'redirect', moName: militaryHospital, needsAction: true),
          notification('b', 'tests_expiring', count: 7),
          notification('c', 'scribe_leaflet', moName: 'ГКБ №7'),
          notification('d', 'reschedule', moName: dostar, plannedAt: '2026-10-07', reason: 'плановый ремонт отделения'),
        ],
      },
      locale: 'kk',
      textScale: 1.3,
      size: phoneNarrow,
    );
    expect(find.text('жаңа: 4'), findsOneWidget);
    expect(find.textContaining('Жауабыңыз керек'), findsOneWidget);
    expect(find.textContaining('жауап керек'), findsOneWidget);
    expect(find.text('Емдеуге жатқызуға дейін талдаулар мерзімі өтеді: 7'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Достар Мед: жаңа күн 07.10.2026'), 200);
    expect(tester.takeException(), isNull);
  });
}
