import 'dart:convert';
import 'dart:io';

import 'package:darumen/api/models.dart';
import 'package:darumen/theme/app_theme.dart';
import 'package:darumen/theme/tokens.dart';
import 'package:darumen/widgets/route/stage_list.dart';
import 'package:darumen/widgets/route/stage_node.dart';
import 'package:darumen/widgets/route/stage_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Этапы маршрута (RouteTimeline.vue, вариант citizen): узел трёх состояний, полоска только из узлов для карточки
/// главной и вертикальный список с заголовками сервера, датой дд.мм.гггг или нормой — включая этап «Перевод».
Widget host(Widget child, {String locale = 'ru', double textScale = 1.0}) => MaterialApp(
      theme: AppTheme.light(),
      locale: Locale(locale),
      supportedLocales: const [Locale('ru'), Locale('kk')],
      localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale), size: const Size(360, 800)),
        child: Scaffold(body: Center(child: SizedBox(width: 296, child: SingleChildScrollView(child: child)))),
      ),
    );

const c = ColorTokens.light;

/// Таймлайн настоящего `GET /route/me` с переводом, ждущим согласия: шесть этапов, «Перевод» — текущий.
List<RouteStage> fixtureTimeline() {
  final json = jsonDecode(File('test/fixtures/api/route-me.json').readAsStringSync()) as Map<String, dynamic>;
  return PatientRoute.fromJson(json).timeline;
}

const kkStages = [
  RouteStage(code: 'referral_issued', order: 1, title: 'Жолдама берілді', date: '2025-02-03', status: 'done', norm: 'МСАК ұйымы жоспарлы емдеуге жатқызуға жолдама береді: мемлекеттік қызмет, 1 жұмыс күні'),
  RouteStage(code: 'examination', order: 2, title: 'Тексеру', date: '2025-02-10', status: 'done'),
  RouteStage(code: 'waitlisted', order: 3, title: 'Күту парағына енгізілді', date: '2025-02-10', status: 'done'),
  RouteStage(code: 'transfer', order: 4, title: 'Ауыстыру', date: '2026-09-22', status: 'current'),
  RouteStage(
    code: 'date_assigned',
    order: 5,
    title: 'Емдеуге жатқызу күні белгіленді',
    status: 'upcoming',
    norm: 'Жоспарлы күн тіркелгеннен кейін 2 жұмыс күні ішінде белгіленеді; пациенттің өтініші бойынша ауыстыру — 2 күнтізбелік күннен аспайды',
  ),
  RouteStage(code: 'hospitalized', order: 6, title: 'Емдеуге жатқызу', status: 'upcoming', norm: 'Белгіленген күні стационардың қабылдау бөлімі арқылы қабылдау'),
];

BoxDecoration nodeDecoration(WidgetTester tester, Finder node) =>
    tester.widget<Container>(find.descendant(of: node, matching: find.byType(Container)).first).decoration! as BoxDecoration;

