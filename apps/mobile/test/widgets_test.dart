import 'package:darumen/api/models.dart';
import 'package:darumen/screens/vaccination_screen.dart';
import 'package:darumen/theme/app_theme.dart';
import 'package:darumen/widgets/collapsible_section.dart';
import 'package:darumen/widgets/hero_number.dart';
import 'package:darumen/widgets/kpi_tile.dart';
import 'package:darumen/widgets/org_name.dart';
import 'package:darumen/widgets/origin_tag.dart';
import 'package:darumen/widgets/picker_sheet.dart';
import 'package:darumen/widgets/status_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child, {String locale = 'ru', double textScale = 1.0, double width = 360}) => MaterialApp(
      theme: AppTheme.light(),
      locale: Locale(locale),
      supportedLocales: const [Locale('ru'), Locale('kk')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale), size: Size(width, 800)),
        child: Scaffold(body: Center(child: SizedBox(width: width, child: SingleChildScrollView(child: child)))),
      ),
    );

const longOrg = 'Товарищество с ограниченной ответственностью "Достар Мед"';

void main() {
  testWidgets('kazakh labels at 1.3x text scale do not overflow the shared widgets', (tester) async {
    await tester.pumpWidget(host(
      Column(
        children: [
          const StatusChip('емдеуге жатқызуға дейін мерзімі өтеді', tone: StatusTone.warn),
          const Row(children: [Expanded(child: KpiTile(value: '106', label: '10-ның 9-ы одан артық күтпейді, күн', origin: Origin.ml))]),
          const CollapsibleSection(title: 'Талдаулар', summary: '7 мерзімі өтті, 3 жарамды', origin: Origin.formula, child: Text('мазмұны')),
          PickerRow(label: 'Төсек бейіні', value: 'Ересектерге арналған хирургиялық', detail: 'жылына 11 330 078 рецепт', onTap: () {}),
          const HeroNumber(value: '≈ 80', unit: 'күн', caption: 'жартысы одан артық күтпейді', line: '10-ның 9-ы — 106 дейін · 30 күнде 54 %', origin: Origin.ml),
          const OrgName(longOrg, prefix: 'Ересектерге арналған хирургиялық · ', maxLines: 2),
        ],
      ),
      locale: 'kk',
      textScale: 1.3,
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('модель болжамы'), findsNWidgets(2));
  });

  testWidgets('collapsible section shows its summary and expands on tap without errors', (tester) async {
    await tester.pumpWidget(host(const CollapsibleSection(title: 'Анализы', summary: '7 истекли, 3 действуют', origin: Origin.formula, child: Text('список анализов'))));
    expect(find.text('7 истекли, 3 действуют'), findsOneWidget);
    expect(find.text('список анализов'), findsNothing);
    await tester.tap(find.text('Анализы'));
    await tester.pumpAndSettle();
    expect(find.text('список анализов'), findsOneWidget);
    await tester.tap(find.text('Анализы'));
    await tester.pumpAndSettle();
    expect(find.text('список анализов'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('picker sheet filters by search and returns the chosen value', (tester) async {
    String? chosen;
    await tester.pumpWidget(host(Builder(
      builder: (context) => PickerRow(
        label: 'Регион',
        value: 'г. Алматы',
        onTap: () async => chosen = await PickerSheet.show<String>(
          context,
          title: 'Регион',
          items: const [PickerItem('75', 'г. Алматы'), PickerItem('71', 'г. Астана'), PickerItem('11', 'Акмолинская область')],
          selected: '75',
        ),
      ),
    )));
    expect(find.text('Регион'), findsOneWidget);
    expect(find.text('г. Алматы'), findsOneWidget);
    await tester.tap(find.text('г. Алматы'));
    await tester.pumpAndSettle();
    expect(find.text('г. Астана'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'акмол');
    await tester.pumpAndSettle();
    expect(find.text('г. Астана'), findsNothing);
    await tester.tap(find.text('Акмолинская область'));
    await tester.pumpAndSettle();
    expect(chosen, '11');
    expect(tester.takeException(), isNull);
  });

  testWidgets('org name shows the short name and opens the full legal name on tap', (tester) async {
    await tester.pumpWidget(host(const OrgName(longOrg, prefix: 'Офтальмология · ')));
    expect(find.text('Офтальмология · Достар Мед'), findsOneWidget);
    await tester.tap(find.byType(OrgName));
    await tester.pumpAndSettle();
    expect(find.text(longOrg), findsOneWidget);
    expect(find.text('Полное юридическое название'), findsOneWidget);
  });

  testWidgets('origin tag opens an explanation sheet on tap', (tester) async {
    await tester.pumpWidget(host(const OriginTag(Origin.ml)));
    expect(find.text('прогноз модели'), findsOneWidget);
    await tester.tap(find.text('прогноз модели'));
    await tester.pumpAndSettle();
    expect(find.textContaining('по истории очередей'), findsOneWidget);
  });

  test('vaccines are grouped by code with years ascending and the latest last', () {
    final items = [
      for (final (year, pct) in [(2021, 86.0), (2019, 81.0), (2020, 86.0)])
        VaccinationEstimate(vaccine: 'BCG', title: 'БЦЖ', year: year, coveragePct: pct, source: 'WHO'),
      const VaccinationEstimate(vaccine: 'MCV1', title: 'корь, первая доза', year: 2021, coveragePct: 70, source: 'WHO'),
    ];
    final groups = groupVaccines(items, 'ru');
    expect(groups.map((g) => g.title).toList(), ['БЦЖ', 'корь, первая доза']);
    expect(groups.first.latest.year, 2021);
    expect(groups.first.previous.map((y) => y.year).toList(), [2019, 2020]);
  });
}
