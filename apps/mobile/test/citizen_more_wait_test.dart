import 'dart:convert';

import 'package:darumen/screens/wait_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/harness.dart';

/// «Сколько ждут» (§3, веб `WaitView.vue`): формулировки и структура веба, полосы одного цвета со сравнением со
/// средним по региону, «Как считается» с индексом и сезонностью NHS; «Попросить рассмотреть» — только при
/// `request_transfer` и только для региона и профиля своего маршрута (решения Q8, Q23), через контроллер маршрута.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const regions = {
    'items': [
      {'regionKato': '75', 'name': 'г. Алматы'},
      {'regionKato': '71', 'name': 'г. Астана'},
      {'regionKato': '19', 'name': 'Алматинская область'},
    ],
  };
  const profiles = {
    'items': [
      {'profileCode': 'DH', 'name': 'Дневной стационар', 'isDayHospital': true, 'referrals': 1},
      {'profileCode': '121', 'name': 'Хирургические для взрослых', 'isDayHospital': false, 'referrals': 10},
      {'profileCode': '021', 'name': 'Терапевтические', 'isDayHospital': false, 'referrals': 20},
    ],
  };
  const predict = {
    'p50Days': 47.4,
    'p90Days': 106.2,
    'pWithin30Days': 0.54,
    'pRefusal': 0.08,
    'explanation': {'summary': '', 'factors': <Object?>[]},
    'model': {'name': 'queue-lgbm', 'version': '2.3.1', 'trainedThrough': '2025-03-31'},
  };
  Map<String, Object?> alt(String code, String name, double p50, {String region = '75', bool neighbour = false}) =>
      {'mo': {'moCode': code, 'name': name, 'regionKato': region}, 'p50Days': p50, 'p90Days': p50 * 2, 'pRefusal': 0.1, 'distanceKm': 4.0, 'isNeighborRegion': neighbour};
  final alternatives = {
    'items': [
      alt('031N', 'Государственное коммунальное предприятие на праве хозяйственного ведения "Городская клиническая больница №7"', 30.6),
      alt('22GN', 'Товарищество с ограниченной ответственностью "Достар Мед"', 35.2),
      alt('08IV', 'Коммунальное государственное предприятие "Алматинский онкологический центр"', 47.0),
      alt('19AA', 'ГКП "Талгарская районная больница"', 60.1, region: '19', neighbour: true),
    ],
  };
  final index = {
    'items': [
      for (var i = 1; i <= 19; i++)
        i == 7
            ? {'regionKato': '75', 'name': 'г. Алматы', 'shareOver30': 0.42, 'p90Days': 98.0, 'indexValue': 51.3, 'rank': 7, 'n': 300}
            : {'regionKato': 'r$i', 'name': 'Регион $i', 'shareOver30': 0.3, 'p90Days': 70.0, 'indexValue': 60.0, 'rank': i, 'n': 100},
    ],
  };
  final seasonality = {
    'items': [
      for (var m = 1; m <= 12; m++) {'seriesId': 'rtt_waiting_list', 'month': m, 'multiplier': 1 + m / 100, 'title': 'RTT', 'source': 'NHS', 'sourceYear': 2020, 'windowLabel': '2017-01..2019-12'},
    ],
  };

  /// Маршрут фикстуры в листе ожидания: просить перевод можно, 22GN отказала, [openTo] — открытая просьба.
  Map<String, dynamic> waitingRoute({String? openTo}) {
    final json = fixtureMap('route-me');
    return {
      ...json,
      'progress': {
        ...json['progress'] as Map<String, dynamic>,
        'status': 'waiting',
        'allowed': ['prefer_current', 'request_transfer', 'still_waiting', 'withdraw'],
        'blockedMoCodes': ['22GN'],
        'transfer': null,
      },
      'signals': [
        if (openTo != null) {'decisionId': 'sig-1', 'recordedAt': '2026-10-02T06:00:00+00:00', 'kind': 'request_redirect', 'toMoCode': openTo, 'open': true},
      ],
    };
  }

  Map<String, Object?> api({Object? route, Object? alternativesReply, Object? predictReply}) => {
        '/refdata/regions': regions,
        '/refdata/profiles': profiles,
        '/refdata/route-standard': fixtureMap('route-standard'),
        '/refdata/seasonality': seasonality,
        '/index': index,
        'POST /queue/predict': predictReply ?? predict,
        'POST /queue/alternatives': alternativesReply ?? alternatives,
        'GET /route/me': route ?? waitingRoute(),
      };

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).first);
    await tester.pump();
  }

  Finder requestButton(String moCode) => find.byKey(ValueKey('wait-request-$moCode'));

  testWidgets('the region average card and the faster list in the web wording; no model line, no «предложил врач»', (tester) async {
    final (session, backend) = await demoSession(DemoUser.citizen1, api: api());
    await pumpScreen(tester, session, const WaitScreen(regionKato: '75', profileCode: '121'), size: phoneTall);

    expect(find.text('Сколько ждут'), findsOneWidget);
    expect(find.text('Оценка по региону и профилю койки на данных I квартала 2025 года. Без персональных данных.'), findsOneWidget);
    expect(find.text('г. Алматы'), findsOneWidget);
    expect(find.text('Хирургические для взрослых'), findsOneWidget);
    expect(find.text('В СРЕДНЕМ ПО РЕГИОНУ'), findsOneWidget);
    expect(find.text('Половина пациентов в регионе ждёт госпитализации не больше'), findsOneWidget);
    expect(find.text('≈ 47'), findsOneWidget);
    expect(find.text('9 из 10 пациентов ждут не больше 106 дн.\n54 % пациентов попадают в больницу в течение 30 дней.'), findsOneWidget);
    expect(find.text('Ориентир Минздрава РК — ждать не больше 20 дн.'), findsOneWidget);
    expect(find.text('Оценка по очередям I квартала 2025 · данные на 31.03.2025'), findsOneWidget);
    expect(find.textContaining('queue-lgbm'), findsNothing, reason: 'названия и версии модели нет (X7)');
    expect(find.textContaining('предложил врач'), findsNothing);

    final body = backend.lastBody('POST', '/queue/alternatives');
    expect(body['regionKato'], '75');
    expect(body['profileCode'], '121');
    expect(body['includeNeighbors'], isFalse);

    await scrollTo(tester, find.text('ГДЕ БЫСТРЕЕ В РЕГИОНЕ'));
    expect(find.text('031N'), findsOneWidget);
    expect(find.text('на 16 дн. быстрее среднего'), findsOneWidget);
    expect(find.text('как в среднем по региону'), findsOneWidget, reason: '47.0 и 47.4 — одинаково на округлённых днях');
    expect(find.text('19AA · сосед: Алматинская область'), findsOneWidget);
    expect(find.text('на 13 дн. дольше среднего'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('«Попросить рассмотреть» only where the own route allows it: not for the own and the blocked hospital', (tester) async {
    final (session, _) = await demoSession(DemoUser.citizen1, api: api());
    await pumpScreen(tester, session, const WaitScreen(regionKato: '75', profileCode: '121'), size: phoneTall);
    await scrollTo(tester, requestButton('031N'));
    expect(requestButton('031N'), findsOneWidget);
    expect(requestButton('19AA'), findsOneWidget, reason: 'соседний регион — тоже вариант маршрута');
    expect(requestButton('22GN'), findsNothing, reason: 'больница уже отказала');
    expect(requestButton('08IV'), findsNothing, reason: 'своя больница');
  });

  testWidgets('another profile or region, or a route in transfer: no request buttons at all', (tester) async {
    final (session, _) = await demoSession(DemoUser.citizen1, api: api());
    await pumpScreen(tester, session, const WaitScreen(regionKato: '75', profileCode: '021'), size: phoneTall);
    await scrollTo(tester, find.text('031N'));
    expect(find.text('Попросить рассмотреть'), findsNothing, reason: 'чужой профиль');

    await tester.pumpWidget(const SizedBox()); // новый экран, а не прежнее состояние
    final (pending, _) = await demoSession(DemoUser.citizen1, api: api(route: fixtureMap('route-me')));
    await pumpScreen(tester, pending, const WaitScreen(regionKato: '75', profileCode: '121'), size: phoneTall);
    await scrollTo(tester, find.text('031N'));
    expect(find.text('Попросить рассмотреть'), findsNothing, reason: 'идёт перевод — request_transfer нет в allowed');
  });

  testWidgets('a request goes through the route controller once, with the comment; then the row shows the chip', (tester) async {
    var requested = false;
    final (session, backend) = await demoSession(DemoUser.citizen1, api: {
      ...api(),
      'GET /route/me': (http.Request _) => json(waitingRoute(openTo: requested ? '031N' : null)),
      'POST /route/me/signals': (http.Request _) {
        requested = true;
        return recorded('sig-1');
      },
    });
    await pumpScreen(tester, session, const WaitScreen(regionKato: '75', profileCode: '121'), size: phoneTall);
    await scrollTo(tester, requestButton('031N'));
    await tester.tap(requestButton('031N'));
    await pumpFrames(tester);
    expect(find.text('КОММЕНТАРИЙ ВРАЧУ (НЕОБЯЗАТЕЛЬНО)'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  Ближе к дому  ');
    await tester.tap(find.byKey(const ValueKey('send-request')));
    await pumpFrames(tester);

    final calls = backend.calls('POST', '/route/me/signals');
    expect(calls, hasLength(1));
    expect(jsonDecode(calls.single.body), {'kind': 'request_redirect', 'toMoCode': '031N', 'comment': 'Ближе к дому'});
    expect(calls.single.headers['Idempotency-Key'], isNotEmpty);
    expect(calls.single.url.queryParameters['regionKato'], '75');
    expect(find.text('Запрос отправлен врачу'), findsOneWidget);
    await scrollTo(tester, find.text('Запрос отправлен'));
    expect(find.text('Запрос отправлен'), findsOneWidget);
    expect(requestButton('031N'), findsNothing);
  });

  testWidgets('cancelling the sheet sends nothing', (tester) async {
    final (session, backend) = await demoSession(DemoUser.citizen1, api: {...api(), 'POST /route/me/signals': recorded()});
    await pumpScreen(tester, session, const WaitScreen(regionKato: '75', profileCode: '121'), size: phoneTall);
    await scrollTo(tester, requestButton('031N'));
    await tester.tap(requestButton('031N'));
    await pumpFrames(tester);
    await tester.tap(find.text('Отмена'));
    await pumpFrames(tester);
    expect(backend.calls('POST', '/route/me/signals'), isEmpty);
  });

  testWidgets('409: the route is read again first, then the server text; the button disappears', (tester) async {
    var conflict = false;
    final (session, backend) = await demoSession(DemoUser.citizen1, api: {
      ...api(),
      'GET /route/me': (http.Request _) => json(conflict ? fixtureMap('route-me') : waitingRoute()),
      'POST /route/me/signals': (http.Request _) {
        conflict = true;
        return problem(409, 'Идёт перевод', detail: 'во время перевода просить другую больницу нельзя', stateCode: 'transfer_pending_consent');
      },
    });
    await pumpScreen(tester, session, const WaitScreen(regionKato: '75', profileCode: '121'), size: phoneTall);
    final readsBefore = backend.calls('GET', '/route/me').length;
    await scrollTo(tester, requestButton('031N'));
    await tester.tap(requestButton('031N'));
    await pumpFrames(tester);
    await tester.tap(find.byKey(const ValueKey('send-request')));
    await pumpFrames(tester);
    expect(backend.calls('GET', '/route/me').length, greaterThan(readsBefore));
    expect(find.text('Идёт перевод — во время перевода просить другую больницу нельзя'), findsOneWidget);
    expect(find.text('Попросить рассмотреть'), findsNothing);
  });

  testWidgets('«Как считается»: place in the toggle, the index sentence and the NHS example', (tester) async {
    final (session, _) = await demoSession(DemoUser.citizen1, api: api());
    await pumpScreen(tester, session, const WaitScreen(regionKato: '75', profileCode: '121'), size: phoneTall);
    final toggle = find.text('Как считается · место 7 из 19 регионов');
    await scrollTo(tester, toggle);
    await tester.tap(toggle);
    await pumpFrames(tester);
    expect(find.textContaining('Сроки ожидания рассчитывает компьютерная модель'), findsOneWidget);
    expect(find.text('Регион «г. Алматы» по этому профилю: индекс 51, 7-е место из 19. Больше 30 дней ждали 42 % пациентов; самые долгие 10 % пациентов ждали больше 98 дн.'),
        findsOneWidget);
    expect(find.textContaining('Для сравнения — как обычно меняется очередь по сезонам в Англии (данные NHS):'), findsOneWidget);
    expect(find.textContaining('Это пример из другой страны, а не прогноз по Казахстану.'), findsOneWidget);
  });

  testWidgets('another region or profile from the pickers re-runs the estimate; the request is not offered there', (tester) async {
    final (session, backend) = await demoSession(DemoUser.citizen1, api: api());
    await pumpScreen(tester, session, const WaitScreen(regionKato: '75', profileCode: '121'), size: phoneTall);
    await tester.tap(find.text('г. Алматы'));
    await pumpFrames(tester);
    await tester.tap(find.text('г. Астана'));
    await pumpFrames(tester);
    expect(backend.lastBody('POST', '/queue/predict'), {'regionKato': '71', 'profileCode': '121'});
    expect(session.region, '75', reason: 'выбор на экране справки не меняет регион сессии');
    await scrollTo(tester, find.text('031N'));
    expect(find.text('Попросить рассмотреть'), findsNothing);

    await tester.scrollUntilVisible(find.text('Хирургические для взрослых'), -200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Хирургические для взрослых'));
    await pumpFrames(tester);
    await tester.tap(find.text('Терапевтические'));
    await pumpFrames(tester);
    expect(backend.lastBody('POST', '/queue/predict'), {'regionKato': '71', 'profileCode': '021'});
    expect(find.text('Дневной стационар'), findsNothing, reason: 'дневной стационар в выборе профиля не показывается');
  });

  testWidgets('the reference lists failing show the error box; nothing chosen shows the web empty state', (tester) async {
    final (session, backend) = await demoSession(DemoUser.citizen1, api: {
      ...api(route: problem(404, 'Нет очередей в регионе')),
      '/refdata/regions': problem(503, 'Unavailable'),
    });
    await pumpScreen(tester, session, const WaitScreen(regionKato: '75'), size: phoneTall);
    expect(find.text('Сервер недоступен. Повторите попытку позже.'), findsOneWidget);
    expect(find.text('Выберите регион и профиль койки'), findsOneWidget, reason: 'маршрута нет — профиль не подставляется');
    expect(find.text('Прогноз ожидания считается по региону и профилю; личных данных не нужно.'), findsOneWidget);
    expect(backend.calls('POST', '/queue/predict'), isEmpty);
  });

  testWidgets('the neighbours switch asks for neighbouring regions', (tester) async {
    final (session, backend) = await demoSession(DemoUser.citizen1, api: api());
    await pumpScreen(tester, session, const WaitScreen(regionKato: '75', profileCode: '121'), size: phoneTall);
    await tester.tap(find.text('Показать и соседние регионы'));
    await pumpFrames(tester);
    expect(backend.lastBody('POST', '/queue/alternatives')['includeNeighbors'], isTrue);
  });

  testWidgets('no data for the profile: change-profile state; no hospitals: the web empty texts', (tester) async {
    final (session, _) = await demoSession(DemoUser.citizen1, api: api(predictReply: problem(404, 'Нет данных')));
    await pumpScreen(tester, session, const WaitScreen(regionKato: '75', profileCode: '121'), size: phoneTall);
    expect(find.text('Нет данных по этому профилю'), findsOneWidget);
    expect(find.text('По этому профилю в регионе нет данных, попробуйте другой профиль.'), findsOneWidget);
    expect(find.text('Сменить профиль'), findsOneWidget);

    await tester.pumpWidget(const SizedBox()); // новый экран, а не прежнее состояние
    final (empty, _) = await demoSession(DemoUser.citizen1, api: api(alternativesReply: const {'items': <Object?>[]}));
    await pumpScreen(tester, empty, const WaitScreen(regionKato: '75', profileCode: '121'), size: phoneTall);
    await scrollTo(tester, find.text('Данных об организациях с этим профилем нет.'));
    expect(find.text('По этому профилю в регионе нет данных, попробуйте другой профиль.'), findsOneWidget);
  });

  testWidgets('without a chosen profile the screen opens with the profile of the own route', (tester) async {
    final (session, backend) = await demoSession(DemoUser.citizen1, api: api());
    await pumpScreen(tester, session, const WaitScreen(), size: phoneTall);
    expect(backend.lastBody('POST', '/queue/predict'), {'regionKato': '75', 'profileCode': '121'});
    expect(find.text('Хирургические для взрослых'), findsOneWidget);
  });

  testWidgets('a server failure shows the error box with retry, no raw exception text', (tester) async {
    final (session, _) = await demoSession(DemoUser.citizen1, api: api(predictReply: (http.Request _) => throw http.ClientException('timeout')));
    await pumpScreen(tester, session, const WaitScreen(regionKato: '75', profileCode: '121'), size: phoneTall);
    expect(find.text('Сервер недоступен. Повторите попытку позже.'), findsOneWidget);
    expect(find.text('Повторить'), findsOneWidget);
    expect(find.textContaining('timeout'), findsNothing);
  });

  testWidgets('kazakh at text scale 1.3 on a 360 dp phone: web texts in Kazakh, no overflow', (tester) async {
    final (session, _) = await demoSession(DemoUser.citizen1, locale: 'kk', api: api());
    await pumpScreen(tester, session, const WaitScreen(regionKato: '75', profileCode: '121'), locale: 'kk', textScale: 1.3, size: phoneNarrow);
    expect(find.text('Өңірдегі пациенттердің жартысы емдеуге жатқызуды бұдан ұзақ күтпейді'), findsOneWidget);
    expect(find.text('Көрші өңірлерді де көрсету'), findsOneWidget);
    await scrollTo(tester, requestButton('031N'));
    expect(find.text('орташадан 16 күн жылдам'), findsOneWidget);
    expect(find.text('Қарауды сұрау'), findsWidgets);
    await scrollTo(tester, find.text('Қалай есептеледі · 19 өңірдің ішінде 7-орын'));
    expect(tester.takeException(), isNull);
  });
}
