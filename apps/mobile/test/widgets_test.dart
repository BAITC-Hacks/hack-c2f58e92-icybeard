import 'package:darumen/api/models.dart';
import 'package:darumen/l10n/strings.dart';
import 'package:darumen/screens/vaccination_screen.dart';
import 'package:darumen/theme/app_theme.dart';
import 'package:darumen/widgets/checklist_tile.dart';
import 'package:darumen/widgets/collapsible_section.dart';
import 'package:darumen/widgets/day_groups.dart';
import 'package:darumen/widgets/doctor_route_view.dart';
import 'package:darumen/widgets/hero_number.dart';
import 'package:darumen/widgets/kpi_tile.dart';
import 'package:darumen/widgets/org_name.dart';
import 'package:darumen/widgets/origin_tag.dart';
import 'package:darumen/widgets/picker_sheet.dart';
import 'package:darumen/widgets/redirect_reason_dialog.dart';
import 'package:darumen/widgets/route_events.dart';
import 'package:darumen/widgets/route_timeline.dart';
import 'package:darumen/widgets/route_view.dart';
import 'package:darumen/widgets/signal_card.dart';
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

PatientRoute citizenRoute({bool validationDue = true, List<Map<String, dynamic>> signals = const [], List<Map<String, dynamic>> decisions = const []}) =>
    PatientRoute.fromJson({
      'patientRef': 'SYN-75-028B-381-01',
      'stage': 'waitlisted',
      'organization': {'moCode': '028B', 'moName': 'Институт', 'profileCode': '381', 'profileName': 'Офтальмология'},
      'timeline': [for (final s in stages) {'code': s.code, 'order': s.order, 'title': s.title, 'date': s.date, 'status': s.status, 'norm': s.norm}],
      'forecast': {'p50Days': 47, 'p90Days': 106, 'fromModel': true},
      'alternatives': [
        {'mo': {'moCode': '22GN', 'name': longOrg}, 'p50Days': 9, 'p90Days': 20, 'pRefusal': 0.1, 'distanceKm': 12},
      ],
      'validationDue': validationDue,
      'signals': signals,
      'decisions': decisions,
    });

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

  testWidgets('reason sheet requires a reason, returns it and survives its exit animation', (tester) async {
    String? result;
    await tester.pumpWidget(host(Builder(
      builder: (context) => FilledButton(
        onPressed: () async => result = await RedirectReasonDialog.show(context, organization: longOrg),
        child: const Text('open'),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Достар Мед'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Направить сюда')).enabled, isFalse);
    await tester.enterText(find.byType(TextField), 'ожидание короче');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Направить сюда'));
    await tester.pumpAndSettle();
    expect(result, 'ожидание короче');
    expect(tester.takeException(), isNull);
  });

  testWidgets('citizen route asks "are you still waiting" with three options and lets the patient ask for a faster organisation', (tester) async {
    final signals = <String>[];
    Alternative? requested;
    await tester.pumpWidget(host(RouteView(route: citizenRoute(), onSignal: signals.add, onRequest: (a) => requested = a)));
    expect(find.text('В листе ожидания'), findsOneWidget);
    expect(find.text('Половина — 47 дн., 9 из 10 — до 106 дн.'), findsOneWidget);
    expect(find.text('до 106'), findsOneWidget);
    expect(find.text('Вы ещё ждёте госпитализацию?'), findsOneWidget);
    expect(find.text('Уже лечился в другом месте'), findsOneWidget);
    await tester.ensureVisible(find.text('Да, жду'));
    await tester.tap(find.text('Да, жду'));
    expect(signals, ['still_waiting']);
    expect(find.text('Достар Мед ≈ 9 дн.'), findsOneWidget);
    await tester.ensureVisible(find.text('Где быстрее'));
    await tester.tap(find.text('Где быстрее'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Попросить'));
    await tester.tap(find.text('Попросить'));
    expect(requested?.moCode, '22GN');
    expect(find.text('Направить сюда'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('citizen route shows the doctor answer as a signal card, then "what now" with the pending request chip', (tester) async {
    final route = citizenRoute(
      validationDue: false,
      decisions: [
        {'decisionId': 'd1', 'recordedAt': '2025-02-20T10:00:00+00:00', 'toMoCode': '22GN', 'toMoName': longOrg, 'reason': 'ближе к дому', 'kind': 'redirect'},
      ],
      signals: [
        {'decisionId': 'a', 'recordedAt': '2025-02-21T10:00:00+00:00', 'kind': 'request_redirect', 'toMoCode': '22GN', 'toMoName': longOrg, 'open': true},
      ],
    );
    var opened = false;
    await tester.pumpWidget(host(RouteView(route: route, onSignal: (_) {}, onRequest: (_) {}, seenDecisionId: null, onOpenAnswer: () => opened = true)));
    expect(find.byType(SignalCard), findsOneWidget);
    expect(find.text('Врач предложил Достар Мед'), findsOneWidget);
    expect(find.textContaining('«ближе к дому»'), findsOneWidget);
    expect(find.text('Что сейчас'), findsNothing);
    await tester.ensureVisible(find.text('Врач предложил Достар Мед'));
    await tester.tap(find.text('Врач предложил Достар Мед'));
    expect(opened, isTrue);
    // после «Понятно» (экран запоминает решение) — «Что сейчас» с чипом ожидания ответа и следующим этапом
    await tester.pumpWidget(host(RouteView(route: route, onSignal: (_) {}, onRequest: (_) {}, seenDecisionId: 'd1')));
    expect(find.byType(SignalCard), findsNothing);
    expect(find.text('Что сейчас'), findsOneWidget);
    expect(find.text('Ждёт ответа врача'), findsOneWidget);
    expect(find.text('Следующий этап: Дата госпитализации назначена'), findsOneWidget);
    await tester.ensureVisible(find.text('Где быстрее'));
    await tester.tap(find.text('Где быстрее'));
    await tester.pumpAndSettle();
    expect(find.text('Запрос отправлен'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('doctor route shows the panel first and answers the open signal with an inline reason', (tester) async {
    final route = PatientRoute.fromJson({
      'patientRef': 'SYN-75-028B-381-01',
      'audience': 'doctor',
      'stage': 'waitlisted',
      'organization': {'moCode': '028B', 'moName': 'Институт', 'profileCode': '381', 'profileName': 'Офтальмология'},
      'timeline': [for (final s in stages) {'code': s.code, 'order': s.order, 'title': s.title, 'date': s.date, 'status': s.status}],
      'forecast': {'p50Days': 47, 'p90Days': 106, 'fromModel': true},
      'alternatives': [
        {'mo': {'moCode': '22GN', 'name': longOrg}, 'p50Days': 9, 'p90Days': 20, 'pRefusal': 0.1, 'distanceKm': 12},
      ],
      'doctor': {'priority': 12, 'riskFlags': ['patient_signal'], 'nextAction': 'ждать вызова', 'nextActionCode': 'wait_for_call', 'explanation': '', 'pRefusal': 0.2, 'refusalOrgInTraining': true},
      'signals': [
        {'decisionId': 'a', 'recordedAt': '2026-09-25T10:00:00+00:00', 'kind': 'request_redirect', 'toMoCode': '22GN', 'toMoName': longOrg, 'comment': 'живу рядом', 'open': true},
      ],
    });
    String? kept;
    Alternative? redirected;
    String? redirectReason;
    await tester.pumpWidget(host(DoctorRouteView(
      route: route,
      onRedirect: (a, {reason}) {
        redirected = a;
        redirectReason = reason;
      },
      onKeep: (reason) => kept = reason,
    )));
    expect(find.textContaining('приоритет 12'), findsOneWidget);
    expect(find.text('РЕКОМЕНДАЦИЯ'), findsOneWidget);
    expect(find.text('≈ 9'), findsOneWidget, reason: 'hero — лучшая альтернатива');
    expect(find.text('Риск отказа 20 %'), findsOneWidget, reason: 'риск отказа виден только врачу');
    expect(find.text('Следующий шаг: ждать вызова'), findsOneWidget);
    expect(find.text('Пациент просит Достар Мед'), findsOneWidget);
    expect(find.text('Вы ещё ждёте госпитализацию?'), findsNothing);
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Оставить')).enabled, isFalse, reason: 'без причины кнопки заблокированы');
    await tester.enterText(find.byType(TextField).first, 'профиль совпадает');
    await tester.pump();
    await tester.ensureVisible(find.text('Оставить'));
    await tester.tap(find.text('Оставить'));
    expect(kept, 'профиль совпадает');
    await tester.ensureVisible(find.text('Направить сюда'));
    await tester.tap(find.text('Направить сюда'));
    expect(redirected?.moCode, '22GN');
    expect(redirectReason, 'профиль совпадает');
    expect(tester.takeException(), isNull);
  });

  test('route events carry a kind, short names and the open-route action', () {
    final route = citizenRoute(
      signals: [
        {'decisionId': 'a', 'recordedAt': '2026-09-25T10:00:00+00:00', 'kind': 'request_redirect', 'toMoCode': '22GN', 'toMoName': longOrg, 'open': true},
      ],
      decisions: [
        {'decisionId': 'd', 'recordedAt': '2026-09-26T10:00:00+00:00', 'toMoCode': '22GN', 'toMoName': longOrg, 'reason': 'ближе', 'kind': 'redirect'},
      ],
    );
    final events = routeEvents(route, S.of('ru'));
    expect(events.first.title, 'Врач предложил Достар Мед');
    expect(events.first.kind, RouteEventKind.doctor);
    expect(events.first.detail, '«ближе»');
    expect(events.first.opensRoute, isTrue);
    expect(events[1].title, 'Вы попросили рассмотреть: Достар Мед');
    expect(events[1].detail, 'ждёт ответа врача');
    expect(events.last.kind, RouteEventKind.stage);
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
