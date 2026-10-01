import 'package:darumen/screens/vaccination_screen.dart';
import 'package:darumen/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/harness.dart';

/// «Вакцинация» (§5, решение Q13 — экран остаётся, у веба его нет): оценки WUENIC как внешний ориентир — чип
/// «ВОЗ/ЮНИСЕФ · год», без метки происхождения; источник — в тихой раскрывашке «Источник»; охват ниже 80 % —
/// янтарным; без литеральных размеров шрифта.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, Object?> estimate(String code, String ru, String kk, int year, double pct) => {
        'vaccine': code,
        'titleRu': ru,
        'titleKk': kk,
        'year': year,
        'coveragePct': pct,
        'source': 'WHO GHO OData API, индикаторы WUENIC (ВОЗ/ЮНИСЕФ), страна KAZ',
        'note': 'Оценки WUENIC ниже административной отчётности Казахстана.',
      };

  final vaccination = {
    'items': [
      estimate('BCG', 'БЦЖ', 'БЦЖ', 2019, 81),
      estimate('BCG', 'БЦЖ', 'БЦЖ', 2021, 86),
      estimate('BCG', 'БЦЖ', 'БЦЖ', 2020, 86),
      estimate('MCV1', 'Корь, 1-я доза', 'Қызылша, 1-доза', 2021, 76),
      estimate('DTP3', 'АКДС-3', 'АКДС-3', 2021, 92),
    ],
  };

  testWidgets('hero of the first vaccine with the bench chip and the trend; others below; low coverage in amber', (tester) async {
    final (session, _) = await demoSession(DemoUser.citizen1, api: {'/refdata/vaccination': vaccination});
    await pumpScreen(tester, session, const VaccinationScreen(), size: phoneTall);
    expect(find.text('Вакцинация'), findsOneWidget);
    expect(find.text('ОХВАТ · КАЗАХСТАН'), findsOneWidget);
    expect(find.text('ВОЗ/ЮНИСЕФ · 2021'), findsOneWidget);
    expect(find.text('86 %'), findsOneWidget);
    expect(find.text('БЦЖ, 2021'), findsOneWidget);
    expect(find.text('2019 · 81 % → 2020 · 86 % → 2021 · 86 %'), findsOneWidget);
    expect(find.text('Корь, 1-я доза'), findsOneWidget);
    expect(find.text('76 %'), findsOneWidget);
    final low = tester.widget<Text>(find.text('76 %'));
    expect(low.style?.color, ColorTokens.light.warn);
    expect(low.style?.fontSize, isNot(17), reason: 'размер — из темы, не литерал');
    expect(find.text('прогноз модели'), findsNothing, reason: 'внешний ориентир — не метка происхождения');
  });

  testWidgets('the source is behind a quiet «Источник» toggle', (tester) async {
    final (session, _) = await demoSession(DemoUser.citizen1, api: {'/refdata/vaccination': vaccination});
    await pumpScreen(tester, session, const VaccinationScreen(), size: phoneTall);
    expect(find.textContaining('WHO GHO OData API'), findsNothing);
    await tester.tap(find.text('Источник'));
    await pumpFrames(tester);
    expect(find.text('Источник: WHO GHO OData API, индикаторы WUENIC (ВОЗ/ЮНИСЕФ), страна KAZ'), findsOneWidget);
    expect(find.text('Оценки WUENIC ниже административной отчётности Казахстана.'), findsOneWidget);
  });

  testWidgets('empty list and load error with retry', (tester) async {
    var reply = json(const {'items': <Object?>[]});
    final (session, _) = await demoSession(DemoUser.citizen1, api: {'/refdata/vaccination': (http.Request _) => reply});
    await pumpScreen(tester, session, const VaccinationScreen(), size: phoneTall);
    expect(find.text('Нет данных по вакцинам'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    reply = problem(500, 'Ошибка');
    await pumpScreen(tester, session, const VaccinationScreen(), size: phoneTall);
    expect(find.text('Не удалось загрузить данные'), findsOneWidget);
    reply = json(vaccination);
    await tester.tap(find.text('Повторить'));
    await pumpFrames(tester);
    expect(find.text('86 %'), findsOneWidget);
  });

  testWidgets('kazakh at text scale 1.3 on a 360 dp phone: Kazakh titles, no overflow', (tester) async {
    final (session, _) = await demoSession(DemoUser.citizen1, locale: 'kk', api: {'/refdata/vaccination': vaccination});
    await pumpScreen(tester, session, const VaccinationScreen(), locale: 'kk', textScale: 1.3, size: phoneNarrow);
    expect(find.text('ҚАМТУ · ҚАЗАҚСТАН'), findsOneWidget);
    expect(find.text('Қызылша, 1-доза'), findsOneWidget);
    await tester.tap(find.text('Дереккөз'));
    await pumpFrames(tester);
    expect(tester.takeException(), isNull);
  });
}
