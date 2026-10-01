import 'dart:convert';
import 'dart:io';

import 'package:darumen/api/models.dart';
import 'package:darumen/theme/app_theme.dart';
import 'package:darumen/theme/tokens.dart';
import 'package:darumen/theme/tones.dart';
import 'package:darumen/widgets/route/checklist_groups.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Анализы по Стандарту (RouteChecklist.vue): три группы в порядке «истёк → скоро истекут → действуют», каждая —
/// блок с цветной полосой слева, тонированной шапкой (значок, заголовок, пояснение, «анализов: N») и строками
/// «название / действителен … после сдачи / истёк … | действует до …»; внизу — источник перечня.
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
final tones = AppTones.from(c);

/// Чек-лист и ссылка на Стандарт из настоящего `GET /route/me` (7 истёкших, 3 действующих) и один «скоро истечёт».
({List<ChecklistItem> items, RouteStandardRef standard}) fixture() {
  final json = jsonDecode(File('test/fixtures/api/route-me.json').readAsStringSync()) as Map<String, dynamic>;
  final route = PatientRoute.fromJson(json);
  const expiring = ChecklistItem(
    code: 'xray',
    title: 'Рентгенография органов грудной клетки',
    validityDays: 30,
    validityLabel: '1 месяц',
    doneAt: '2026-09-10',
    validUntil: '2026-10-10',
    status: 'expiring',
  );
  return (items: [...route.checklist, expiring], standard: route.standard);
}

void main() {
  group('groupChecklist', () {
    test('порядок групп — истёк, скоро истекут, действуют; пустые группы пропускаются; вход не меняется', () {
      final items = fixture().items;
      final before = [for (final i in items) i.code];
      final groups = groupChecklist(items);
      expect([for (final g in groups) g.status], ['expired', 'expiring', 'valid']);
      expect([for (final g in groups) g.items.length], [7, 1, 3]);
      expect([for (final i in items) i.code], before);
      final onlyValid = groupChecklist([for (final i in items) if (i.status == 'valid') i]);
      expect([for (final g in onlyValid) g.status], ['valid']);
      expect(groupChecklist(const []), isEmpty);
    });

    test('пункт с незнакомым статусом в группы не попадает — как в вебе', () {
      const odd = ChecklistItem(code: 'x', title: 'X', validityDays: 1, validityLabel: '1 день', doneAt: '', validUntil: '', status: 'unknown');
      expect(groupChecklist(const [odd]), isEmpty);
    });
  });

  group('ChecklistGroups', () {
    testWidgets('шапки групп с пояснением и счётчиком, пункты с фразой срока и датой, сноска с источником', (tester) async {
      final data = fixture();
      await tester.pumpWidget(host(ChecklistGroups(items: data.items, standard: data.standard)));
      final expired = tester.getTopLeft(find.text('Срок действия истёк')).dy;
      final expiring = tester.getTopLeft(find.text('Скоро истекут')).dy;
      final valid = tester.getTopLeft(find.text('Действуют')).dy;
      expect(expired < expiring && expiring < valid, isTrue);
      expect(find.text('Эти анализы нужно сдать заново до госпитализации.'), findsOneWidget);
      expect(find.text('анализов: 7'), findsOneWidget);
      expect(find.text('анализов: 3'), findsOneWidget);
      expect(find.text('Общий анализ крови'), findsOneWidget);
      expect(find.text('действителен 14 дней после сдачи'), findsNWidgets(6));
      expect(find.text('истёк 20.02.2025'), findsOneWidget);
      expect(find.text('действует до 10.10.2026'), findsOneWidget);
      expect(find.text('действует до 08.02.2026'), findsOneWidget);
      expect(tester.widget<Text>(find.text('истёк 20.02.2025')).style?.color, tones.danger.fg);
      expect(tester.widget<Text>(find.text('Срок действия истёк')).style?.color, tones.danger.fg);
      expect(find.textContaining('Перечень и сроки действия — Стандарт организации'), findsOneWidget);
      expect(find.textContaining('(15.09.2025); это логистика документов'), findsOneWidget);
    });

    testWidgets('полоса слева и шапка окрашены по группе: danger / warnStrong / ok', (tester) async {
      final data = fixture();
      await tester.pumpWidget(host(ChecklistGroups(items: data.items, standard: data.standard)));
      Color? bar(String status) => tester.widget<ColoredBox>(find.byKey(ValueKey('checklist-bar-$status'))).color;
      Color? head(String status) => (tester.widget<Container>(find.byKey(ValueKey('checklist-head-$status'))).decoration! as BoxDecoration).color;
      expect(bar('expired'), tones.danger.fg);
      expect(bar('expiring'), c.warnStrong);
      expect(bar('valid'), tones.ok.fg);
      expect(head('expired'), tones.danger.bg);
      expect(head('expiring'), tones.warn.bg);
      expect(head('valid'), tones.ok.bg);
    });

    testWidgets('без ссылки на Стандарт — без сноски; пустой список — «Данных нет»', (tester) async {
      await tester.pumpWidget(host(ChecklistGroups(items: fixture().items)));
      expect(find.textContaining('Перечень и сроки действия'), findsNothing);
      await tester.pumpWidget(host(const ChecklistGroups(items: [])));
      expect(find.text('Данных нет'), findsOneWidget);
    });

    for (final locale in ['ru', 'kk']) {
      testWidgets('без переполнения на 360 dp при крупном шрифте 1.3 ($locale)', (tester) async {
        final data = fixture();
        await tester.pumpWidget(host(ChecklistGroups(items: data.items, standard: data.standard), locale: locale, textScale: 1.3));
        expect(tester.takeException(), isNull);
      });
    }
  });
}
