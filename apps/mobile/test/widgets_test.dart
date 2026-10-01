import 'package:darumen/api/models.dart';
import 'package:darumen/l10n/strings.dart';
import 'package:darumen/screens/vaccination_screen.dart';
import 'package:darumen/theme/app_theme.dart';
import 'package:darumen/widgets/checklist_tile.dart';
import 'package:darumen/widgets/collapsible_section.dart';
import 'package:darumen/widgets/day_groups.dart';
import 'package:darumen/widgets/hero_number.dart';
import 'package:darumen/widgets/kpi_tile.dart';
import 'package:darumen/widgets/org_name.dart';
import 'package:darumen/widgets/origin_tag.dart';
import 'package:darumen/widgets/picker_sheet.dart';
import 'package:darumen/widgets/route_timeline.dart';
import 'package:darumen/widgets/stage_stepper.dart';
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

const stages = [
  RouteStage(code: 'referral_issued', order: 1, title: 'Направление выдано', date: '2025-02-06', status: 'done'),
  RouteStage(code: 'examination', order: 2, title: 'Обследование', date: '2025-02-07', status: 'done'),
  RouteStage(code: 'waitlisted', order: 3, title: 'Внесено в лист ожидания', date: '2025-02-07', status: 'current'),
  RouteStage(code: 'date_assigned', order: 4, title: 'Дата госпитализации назначена', status: 'upcoming', norm: 'в течение 2 рабочих дней'),
  RouteStage(code: 'hospitalized', order: 5, title: 'Госпитализация', status: 'upcoming'),
];

const kkStages = [
  RouteStage(code: 'referral_issued', order: 1, title: 'Жолдама берілді', date: '2025-02-06', status: 'done'),
  RouteStage(code: 'examination', order: 2, title: 'Тексеру', date: '2025-02-07', status: 'done'),
  RouteStage(code: 'waitlisted', order: 3, title: 'Күту парағына енгізілді', date: '2025-02-07', status: 'current'),
  RouteStage(code: 'date_assigned', order: 4, title: 'Емдеуге жатқызу күні белгіленді', status: 'upcoming', norm: 'тіркелгеннен кейін 2 жұмыс күні ішінде белгіленеді'),
  RouteStage(code: 'hospitalized', order: 5, title: 'Емдеуге жатқызу', status: 'upcoming'),
];

const longOrg = 'Товарищество с ограниченной ответственностью "Достар Мед"';

void main() {
  testWidgets('timeline rows show short labels, dd.MM for passed stages, the norm for upcoming ones and a dash without it', (tester) async {
    await tester.pumpWidget(host(const RouteTimeline(stages: stages)));
    expect(find.text('Выдано'), findsOneWidget);
    expect(find.text('06.02'), findsOneWidget);
    expect(find.text('Лист ожидания'), findsOneWidget);
    expect(find.text('в течение 2 рабочих дней'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.byType(StageMarker), findsNWidgets(3), reason: 'маркер у текущего и пустые круги у двух предстоящих');
    expect(tester.takeException(), isNull);
  });

  testWidgets('stage stepper draws bars with one marker and labels first · current · last', (tester) async {
    await tester.pumpWidget(host(const StageStepper(stages: stages)));
    expect(find.byType(StageBar), findsNWidgets(4));
    expect(find.byType(StageMarker), findsOneWidget);
    expect(find.text('Выдано'), findsOneWidget);
    expect(find.text('Лист ожидания'), findsOneWidget);
    expect(find.text('Стационар'), findsOneWidget);
    expect(find.text('Анализы'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(host(const StageStepper(stages: stages, compact: true)));
    expect(find.text('Выдано'), findsNothing);
    expect(find.byType(StageMarker), findsOneWidget);
  });

  testWidgets('kazakh labels at 1.3x text scale do not overflow the new widgets', (tester) async {
    await tester.pumpWidget(host(
      Column(
        children: [
          const StageStepper(stages: kkStages),
          const RouteTimeline(stages: kkStages),
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
    expect(find.text('Берілді'), findsNWidgets(2), reason: 'степпер и строка таймлайна');
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

  test('day groups label today, yesterday and older days in both languages', () {
    final now = DateTime(2026, 9, 26, 12);
    final ru = S.of('ru');
    expect(dayHeading(DateTime(2026, 9, 26), ru, now: now), 'Сегодня');
    expect(dayHeading(DateTime(2026, 9, 25), ru, now: now), 'Вчера');
    expect(dayHeading(DateTime(2026, 9, 22), ru, now: now), '22 сентября');
    expect(dayHeading(DateTime(2025, 2, 6), ru, now: now), '6 февраля 2025');
    expect(dayHeading(DateTime(2026, 9, 22), S.of('kk'), now: now), '22 қыркүйек');
    final groups = groupByDay(['2026-09-26T09:00:00+00:00', '2026-09-22', '2026-09-26T07:00:00+00:00', null], (x) => x, ru, now: now);
    expect(groups.map((g) => g.label).toList(), ['Сегодня', '22 сентября', '—']);
    expect(groups.first.items, hasLength(2));
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

  testWidgets('checklist tile maps statuses to labels', (tester) async {
    const expired = ChecklistItem(code: 'cbc', title: 'Общий анализ крови', validityDays: 14, validityLabel: '14 дней', doneAt: '2025-02-07', validUntil: '2025-02-21', status: 'expired');
    const valid = ChecklistItem(code: 'hiv', title: 'Анализ на ВИЧ', validityDays: 180, validityLabel: '6 месяцев', doneAt: '2025-02-07', validUntil: '2025-08-06', status: 'valid');
    await tester.pumpWidget(host(const Column(children: [ChecklistTile(expired), ChecklistTile(valid)])));
    expect(find.text('Истёк'), findsOneWidget);
    expect(find.text('Действует'), findsOneWidget);
    expect(find.textContaining('до 21.02.2025'), findsOneWidget);
  });
}
