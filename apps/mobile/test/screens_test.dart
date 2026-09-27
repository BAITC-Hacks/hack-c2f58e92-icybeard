import 'dart:convert';

import 'package:darumen/screens/decisions_screen.dart';
import 'package:darumen/screens/home_screen.dart';
import 'package:darumen/screens/login_screen.dart';
import 'package:darumen/screens/scribe_screen.dart';
import 'package:darumen/screens/updates_screen.dart';
import 'package:darumen/screens/worklist_screen.dart';
import 'package:darumen/state/session.dart';
import 'package:darumen/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'session_test.dart' show fakeJwt;

/// Сессия с мок-Keycloak и мок-API в одном клиенте: токен с ролями, остальное — обработчик `api` по пути.
Future<Session> apiSession({required List<String> roles, required Map<String, Object> api, String? region}) async {
  FlutterSecureStorage.setMockInitialValues({});
  SharedPreferences.setMockInitialValues({});
  final client = MockClient((request) async {
    if (request.url.path.endsWith('/protocol/openid-connect/token')) {
      final token = fakeJwt({'preferred_username': 'doctor1', 'realm_access': {'roles': roles}, 'region_kato': ?region});
      return http.Response(jsonEncode({'access_token': token, 'refresh_token': 'r', 'expires_in': 300}), 200);
    }
    for (final entry in api.entries) {
      if (request.url.path.endsWith(entry.key)) {
        return http.Response(jsonEncode(entry.value), 200, headers: {'content-type': 'application/json'});
      }
    }
    return http.Response(jsonEncode({'title': 'Not found'}), 404, headers: {'content-type': 'application/problem+json'});
  });
  final session = Session(httpClient: client);
  await session.load();
  if (roles.isNotEmpty) {
    await session.login('doctor1', 'darumen');
  }
  return session;
}

Widget app(Session session, Widget screen) => MaterialApp(
      theme: AppTheme.light(),
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru'), Locale('kk')],
      localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      home: ChangeNotifierProvider<Session>.value(value: session, child: screen),
    );

const longOrg = 'Коммунальное государственное предприятие на праве хозяйственного ведения "Городской перинатальный центр" Управления общественного здравоохранения города Алматы';
const dostar = 'Товарищество с ограниченной ответственностью "Достар Мед"';

