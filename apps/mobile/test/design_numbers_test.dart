import 'package:darumen/theme/app_theme.dart';
import 'package:darumen/theme/tokens.dart';
import 'package:darumen/widgets/hero_number.dart';
import 'package:darumen/widgets/kpi_tile.dart';
import 'package:darumen/widgets/origin_tag.dart';
import 'package:darumen/widgets/status_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child, {String locale = 'ru', double textScale = 1.0, double width = 360}) => MaterialApp(
      theme: AppTheme.light(),
      locale: Locale(locale),
      supportedLocales: const [Locale('ru'), Locale('kk')],
      localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale), size: Size(width, 800)),
        child: Scaffold(body: Center(child: SizedBox(width: width, child: SingleChildScrollView(child: child)))),
      ),
    );

// Формулировки героя гражданина — веб route.citizen.forecastLead / forecastNine / forecastWithin30 (citizen Q1).
const lead = 'Половина пациентов в этой очереди ждёт госпитализации не больше';
const sub = '9 из 10 пациентов ждут не больше 106 дн.\n54 % пациентов попадают в больницу в течение 30 дней.';

void main() {
  final c = ColorTokens.light;

  group('HeroNumber', () {
    testWidgets('citizen hero: the sentence first (600, 1.4), then the p50 number 40/800, then the p90 sub-line', (tester) async {
      await tester.pumpWidget(host(const HeroNumber(lead: lead, value: '≈ 47', unit: 'дн.', line: sub, origin: Origin.ml)));
      final leadText = tester.widget<Text>(find.text(lead));
      expect(leadText.style?.fontWeight, FontWeight.w600);
      expect(leadText.style?.height, 1.4);
      final number = tester.widget<Text>(find.text('≈ 47'));
      expect(number.style?.fontSize, 40);
      expect(number.style?.fontWeight, FontWeight.w800);
      final line = tester.widget<Text>(find.text(sub));
      expect(line.style?.fontSize, 13.5);
      expect(line.style?.height, 1.55);
      expect(line.style?.color, c.muted);
      final leadTop = tester.getTopLeft(find.text(lead)).dy;
      final numberTop = tester.getTopLeft(find.text('≈ 47')).dy;
      final lineTop = tester.getTopLeft(find.text(sub)).dy;
      expect(leadTop, lessThan(numberTop));
      expect(numberTop, lessThan(lineTop));
      expect(find.text('прогноз модели'), findsOneWidget, reason: 'без kicker метка встаёт в строку фразы');
      expect(tester.getTopLeft(find.text('прогноз модели')).dy, lessThan(numberTop));
    });

    testWidgets('compact hero uses the KPI size 22 and the unit is 14.5 text-secondary', (tester) async {
      await tester.pumpWidget(host(const HeroNumber(value: '≈ 9', unit: 'дн.', compact: true)));
      expect(tester.widget<Text>(find.text('≈ 9')).style?.fontSize, 22);
      final unit = tester.widget<Text>(find.text('дн.'));
      expect(unit.style?.fontSize, 14.5);
      expect(unit.style?.color, c.muted);
    });

    testWidgets('value and unit alone are the inline hero (former HeroNumberInline)', (tester) async {
      await tester.pumpWidget(host(const HeroNumber(value: 'до 106', unit: 'дн. до госпитализации')));
      expect(find.text('до 106'), findsOneWidget);
      expect(find.text('дн. до госпитализации'), findsOneWidget);
      expect(tester.getTopLeft(find.text('до 106')).dy, lessThan(tester.getBottomLeft(find.text('дн. до госпитализации')).dy), reason: 'одна строка по базовой линии');
    });

    testWidgets('kicker label keeps the origin chip on its right; caption under the number is 14.5', (tester) async {
      await tester.pumpWidget(host(const HeroNumber(label: 'Срок ожидания', origin: Origin.ml, value: '≈ 47', unit: 'дн.', caption: 'половина госпитализированных ждёт не дольше')));
      expect(find.text('СРОК ОЖИДАНИЯ'), findsOneWidget);
      expect(tester.getTopLeft(find.text('прогноз модели')).dy, lessThan(tester.getTopLeft(find.text('≈ 47')).dy));
      expect(tester.widget<Text>(find.text('половина госпитализированных ждёт не дольше')).style?.fontSize, 14.5);
    });

    testWidgets('tone colours the number: ok green, warn and danger red', (tester) async {
      await tester.pumpWidget(host(const Column(children: [
        HeroNumber(value: '1', tone: StatusTone.ok),
        HeroNumber(value: '2', tone: StatusTone.warn),
        HeroNumber(value: '3', tone: StatusTone.danger),
        HeroNumber(value: '4'),
      ])));
      expect(tester.widget<Text>(find.text('1')).style?.color, c.ok);
      expect(tester.widget<Text>(find.text('2')).style?.color, c.danger);
      expect(tester.widget<Text>(find.text('3')).style?.color, c.danger);
      expect(tester.widget<Text>(find.text('4')).style?.color, c.ink);
    });

    testWidgets('kazakh hero with lead, tag and two sub-lines at 1.3x fits a 360 dp card', (tester) async {
      await tester.pumpWidget(host(
        const Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: HeroNumber(
            lead: 'Бұл кезектегі пациенттердің жартысы ауруханаға жатқызуды одан артық күтпейді',
            value: '≈ 47',
            unit: 'күн',
            line: '10 пациенттің 9-ы 106 күннен артық күтпейді.\nПациенттердің 54 %-ы 30 күн ішінде ауруханаға түседі.',
            origin: Origin.ml,
          ),
        ),
        locale: 'kk',
        textScale: 1.3,
      ));
      expect(tester.takeException(), isNull);
    });
  });

  group('KpiTile', () {
    testWidgets('label-first: label 13.5/600 text-secondary above the 22/800 value, origin in the label line, hint below', (tester) async {
      await tester.pumpWidget(host(const KpiTile(
        labelFirst: true,
        label: 'Пациентов в листе ожидания',
        value: '1784',
        origin: Origin.formula,
        hint: 'по данным на 31.03.2025',
      )));
      final label = tester.widget<Text>(find.text('Пациентов в листе ожидания'));
      expect(label.style?.fontSize, 13.5);
      expect(label.style?.fontWeight, FontWeight.w600);
      expect(label.style?.color, c.muted);
      expect(tester.widget<Text>(find.text('1784')).style?.fontSize, 22);
      expect(tester.getTopLeft(find.text('Пациентов в листе ожидания')).dy, lessThan(tester.getTopLeft(find.text('1784')).dy));
      expect(tester.getTopLeft(find.text('расчёт по правилу')).dy, lessThan(tester.getTopLeft(find.text('1784')).dy));
      expect(tester.widget<Text>(find.text('по данным на 31.03.2025')).style?.fontSize, 12);
    });

    testWidgets('default layout keeps value first; tone colours the value', (tester) async {
      await tester.pumpWidget(host(const KpiRow(children: [
        KpiTile(value: '47', label: 'половина ждёт не дольше, дн.', tone: StatusTone.ok),
        KpiTile(value: '106', label: '9 из 10 не дольше, дн.', tone: StatusTone.warn),
        KpiTile(value: '20 %', label: 'риск отказа', tone: StatusTone.danger),
      ])));
      expect(tester.getTopLeft(find.text('47')).dy, lessThan(tester.getTopLeft(find.text('половина ждёт не дольше, дн.')).dy));
      expect(tester.widget<Text>(find.text('47')).style?.color, c.ok);
      expect(tester.widget<Text>(find.text('106')).style?.color, c.warn);
      expect(tester.widget<Text>(find.text('20 %')).style?.color, c.danger);
    });

    testWidgets('KpiRow with columns: 2 wraps three tiles into two rows', (tester) async {
      await tester.pumpWidget(host(const KpiRow(columns: 2, children: [
        KpiTile(value: '1', label: 'а'),
        KpiTile(value: '2', label: 'б'),
        KpiTile(value: '3', label: 'в'),
      ])));
      expect(tester.getTopLeft(find.text('1')).dy, tester.getTopLeft(find.text('2')).dy);
      expect(tester.getTopLeft(find.text('3')).dy, greaterThan(tester.getTopLeft(find.text('1')).dy));
      expect(tester.getSize(find.ancestor(of: find.text('3'), matching: find.byType(KpiTile))).width,
          tester.getSize(find.ancestor(of: find.text('1'), matching: find.byType(KpiTile))).width,
          reason: 'неполный ряд держит ширину колонки');
    });
  });

  group('StatGrid', () {
    testWidgets('label above value in two columns with border-soft hairlines between cells', (tester) async {
      await tester.pumpWidget(host(const StatGrid(items: [
        StatItem(label: 'Половина ждёт не дольше', value: '≈ 47', unit: 'дн.'),
        StatItem(label: '9 из 10 ждут не дольше', value: '≈ 106', unit: 'дн.'),
        StatItem(label: 'За 30 дней', value: '54 %'),
      ])));
      final label = tester.widget<Text>(find.text('Половина ждёт не дольше'));
      expect(label.style?.fontSize, 12);
      // значение и единица — одна строка Text.rich: единица мельче (13.5/700)
      expect(tester.widget<Text>(find.text('≈ 47 дн.')).style?.fontSize, 19);
      expect(tester.getTopLeft(find.text('Половина ждёт не дольше')).dy, lessThan(tester.getTopLeft(find.text('≈ 47 дн.')).dy));
      expect(tester.getTopLeft(find.text('≈ 47 дн.')).dy, tester.getTopLeft(find.text('≈ 106 дн.')).dy);
      expect(tester.getTopLeft(find.text('54 %')).dy, greaterThan(tester.getTopLeft(find.text('≈ 47 дн.')).dy));
      final lines = tester.widgetList<Container>(find.byType(Container)).where((box) {
        final border = (box.decoration as BoxDecoration?)?.border;
        return border is Border && (border.left.color == c.borderSoft || border.top.color == c.borderSoft);
      });
      expect(lines, isNotEmpty);
    });

    testWidgets('kazakh stat grid at 1.3x does not overflow', (tester) async {
      await tester.pumpWidget(host(
        const StatGrid(items: [
          StatItem(label: 'Жартысы одан артық күтпейді', value: '≈ 47', unit: 'күн'),
          StatItem(label: '10-ның 9-ы одан артық күтпейді', value: '≈ 106', unit: 'күн'),
        ]),
        locale: 'kk',
        textScale: 1.3,
      ));
      expect(tester.takeException(), isNull);
    });
  });
}
