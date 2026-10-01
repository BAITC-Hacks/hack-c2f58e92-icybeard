import 'package:darumen/screens/home_screen.dart';
import 'package:darumen/widgets/route/stage_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'citizen_route_test.dart' show consentPath, signalsPath, tapAction;
import 'citizen_support.dart';
import 'support/harness.dart';

/// Главная гражданина: запрос записи приёма и карточка состояния маршрута с рабочими кнопками (решение Q2), сводка
/// «Ваша больница» с полоской этапов и строкой «Вы ещё ждёте?», плитки и подпись о данных. Маршрут — один на главную
/// и «Мой путь» (`CitizenRouteController`).
Future<DemoBackend> pumpHome(WidgetTester tester, Object route, {Map<String, Object?> api = const {}, String locale = 'ru', double textScale = 1, Size size = phoneTall}) async {
  final (session, backend) = await demoSession(DemoUser.citizen1, api: {'/route/me': route, ...api}, locale: locale);
  await pumpScreen(tester, session, const HomeScreen(), locale: locale, textScale: textScale, size: size);
  return backend;
}

void main() {
  testWidgets('a proposed transfer: the state card comes first and «Согласен» answers it from the home screen', (tester) async {
    final backend = await pumpHome(tester, routeMe(), api: {'POST $consentPath': recorded()});
    final card = tester.getTopLeft(find.text('Врач предлагает перевод')).dy;
    expect(card, lessThan(tester.getTopLeft(find.text('ВАША БОЛЬНИЦА')).dy), reason: 'действие — над сводкой');
    await tapAction(tester, 'Согласен');
    expect(backend.lastBody('POST', consentPath), {'decisionId': transferId, 'accepted': true});
    expect(find.text('Вы согласились на перевод'), findsOneWidget);
  });

  testWidgets('the summary card: hospital, profile, three facts, the nodes-only strip with the count, tiles and the data note', (tester) async {
    await pumpHome(tester, routeMe(status: 'waiting', decisions: [], signals: []));
    expect(find.text('ВАША БОЛЬНИЦА'), findsOneWidget);
    expect(find.textContaining('Алматинский онкологический центр'), findsOneWidget);
    expect(find.text('Хирургические для взрослых'), findsOneWidget);
    expect(find.text('В листе ожидания с'), findsOneWidget);
    expect(find.text('10.02.2025'), findsOneWidget);
    expect(find.text('49 дн.'), findsOneWidget);
    expect(find.text('6 этапов · 3 пройдено'), findsOneWidget);
    expect(find.byType(StageStrip), findsOneWidget);
    expect(find.text('Внесено в лист ожидания'), findsNothing, reason: 'на главной — только узлы (Q3)');
    expect(find.text('Открыть маршрут'), findsOneWidget);
    expect(find.text('Сколько ждут'), findsOneWidget);
    expect(find.text('Лекарства'), findsOneWidget);
    expect(find.text('Вакцинация'), findsOneWidget);
    expect(find.text('Данные МЗ РК, I квартал 2025. Без персональных данных.'), findsOneWidget);
    expect(find.text('Врач предлагает перевод'), findsNothing);
  });

  testWidgets('a pending recording request is on the home screen with «Разрешаю» / «Не разрешаю»', (tester) async {
    final backend = await pumpHome(tester, routeMe(status: 'waiting', decisions: [], signals: []), api: {
      '/route/me/scribe': [scribeConsent('req-1', 'pending')],
      'POST /route/me/scribe/req-1/answer': recorded(),
    });
    expect(find.text('Врач просит разрешение записать приём'), findsOneWidget);
    await tapAction(tester, 'Не разрешаю');
    expect(backend.lastBody('POST', '/route/me/scribe/req-1/answer'), {'granted': false});
    expect(find.text('Ответ отправлен врачу'), findsOneWidget);
  });

  testWidgets('a due validation is one line in the summary card: «Да, жду» sends still_waiting', (tester) async {
    final backend = await pumpHome(tester, routeMe(status: 'waiting', validationDue: true, decisions: [], signals: []), api: {'POST $signalsPath': recorded()});
    expect(find.text('Вы ещё ждёте?'), findsOneWidget);
    expect(find.text('Уже лечился в другом месте'), findsNothing, reason: 'полная карточка вопроса — в «Моём пути»');
    await tapAction(tester, 'Да, жду');
    expect(backend.lastBody('POST', signalsPath), {'kind': 'still_waiting'});
    expect(find.text('Ответ записан, врач его увидит'), findsOneWidget);
  });

  testWidgets('without still_waiting in allowed there is no validation line (H-6)', (tester) async {
    await pumpHome(tester, routeMe(status: 'waiting', validationDue: true, allowed: ['request_transfer'], decisions: [], signals: []));
    expect(find.text('Вы ещё ждёте?'), findsNothing);
  });

  testWidgets('a doctor answer while waiting shows on the home screen and «Понятно» hides it', (tester) async {
    await pumpHome(tester, routeMe(status: 'kept', decisions: [decision('d-keep', kind: 'keep')], signals: []));
    expect(find.text('Врач оставил в текущей организации'), findsOneWidget);
    await tapAction(tester, 'Понятно');
    expect(find.text('Врач оставил в текущей организации'), findsNothing);
  });

  testWidgets('no route in the region (404): the not-found card, the tiles stay', (tester) async {
    await pumpHome(tester, problem(404, 'Нет очередей в регионе'));
    expect(find.text('Маршрут не найден: в регионе нет активных очередей'), findsOneWidget);
    expect(find.text('Вакцинация'), findsOneWidget);
  });

  testWidgets('a network failure: the error box with «Повторить», the tiles stay', (tester) async {
    var reads = 0;
    await pumpHome(tester, (_) => ++reads == 1 ? problem(502, 'Bad Gateway') : json(routeMe()));
    expect(find.text('Сервер недоступен. Повторите попытку позже.'), findsOneWidget);
    expect(find.text('Сколько ждут'), findsOneWidget);
    await tapAction(tester, 'Повторить');
    expect(find.text('Врач предлагает перевод'), findsOneWidget);
  });

  testWidgets('home and «Мой путь» share one route: opening the route does not read it again', (tester) async {
    final (session, backend) = await demoSession(DemoUser.citizen1, api: {'/route/me': routeMe()});
    final router = await pumpRouterApp(tester, session, size: phoneTall);
    expect(router.state.uri.path, '/home');
    expect(backend.calls('GET', '/api/v1/route/me'), hasLength(1));
    await tapAction(tester, 'Открыть маршрут');
    expect(router.state.uri.path, '/home/route');
    expect(find.text('Мой путь'), findsOneWidget);
    expect(backend.calls('GET', '/api/v1/route/me'), hasLength(1), reason: 'тот же CitizenRouteController, без второй копии маршрута');
    expect(tester.takeException(), isNull);
  });

  testWidgets('kazakh at 1.3 on a 360 dp phone: state card, scribe card, summary with validation and tiles fit', (tester) async {
    for (final route in [routeMe(), routeMe(status: 'waiting', validationDue: true, decisions: [], signals: [])]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpHome(tester, route, api: {'/route/me/scribe': [scribeConsent('req-2', 'pending')]}, locale: 'kk', textScale: 1.3, size: phoneNarrow);
      await tester.scrollUntilVisible(find.text('Вакцинация'), 300);
      expect(tester.takeException(), isNull);
    }
    expect(find.text('Әлі күтіп отырсыз ба?'), findsOneWidget);
  });
}