Map<String, Object> worklistItem(String ref, {List<String> flags = const [], int priority = 10, int days = 40, String next = 'review_before_call', Map<String, Object>? signal}) => {
      'patientRef': ref,
      'stage': 'вызов на госпитализацию',
      'stageCode': 'called',
      'riskFlags': flags,
      'priority': priority,
      'nextAction': 'проверить показания и документы до вызова',
      'nextActionCode': next,
      'explanation': '',
      'moCode': '0290',
      'moName': longOrg,
      'profileCode': '241',
      'regionKato': '75',
      'daysWaiting': days,
      'patientSignal': ?signal,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('login screen: language toggle, carousel with dots, bottom buttons and the password sheet', (tester) async {
    final session = await apiSession(roles: [], api: {});
    await tester.pumpWidget(app(session, const LoginScreen()));
    await tester.pump();
    expect(find.text('РУС'), findsOneWidget);
    expect(find.text('ҚАЗ'), findsOneWidget);
    expect(find.text('Видите, на каком этапе ваше направление'), findsOneWidget);
    expect(find.byType(PageView), findsOneWidget);
    expect(find.text('Войти через eGov mobile'), findsOneWidget);
    expect(find.text('Продолжить как гость'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(find.text('Знаете, сколько обычно ждут такие пациенты'), findsOneWidget);
    await tester.tap(find.text('Войти по логину'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(2));
    await tester.tap(find.text('ҚАЗ'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('home screen for a guest shows the invitation and three equal tiles', (tester) async {
    final session = await apiSession(roles: [], api: {});
    await tester.pumpWidget(app(session, const HomeScreen()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Войдите через eGov mobile'), findsOneWidget);
    expect(find.text('Сколько ждут'), findsOneWidget);
    expect(find.text('Лекарства'), findsOneWidget);
    expect(find.text('Вакцинация'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('worklist counts flags on the client, filters locally and shows the signal row with actions', (tester) async {
    final session = await apiSession(roles: ['doctor'], region: '75', api: {
      '/journal/worklist': {
        'items': [
          worklistItem('SYN-75-0290-241-01', flags: ['stuck_over_30', 'refusal_risk'], priority: 652, days: 85),
          worklistItem('SYN-75-0290-241-02', flags: ['faster_alternative'], priority: 40, days: 12, next: 'redirect_faster'),
          worklistItem('SYN-75-0290-241-03', flags: ['patient_signal'], priority: 15, days: 40, next: 'wait_for_call', signal: {
            'kind': 'request_redirect', 'toMoCode': '22GN', 'toMoName': dostar, 'comment': 'живу рядом', 'recordedAt': '2026-09-25T10:00:00+00:00',
          }),
        ],
        'synthetic': true, 'asOf': '2025-03-31', 'regionKato': '75', 'modelBacked': true,
      },
    });
    await tester.pumpWidget(app(session, const WorklistScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Пациенты · 75'), findsOneWidget);
    expect(find.text('данные на 31.03.2025'), findsOneWidget);
    expect(find.text('3'), findsOneWidget, reason: 'плитка «Все»');
    expect(find.text('Запрос пациента'), findsWidgets);
    expect(find.text('Городской перинатальный центр'), findsNWidgets(3));
    expect(find.text('Проверить до вызова'), findsOneWidget);
    expect(find.text('Предложить быстрее'), findsOneWidget);
    expect(find.text('Просит Достар Мед — „живу рядом“'), findsOneWidget);
    expect(find.text('Направить сюда'), findsOneWidget);
    expect(find.text('Оставить'), findsOneWidget);
    // сортировка по приоритету: SYN-…-01 первым
    final first = tester.getTopLeft(find.text('SYN-75-0290-241-01'));
    final second = tester.getTopLeft(find.text('SYN-75-0290-241-02'));
    expect(first.dy, lessThan(second.dy));
    // плитка-счётчик идёт в дереве раньше одноимённого чипа в строке
    await tester.tap(find.text('> 30 дней').first);
    await tester.pumpAndSettle();
    expect(find.text('SYN-75-0290-241-01'), findsOneWidget);
    expect(find.text('SYN-75-0290-241-02'), findsNothing);
    expect(find.text('SYN-75-0290-241-03'), findsNothing);
    await tester.tap(find.text('Есть быстрее').first);
    await tester.pumpAndSettle();
    expect(find.text('SYN-75-0290-241-02'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('updates are grouped by day with short names and the open-route action', (tester) async {
    final session = await apiSession(roles: ['citizen'], api: {
      '/route/me': {
        'patientRef': 'SYN-75-028B-381-01',
        'organization': {'moCode': '028B', 'moName': 'Институт', 'profileCode': '381', 'profileName': 'Офтальмология'},
        'forecast': {'p50Days': 47, 'p90Days': 106, 'fromModel': true},
        'timeline': [
          {'code': 'waitlisted', 'order': 3, 'title': 'Внесено в лист ожидания', 'date': '2025-02-17', 'status': 'current'},
        ],
        'decisions': [
          {'decisionId': 'd', 'recordedAt': '2025-02-20T10:00:00+00:00', 'toMoCode': '22GN', 'toMoName': dostar, 'reason': 'ближе к дому', 'kind': 'redirect'},
        ],
        'signals': [
          {'decisionId': 'a', 'recordedAt': '2025-02-19T10:00:00+00:00', 'kind': 'still_waiting', 'open': false},
        ],
      },
    });
    await tester.pumpWidget(app(session, const UpdatesScreen()));
    await tester.pumpAndSettle();
    expect(find.text('20 февраля 2025'), findsOneWidget);
    expect(find.text('19 февраля 2025'), findsOneWidget);
    expect(find.text('17 февраля 2025'), findsOneWidget);
    expect(find.text('Врач предложил Достар Мед'), findsOneWidget);
    expect(find.text('«ближе к дому»'), findsOneWidget);
    expect(find.text('Открыть маршрут'), findsOneWidget);
    expect(find.text('Вы подтвердили, что ждёте'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('decisions journal filters by subject, groups by day and opens the details sheet', (tester) async {
    final session = await apiSession(roles: ['doctor'], region: '75', api: {
      '/journal/decisions': {
        'items': [
          {'decisionId': 'aaaa-1', 'subject': 'route', 'subjectId': 'SYN-75-08IV-121-01', 'recommended': {'moCode': '031N'}, 'chosen': {'moCode': '22GN'}, 'reason': 'ожидание короче', 'recordedAt': '2025-02-25T12:26:38+00:00'},
          {'decisionId': 'bbbb-2', 'subject': 'referral', 'subjectId': '75.028B.381.11', 'recommended': null, 'chosen': {'moCode': '028B'}, 'reason': 'kc', 'recordedAt': '2025-02-10T12:07:20+00:00'},
        ],
        'page': 1, 'size': 50, 'total': 2,
      },
      '/refdata/organizations': {
        'items': [
          {'moCode': '22GN', 'name': dostar},
          {'moCode': '031N', 'name': 'Государственное учреждение "Региональный военный госпиталь"'},
        ],
      },
    });
    await tester.pumpWidget(app(session, const DecisionsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Региональный военный госпиталь → Достар Мед'), findsOneWidget);
    expect(find.text('— → 028B'), findsOneWidget, reason: 'организация вне справочника — кодом');
    expect(find.text('«ожидание короче»'), findsOneWidget);
    expect(find.text('25 февраля 2025'), findsOneWidget);
    // чип-фильтр идёт в дереве раньше чипа предмета в строке
    await tester.tap(find.text('Направление').first);
    await tester.pumpAndSettle();
    expect(find.text('Региональный военный госпиталь → Достар Мед'), findsNothing);
    await tester.tap(find.text('Все'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Региональный военный госпиталь → Достар Мед'));
    await tester.pumpAndSettle();
    expect(find.text('Ключ записи (decisionId)'), findsOneWidget);
    expect(find.text('aaaa-1'), findsOneWidget);
    expect(find.textContaining('(22GN)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scribe: consent enables start, the record step offers the microphone, paste fallback and the draft button', (tester) async {
    final session = await apiSession(roles: ['doctor'], api: {'/scribe/sessions': {'sessionId': 's1'}});
    await tester.pumpWidget(app(session, const ScribeScreen()));
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Начать')).enabled, isFalse);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('Начать'));
    await tester.pumpAndSettle();
    expect(find.text('Записать'), findsOneWidget);
    expect(find.text('Вставить текст'), findsOneWidget);
    expect(find.text('Составить черновик'), findsOneWidget);
    expect(find.text('RU'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
