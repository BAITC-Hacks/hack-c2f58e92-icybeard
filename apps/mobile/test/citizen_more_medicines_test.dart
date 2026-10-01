import 'dart:convert';

import 'package:darumen/screens/medicines_screen.dart';
import 'package:darumen/widgets/status_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/harness.dart';

/// «Проверка рецепта» (§4, веб `MedicinesView.vue`): чип «покрыт / не покрыт программой» (не покрыт — янтарный),
/// фактическая медиана отдельно от модельной оценки со своей меткой, дефицит словами с долей похожих МНН, «Как
/// считается» вместо строки модели, «Другие МНН при этой нозологии».
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const nosologies = {
    'items': [
      {'nosologyId': '9', 'categoryId': '63', 'issued12m': 120000, 'fulfilled12m': 100000, 'mnnCount': 4},
    ],
  };
  const mnns = {
    'items': [
      {'mnnId': '1201', 'nosologyId': '9', 'categoryId': '63', 'issued12m': 50000, 'fulfilled12m': 40000, 'fillDaysP50': 4},
      {'mnnId': '1203', 'nosologyId': '9', 'categoryId': '63', 'issued12m': 15234, 'fulfilled12m': 12000, 'fillDaysP50': 6},
    ],
  };

  Map<String, Object?> check({bool covered = true, double? model, bool shortage = false, double? peer = 0.93}) => {
        'covered': covered,
        'program': covered ? 'ГОБМП' : null,
        'category': '63',
        'fillDaysP50': 4.2,
        'fillDaysP90': 11.0,
        'fillDaysP50Model': model,
        'pFilled14d': 0.87,
        'shortage': {'flag': shortage, 'score': 2.4, 'basis': 'доля обеспеченных за 4 недели против предыдущих 12.', 'peerRatio': peer, 'peerBasis': null},
        'pharmacies': <Object?>[],
        'alternatives': [
          {'mnnId': '1203', 'name': 'МНН 1203', 'issued12m': 15234},
        ],
        'basis': 'медиана и 90-й перцентиль по рецептам за 12 месяцев',
        'model': {'name': 'rx-fill', 'version': '1.0', 'trainedThrough': '2026-09-28'},
      };

  Map<String, Object?> api({Object? checkReply}) => {
        '/medicines/nosologies': nosologies,
        '/medicines/mnn': mnns,
        'POST /medicines/check': checkReply ?? check(),
      };

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).first);
    await tester.pump();
  }

  StatusChip chip(WidgetTester tester, String label) => tester.widget<StatusChip>(find.widgetWithText(StatusChip, label));

  testWidgets('covered МНН: web wording, factual median, rule tag, no model line; the first МНН is checked at once', (tester) async {
    final (session, backend) = await demoSession(DemoUser.citizen1, api: api());
    await pumpScreen(tester, session, const MedicinesScreen(), size: phoneTall);

    expect(find.text('Проверка рецепта'), findsOneWidget);
    expect(find.text('Покрыт ли препарат программой, за сколько дней его обычно получают и нет ли признаков дефицита.'), findsOneWidget);
    expect(jsonDecode(backend.calls('POST', '/medicines/check').single.body), {'mnnId': '1201', 'nosologyId': '9', 'regionKato': '75'});
    expect(find.text('МНН 1201'), findsWidgets);
    expect(chip(tester, 'Покрыт программой').tone, StatusTone.ok);
    expect(find.text('расчёт по правилу'), findsOneWidget);
    expect(find.text('Покрыт программой ГОБМП · категория 63 · нозология 9'), findsOneWidget);
    expect(find.text('Медиана получения'), findsOneWidget);
    expect(find.text('4 дн.'), findsOneWidget);
    expect(find.text('9 из 10 получают'), findsOneWidget);
    expect(find.text('до 11 дн.'), findsOneWidget);
    expect(find.text('Получают за 14 дней'), findsOneWidget);
    expect(find.text('87 %'), findsOneWidget);
    expect(find.text('Похожие МНН обеспечены 93 %'), findsOneWidget);
    expect(chip(tester, 'Без признаков дефицита').tone, StatusTone.ok);
    expect(find.text('Модельная оценка p50'), findsNothing);
    expect(find.textContaining('rx-fill'), findsNothing, reason: 'строки с названием и версией модели нет (X7)');
    expect(find.textContaining('балл'), findsNothing, reason: 'веб не показывает балл дефицита');

    await scrollTo(tester, find.text('Как считается'));
    await tester.tap(find.text('Как считается'));
    await pumpFrames(tester);
    expect(find.textContaining('(данные по 28.09.2026)'), findsOneWidget);
    expect(find.text('• Сроки — медиана и 90-й перцентиль по рецептам за 12 месяцев.'), findsOneWidget);
    expect(find.text('• Дефицит — доля обеспеченных за 4 недели против предыдущих 12.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('not covered is amber; the model estimate is its own row with the model tag; shortage in red words', (tester) async {
    final (session, _) = await demoSession(DemoUser.citizen1, api: api(checkReply: check(covered: false, model: 3.4, shortage: true, peer: null)));
    await pumpScreen(tester, session, const MedicinesScreen(), size: phoneTall);
    expect(chip(tester, 'Не покрыт программой').tone, StatusTone.warn);
    expect(find.text('Не покрыт программой · категория 63 · нозология 9'), findsOneWidget);
    expect(find.text('прогноз модели'), findsNWidgets(2), reason: 'метка карточки и строки модельной оценки');
    expect(find.text('Модельная оценка p50'), findsOneWidget);
    expect(find.text('3 дн.'), findsOneWidget);
    expect(find.text('4 дн.'), findsOneWidget, reason: 'фактическая медиана остаётся фактом');
    expect(chip(tester, 'Признаки дефицита').tone, StatusTone.danger);
    expect(find.textContaining('Похожие МНН обеспечены'), findsNothing);
  });

  testWidgets('«Другие МНН при этой нозологии»: rows with the yearly volume, a tap checks that МНН', (tester) async {
    final (session, backend) = await demoSession(DemoUser.citizen1, api: api());
    await pumpScreen(tester, session, const MedicinesScreen(), size: phoneTall);
    await scrollTo(tester, find.text('ДРУГИЕ МНН ПРИ ЭТОЙ НОЗОЛОГИИ'));
    expect(find.text('Аптеки рядом появятся после справочника аптек с координатами.'), findsOneWidget);
    expect(find.textContaining('рецептов в год'), findsOneWidget);
    await tester.tap(find.text('МНН 1203').last);
    await pumpFrames(tester);
    expect(jsonDecode(backend.calls('POST', '/medicines/check').last.body)['mnnId'], '1203');
  });

  testWidgets('another nosology clears the result until an МНН is picked from the suggestions', (tester) async {
    final (session, backend) = await demoSession(DemoUser.citizen1, api: {
      ...api(),
      '/medicines/nosologies': {
        'items': [
          {'nosologyId': '9', 'issued12m': 120000},
          {'nosologyId': '12', 'issued12m': 5000},
        ],
      },
      '/medicines/mnn': (http.Request r) => json({
            'items': [
              if (r.url.queryParameters['nosologyId'] == '12') ...[
                {'mnnId': '3301', 'issued12m': 4000},
                {'mnnId': '3302', 'issued12m': 1000},
              ] else
                {'mnnId': '1201', 'issued12m': 50000},
            ],
          }),
    });
    await pumpScreen(tester, session, const MedicinesScreen(), size: phoneTall);
    await tester.tap(find.text('Нозология 9'));
    await pumpFrames(tester);
    await tester.tap(find.text('Нозология 12'));
    await pumpFrames(tester);
    expect(find.text('Выберите нозологию и МНН'), findsOneWidget);
    expect(backend.calls('POST', '/medicines/check'), hasLength(1), reason: 'новая нозология без выбора МНН не проверяется');

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '3302');
    await pumpFrames(tester);
    expect(find.text('МНН 3301'), findsNothing, reason: 'подсказки отфильтрованы по вводу');
    await tester.tap(find.text('МНН 3302'));
    await pumpFrames(tester);
    expect(jsonDecode(backend.calls('POST', '/medicines/check').last.body), {'mnnId': '3302', 'nosologyId': '12', 'regionKato': '75'});

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'нет такого');
    await pumpFrames(tester);
    expect(find.text('Ничего не найдено'), findsOneWidget);
  });

  testWidgets('the nosology list failing shows the error box with retry', (tester) async {
    final (session, _) = await demoSession(DemoUser.citizen1, api: {...api(), '/medicines/nosologies': problem(500, 'Ошибка')});
    await pumpScreen(tester, session, const MedicinesScreen(), size: phoneTall);
    expect(find.text('Сервер недоступен. Повторите попытку позже.'), findsOneWidget);
    expect(find.text('Повторить'), findsOneWidget);
  });

  testWidgets('a failed check: error box with retry, no raw text', (tester) async {
    var reply = problem(503, 'Unavailable');
    final (session, backend) = await demoSession(DemoUser.citizen1, api: api(checkReply: (http.Request _) => reply));
    await pumpScreen(tester, session, const MedicinesScreen(), size: phoneTall);
    expect(find.text('Сервер недоступен. Повторите попытку позже.'), findsOneWidget);
    reply = json(check());
    await tester.tap(find.text('Повторить'));
    await pumpFrames(tester);
    expect(find.text('Медиана получения'), findsOneWidget);
    expect(backend.calls('POST', '/medicines/check'), hasLength(2));
  });

  testWidgets('kazakh at text scale 1.3 on a 360 dp phone without overflow', (tester) async {
    final (session, _) = await demoSession(DemoUser.citizen1, locale: 'kk', api: api(checkReply: check(model: 3.4)));
    await pumpScreen(tester, session, const MedicinesScreen(), locale: 'kk', textScale: 1.3, size: phoneNarrow);
    expect(find.text('Бағдарламамен қамтылған'), findsOneWidget);
    expect(find.text('Алу медианасы'), findsOneWidget);
    await scrollTo(tester, find.text('Модельдік p50 бағасы'));
    await scrollTo(tester, find.text('Жақын дәріханалар координаталары бар анықтамалықтан кейін пайда болады.'));
    expect(tester.takeException(), isNull);
  });
}
