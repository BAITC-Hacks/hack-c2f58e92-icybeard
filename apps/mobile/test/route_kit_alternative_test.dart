import 'dart:convert';
import 'dart:io';

import 'package:darumen/api/models.dart';
import 'package:darumen/l10n/strings.dart';
import 'package:darumen/theme/app_theme.dart';
import 'package:darumen/theme/tokens.dart';
import 'package:darumen/theme/tones.dart';
import 'package:darumen/widgets/route/alternative_tile.dart';
import 'package:darumen/widgets/status_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Плитка «Где быстрее» гражданина (RouteAlternatives.vue): имя и код больницы, «сосед: регион», справа «половина
/// пациентов ждёт не больше», «≈ N дн.» (зелёным только когда быстрее) и сравнение в трёх вариантах по округлённым
/// дням; под ними — действие экрана или чип «запрос отправлен».
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
final ru = S.of('ru');

/// Альтернативы и прогноз своей больницы из настоящего `GET /route/me`: своя p50 ≈ 1.5, альтернативы 2.3 / 3.7 / 6.4.
({List<Alternative> alternatives, double baseline}) fixture() {
  final json = jsonDecode(File('test/fixtures/api/route-me.json').readAsStringSync()) as Map<String, dynamic>;
  final route = PatientRoute.fromJson(json);
  return (alternatives: route.alternatives, baseline: route.forecast.p50Days);
}

const neighbour = Alternative(
  moCode: '22GN',
  name: 'Товарищество с ограниченной ответственностью "Достар Мед"',
  p50Days: 2.2,
  p90Days: 9,
  pRefusal: 0.1,
  distanceKm: 40,
  isNeighborRegion: true,
);

void main() {
  group('сравнение по округлённым дням', () {
    test('разница — округлённая своя минус округлённая чужая: ≈ 4 и ≈ 2 → на 2 дн.', () {
      expect(alternativeDayDifference(baselineDays: 4.4, p50Days: 2.28), 2);
      expect(alternativeDayDifference(baselineDays: 1.5, p50Days: 2.28), 0, reason: '1.5 → 2, 2.28 → 2');
      expect(alternativeDayDifference(baselineDays: 2, p50Days: 3.65), -2);
      expect(alternativeDayDifference(baselineDays: null, p50Days: 3.65), isNull);
      expect(alternativeDayDifference(baselineDays: double.nan, p50Days: 3.65), isNull);
    });

    test('фраза сравнения: меньше, больше или «как в вашей больнице»; без своей медианы — нет фразы', () {
      expect(alternativeCompareText(ru, 2), 'на 2 дн. меньше, чем в вашей больнице');
      expect(alternativeCompareText(ru, -3), 'на 3 дн. больше, чем в вашей больнице');
      expect(alternativeCompareText(ru, 0), 'как в вашей больнице');
      expect(alternativeCompareText(S.of('kk'), 2), 'сіздің ауруханаңыздан 2 күн аз');
      expect(alternativeCompareText(ru, null), isNull);
    });
  });

  group('AlternativeTile', () {
    testWidgets('быстрее: число и единица зелёные, сравнение серое, код и действие под именем', (tester) async {
      await tester.pumpWidget(host(AlternativeTile(
        alternative: neighbour,
        baselineDays: 4.4,
        neighbourRegion: 'Алматинская область',
        action: TextButton(onPressed: () {}, child: Text(ru.routeRequestConsider)),
      )));
      expect(find.text('Достар Мед'), findsOneWidget);
      expect(find.text('22GN · сосед: Алматинская область'), findsOneWidget);
      expect(find.text('половина пациентов ждёт не больше'), findsOneWidget);
      expect(tester.widget<Text>(find.text('≈ 2')).style?.color, tones.ok.fg);
      expect(tester.widget<Text>(find.text('дн.')).style?.color, c.okSoftText);
      final compare = tester.widget<Text>(find.text('на 2 дн. меньше, чем в вашей больнице'));
      expect(compare.style?.color, c.muted);
      expect(find.text('Попросить рассмотреть'), findsOneWidget);
      expect(find.byType(StatusChip), findsNothing);
    });

    testWidgets('не быстрее: число обычного цвета; без своей медианы — без сравнения', (tester) async {
      final data = fixture();
      await tester.pumpWidget(host(Column(children: [
        AlternativeTile(alternative: data.alternatives[1], baselineDays: data.baseline),
        AlternativeTile(alternative: data.alternatives[0], baselineDays: data.baseline),
        AlternativeTile(alternative: data.alternatives[2]),
      ])));
      expect(find.text('≈ 4'), findsOneWidget);
      expect(tester.widget<Text>(find.text('≈ 4')).style?.color, isNot(tones.ok.fg));
      expect(find.text('на 2 дн. больше, чем в вашей больнице'), findsOneWidget);
      expect(find.text('как в вашей больнице'), findsOneWidget);
      expect(find.text('≈ 6'), findsOneWidget);
      expect(find.textContaining('вашей больнице'), findsNWidgets(2));
      expect(find.text('031N'), findsOneWidget, reason: 'не соседний регион — только код');
    });

    testWidgets('открытая просьба — чип «запрос отправлен» (accent) вместо действия', (tester) async {
      await tester.pumpWidget(host(AlternativeTile(
        alternative: neighbour,
        baselineDays: 4.4,
        requested: true,
        action: TextButton(onPressed: () {}, child: Text(ru.routeRequestConsider)),
      )));
      final chip = tester.widget<StatusChip>(find.byType(StatusChip));
      expect(chip.label, ru.routeRequestSent);
      expect(chip.tone, StatusTone.accent);
      expect(find.text('Попросить рассмотреть'), findsNothing);
      expect(find.textContaining('сосед'), findsNothing, reason: 'без названия региона подпись соседа не выводится');
    });

    testWidgets('тап по сокращённому имени открывает полное юридическое имя', (tester) async {
      await tester.pumpWidget(host(const AlternativeTile(alternative: neighbour)));
      await tester.tap(find.text('Достар Мед'));
      await tester.pumpAndSettle();
      expect(find.text(neighbour.name), findsOneWidget);
    });

    for (final locale in ['ru', 'kk']) {
      testWidgets('без переполнения на 360 dp при крупном шрифте 1.3 ($locale)', (tester) async {
        final dict = S.of(locale);
        final data = fixture();
        const slow = Alternative(
          moCode: '031N',
          name: 'Государственное учреждение "Региональный военный госпиталь с поликлиникой Комитета национальной безопасности Республики Казахстан в городе Алматы"',
          p50Days: 128.4,
          p90Days: 300,
          pRefusal: 0.5,
          distanceKm: 0,
          isNeighborRegion: true,
        );
        await tester.pumpWidget(host(
          Column(children: [
            for (final a in [...data.alternatives, slow])
              AlternativeTile(
                alternative: a,
                baselineDays: data.baseline,
                neighbourRegion: 'Северо-Казахстанская область',
                action: TextButton(onPressed: () {}, child: Text(dict.routeRequestConsider)),
              ),
            AlternativeTile(alternative: slow, baselineDays: 2, requested: true),
          ]),
          locale: locale,
          textScale: 1.3,
        ));
        expect(tester.takeException(), isNull);
      });
    }
  });
}