void main() {
  group('порядок и прогресс', () {
    test('этапы упорядочиваются по order в новом списке, вход не меняется', () {
      const shuffled = [
        RouteStage(code: 'hospitalized', order: 3, title: 'Госпитализация', status: 'upcoming'),
        RouteStage(code: 'referral_issued', order: 1, title: 'Направление выдано', status: 'done'),
        RouteStage(code: 'waitlisted', order: 2, title: 'Внесено в лист ожидания', status: 'current'),
      ];
      final input = [...shuffled];
      expect([for (final s in orderedStages(input)) s.order], [1, 2, 3]);
      expect([for (final s in input) s.order], [3, 1, 2]);
    });

    test('прогресс доходит до текущего этапа; все пройдены — до последнего; ничего не начато — 0', () {
      final timeline = fixtureTimeline();
      expect(stageProgressIndex(timeline), 3, reason: '«Перевод» — четвёртый из шести');
      const allDone = [
        RouteStage(code: 'a', order: 1, title: 'A', status: 'done'),
        RouteStage(code: 'b', order: 2, title: 'B', status: 'done'),
      ];
      expect(stageProgressIndex(allDone), 1);
      const nothing = [
        RouteStage(code: 'a', order: 1, title: 'A', status: 'upcoming'),
        RouteStage(code: 'b', order: 2, title: 'B', status: 'upcoming'),
      ];
      expect(stageProgressIndex(nothing), 0);
      expect(stageProgressIndex(const []), 0);
    });
  });

  group('StageNode', () {
    testWidgets('пройден — accent с галочкой, текущий — accent-soft с рамкой и точкой, впереди — пустой с рамкой toggle-off', (tester) async {
      await tester.pumpWidget(host(const Row(children: [
        StageNode(key: Key('done'), status: 'done'),
        StageNode(key: Key('current'), status: 'current'),
        StageNode(key: Key('upcoming'), status: 'upcoming'),
        StageNode(key: Key('odd'), status: 'skipped'),
      ])));
      final done = nodeDecoration(tester, find.byKey(const Key('done')));
      expect(done.color, c.accent);
      expect(find.descendant(of: find.byKey(const Key('done')), matching: find.byIcon(Icons.check)), findsOneWidget);
      final current = nodeDecoration(tester, find.byKey(const Key('current')));
      expect(current.color, c.accentSoft);
      expect((current.border! as Border).top.color, c.accent);
      expect(find.descendant(of: find.byKey(const Key('current')), matching: find.byIcon(Icons.check)), findsNothing);
      final upcoming = nodeDecoration(tester, find.byKey(const Key('upcoming')));
      expect(upcoming.color, c.card);
      expect((upcoming.border! as Border).top.color, c.toggleOff);
      expect(nodeDecoration(tester, find.byKey(const Key('odd'))).color, c.card, reason: 'незнакомый статус — как будущий');
      expect(tester.getSize(find.byKey(const Key('done'))), const Size.square(AppSizes.stageNode));
    });
  });

  group('StageStrip', () {
    testWidgets('только узлы: шесть этапов с «Переводом», без подписей, линия до текущего узла — accent', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(host(StageStrip(stages: fixtureTimeline())));
      expect(find.byType(StageNode), findsNWidgets(6));
      expect(find.byType(Text), findsNothing);
      expect(find.bySemanticsLabel('Этап 4 из 6: Перевод'), findsOneWidget);
      final segments = tester.widgetList<StageConnector>(find.byType(StageConnector)).toList();
      expect(segments, hasLength(5));
      expect([for (final s in segments) s.reached], [true, true, true, false, false]);
      semantics.dispose();
    });

    testWidgets('без текущего этапа подпись — «N этапов · M пройдено»; пустой список — ничего', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(host(const StageStrip(stages: [
        RouteStage(code: 'referral_issued', order: 1, title: 'Направление выдано', status: 'done'),
        RouteStage(code: 'hospitalized', order: 2, title: 'Госпитализация', status: 'done'),
      ])));
      expect(find.bySemanticsLabel('2 этапов · 2 пройдено'), findsOneWidget);
      await tester.pumpWidget(host(const StageStrip(stages: [])));
      expect(find.byType(StageNode), findsNothing);
      semantics.dispose();
    });
  });

  group('StageList', () {
    testWidgets('заголовки сервера, дата дд.мм.гггг у пройденных и «Перевода», норма у будущих', (tester) async {
      final timeline = fixtureTimeline();
      await tester.pumpWidget(host(StageList(stages: timeline)));
      expect(find.text('Внесено в лист ожидания'), findsOneWidget, reason: 'заголовок сервера, а не мобильное «Лист ожидания»');
      expect(find.text('Перевод'), findsOneWidget);
      expect(find.text('22.09.2026'), findsOneWidget, reason: 'дата этапа «Перевод»');
      expect(find.text('03.02.2025'), findsOneWidget);
      expect(find.text(timeline[4].norm!), findsOneWidget);
      expect(find.byType(StageNode), findsNWidgets(6));
      expect(tester.widget<Text>(find.text('Перевод')).style?.color, c.accentHover, reason: 'текущий этап — accent-strong');
      expect(tester.widget<Text>(find.text('Госпитализация')).style?.color, c.muted, reason: 'будущий — text-secondary, не text-faint');
      final segments = tester.widgetList<StageConnector>(find.byType(StageConnector)).toList();
      expect([for (final s in segments) s.reached], [true, true, true, false, false]);
    });

    testWidgets('будущий этап без нормы и без даты — без подстроки; пустой список — ничего', (tester) async {
      await tester.pumpWidget(host(const StageList(stages: [
        RouteStage(code: 'waitlisted', order: 1, title: 'Внесено в лист ожидания', date: '2025-02-10', status: 'current'),
        RouteStage(code: 'hospitalized', order: 2, title: 'Госпитализация', status: 'upcoming'),
      ])));
      expect(find.text('10.02.2025'), findsOneWidget);
      expect(find.text('—'), findsNothing);
      expect(find.byType(Text), findsNWidgets(3));
      await tester.pumpWidget(host(const StageList(stages: [])));
      expect(find.byType(StageNode), findsNothing);
    });

    testWidgets('строки озвучиваются как «Этап k из n: заголовок»', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(host(StageList(stages: fixtureTimeline())));
      expect(find.bySemanticsLabel(RegExp(r'^Этап 4 из 6: Перевод')), findsOneWidget);
      semantics.dispose();
    });

    for (final (locale, stages) in [('ru', fixtureTimeline()), ('kk', kkStages)]) {
      testWidgets('без переполнения на 360 dp при крупном шрифте 1.3 ($locale)', (tester) async {
        await tester.pumpWidget(host(Column(children: [StageStrip(stages: stages), StageList(stages: stages)]), locale: locale, textScale: 1.3));
        expect(tester.takeException(), isNull);
      });
    }
  });
}
