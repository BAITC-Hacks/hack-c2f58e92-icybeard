import 'dart:convert';

import 'package:darumen/api/models.dart';
import 'package:darumen/l10n/strings.dart';
import 'package:darumen/screens/scribe_screen.dart';
import 'package:darumen/state/session.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:darumen/theme/app_theme.dart';
import 'package:darumen/widgets/checklist_tile.dart';
import 'package:darumen/widgets/kpi_tile.dart';
import 'package:darumen/widgets/origin_tag.dart';
import 'package:darumen/widgets/redirect_reason_dialog.dart';
import 'package:darumen/widgets/route_events.dart';
import 'package:darumen/widgets/route_timeline.dart';
import 'package:darumen/widgets/route_view.dart';
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

void main() {
  testWidgets('timeline shows dates for passed stages and the norm for upcoming ones', (tester) async {
    await tester.pumpWidget(host(const RouteTimeline(stages: stages)));
    expect(find.text('Направление выдано'), findsOneWidget);
    expect(find.text('06.02.2025'), findsOneWidget);
    expect(find.text('в течение 2 рабочих дней'), findsOneWidget);
    expect(find.textContaining('Госпитализация'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('kazakh titles at 1.3x text scale do not overflow the timeline or chips', (tester) async {
    const kk = [
      RouteStage(code: 'referral_issued', order: 1, title: 'Жолдама берілді', date: '2025-02-06', status: 'done'),
      RouteStage(code: 'waitlisted', order: 3, title: 'Күту парағына енгізілді', date: '2025-02-07', status: 'current'),
      RouteStage(code: 'date_assigned', order: 4, title: 'Емдеуге жатқызу күні белгіленді', status: 'upcoming', norm: 'тіркелгеннен кейін 2 жұмыс күні ішінде белгіленеді'),
    ];
    await tester.pumpWidget(host(
      const Column(
        children: [
          RouteTimeline(stages: kk),
          StatusChip('емдеуге жатқызуға дейін мерзімі өтеді', tone: StatusTone.warn),
          Row(children: [Expanded(child: KpiTile(value: '106', label: '10-ның 9-ы одан артық күтпейді, күн', origin: Origin.ml))]),
        ],
      ),
      locale: 'kk',
      textScale: 1.3,
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('ML‑МОДЕЛЬ'), findsOneWidget);
  });

  testWidgets('origin tag opens an explanation sheet on tap', (tester) async {
    await tester.pumpWidget(host(const OriginTag(Origin.ml)));
    expect(find.text('ML‑МОДЕЛЬ'), findsOneWidget);
    await tester.tap(find.text('ML‑МОДЕЛЬ'));
    await tester.pumpAndSettle();
    expect(find.textContaining('отложенном месяце'), findsOneWidget);
  });

  testWidgets('redirect reason dialog returns the reason and survives its exit animation', (tester) async {
    String? result;
    await tester.pumpWidget(host(Builder(
      builder: (context) => FilledButton(
        onPressed: () async => result = await RedirectReasonDialog.show(context, organization: 'ГКБ №5'),
        child: const Text('open'),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ожидание короче');
    await tester.tap(find.text('Направить сюда'));
    await tester.pumpAndSettle();
    expect(result, 'ожидание короче');
    expect(tester.takeException(), isNull);
  });

  testWidgets('scribe transcript step lays out the microphone button next to the text field', (tester) async {
    // кнопки темы растянуты на всю ширину: внутри Row без Expanded они роняли layout («forces an infinite width»)
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    final api = MockClient((request) async {
      if (request.method == 'POST' && request.url.path.endsWith('/scribe/sessions')) {
        return http.Response(jsonEncode({'sessionId': 's1'}), 200, headers: {'content-type': 'application/json'});
      }
      return http.Response('{}', 404);
    });
    final session = Session(httpClient: api);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru'), Locale('kk')],
      localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      home: ChangeNotifierProvider<Session>.value(value: session, child: const ScribeScreen()),
    ));
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.tap(find.text('Начать сессию'));
    await tester.pumpAndSettle();
    expect(find.text('Записать с микрофона'), findsOneWidget);
    expect(find.text('Составить черновик'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('citizen route asks "are you still waiting" and lets the patient request a faster organisation', (tester) async {
    final route = PatientRoute.fromJson({
      'patientRef': 'SYN-75-028B-381-01',
      'organization': {'moCode': '028B', 'moName': 'Институт', 'profileCode': '381', 'profileName': 'Офтальмология'},
      'forecast': {'p50Days': 47, 'p90Days': 106, 'fromModel': true},
      'alternatives': [
        {'mo': {'moCode': '22GN', 'name': 'Больница №2'}, 'p50Days': 9, 'p90Days': 20, 'pRefusal': 0.1, 'distanceKm': 12},
      ],
      'validationDue': true,
    });
    final signals = <String>[];
    Alternative? requested;
    await tester.pumpWidget(host(RouteView(route: route, onSignal: signals.add, onRequest: (a) => requested = a)));
    expect(find.text('Вы ещё ждёте госпитализацию?'), findsOneWidget);
    await tester.tap(find.text('Да, жду'));
    expect(signals, ['still_waiting']);
    // альтернативы ниже прогноза и этапов — на экране 360×800 они за пределами вьюпорта
    await tester.ensureVisible(find.text('Попросить'));
    await tester.tap(find.text('Попросить'));
    expect(requested?.moCode, '22GN');
    expect(find.text('Направить сюда'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('doctor route shows the open patient signal with keep and redirect actions', (tester) async {
    final route = PatientRoute.fromJson({
      'patientRef': 'SYN-75-028B-381-01',
      'audience': 'doctor',
      'organization': {'moCode': '028B', 'moName': 'Институт', 'profileCode': '381', 'profileName': 'Офтальмология'},
      'forecast': {'p50Days': 47, 'p90Days': 106, 'fromModel': true},
      'alternatives': [
        {'mo': {'moCode': '22GN', 'name': 'Больница №2'}, 'p50Days': 9, 'p90Days': 20, 'pRefusal': 0.1, 'distanceKm': 12},
      ],
      'doctor': {'priority': 12, 'riskFlags': ['patient_signal'], 'nextAction': 'ждать вызова', 'nextActionCode': 'wait_for_call', 'explanation': '', 'pRefusal': 0.2, 'refusalOrgInTraining': true},
      'signals': [
        {'decisionId': 'a', 'recordedAt': '2026-09-25T10:00:00+00:00', 'kind': 'request_redirect', 'toMoCode': '22GN', 'toMoName': 'Больница №2', 'comment': 'живу рядом', 'open': true},
      ],
    });
    var kept = false;
    Alternative? redirected;
    await tester.pumpWidget(host(RouteView(route: route, doctorMode: true, onRedirect: (a) => redirected = a, onKeep: () => kept = true)));
    expect(find.text('Пациент просит рассмотреть: Больница №2'), findsWidgets);
    expect(find.text('Вы ещё ждёте госпитализацию?'), findsNothing);
    await tester.ensureVisible(find.text('Оставить'));
    await tester.tap(find.text('Оставить'));
    expect(kept, isTrue);
    await tester.ensureVisible(find.text('Направить сюда').first);
    await tester.tap(find.text('Направить сюда').first);
    expect(redirected?.moCode, '22GN');
    expect(tester.takeException(), isNull);
  });

  test('route events include signals and expiring tests, newest first', () {
    final route = PatientRoute.fromJson({
      'patientRef': 'SYN-75-028B-381-01',
      'organization': {'moCode': '028B', 'moName': 'Институт', 'profileCode': '381', 'profileName': 'Офтальмология'},
      'forecast': {'p50Days': 47, 'p90Days': 106},
      'timeline': [
        {'code': 'waitlisted', 'order': 3, 'title': 'Внесено в лист ожидания', 'date': '2025-02-17', 'status': 'current'},
        {'code': 'date_assigned', 'order': 4, 'title': 'Дата назначена', 'status': 'upcoming'},
      ],
      'checklist': [
        {'code': 'cbc', 'title': 'ОАК', 'validityDays': 14, 'validityLabel': '14 дней', 'doneAt': '2025-02-14', 'validUntil': '2025-02-28', 'status': 'expiring'},
        {'code': 'hiv', 'title': 'ВИЧ', 'validityDays': 180, 'validityLabel': '6 месяцев', 'doneAt': '2025-02-14', 'validUntil': '2025-08-13', 'status': 'valid'},
      ],
      'signals': [
        {'decisionId': 'a', 'recordedAt': '2026-09-25T10:00:00+00:00', 'kind': 'request_redirect', 'toMoCode': '22GN', 'toMoName': 'Больница №2', 'open': true},
      ],
    });
    final events = routeEvents(route, S.of('ru'));
    expect(events.map((e) => e.title).toList(), ['Вы попросили рассмотреть: Больница №2', 'ОАК действует до 28.02.2025', 'Внесено в лист ожидания']);
    expect(events.first.detail, 'ждёт ответа врача');
  });

  testWidgets('checklist tile maps statuses to labels', (tester) async {
    const expired = ChecklistItem(code: 'cbc', title: 'Общий анализ крови', validityDays: 14, validityLabel: '14 дней', doneAt: '2025-02-07', validUntil: '2025-02-21', status: 'expired');
    const valid = ChecklistItem(code: 'hiv', title: 'Анализ на ВИЧ', validityDays: 180, validityLabel: '6 месяцев', doneAt: '2025-02-07', validUntil: '2025-08-06', status: 'valid');
    await tester.pumpWidget(host(const Column(children: [ChecklistTile(expired), ChecklistTile(valid)])));
    expect(find.text('истёк'), findsOneWidget);
    expect(find.text('действует'), findsOneWidget);
    expect(find.textContaining('до 21.02.2025'), findsOneWidget);
  });
}
