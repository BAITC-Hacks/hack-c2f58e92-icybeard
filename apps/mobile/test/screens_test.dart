import 'dart:convert';

import 'package:darumen/screens/decisions_screen.dart';
import 'package:darumen/screens/home_screen.dart';
import 'package:darumen/screens/route_screen.dart';
import 'package:darumen/screens/scribe_screen.dart';
import 'package:darumen/screens/updates_screen.dart';
import 'package:darumen/screens/worklist_screen.dart';
import 'package:darumen/widgets/signal_card.dart';
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
Future<Session> apiSession({required List<String> roles, required Map<String, Object> api, String? region, Map<String, Object?> claims = const {}}) async {
  FlutterSecureStorage.setMockInitialValues({});
  SharedPreferences.setMockInitialValues({});
  final client = MockClient((request) async {
    if (request.url.path.endsWith('/protocol/openid-connect/token')) {
      final token = fakeJwt({'preferred_username': 'doctor1', 'realm_access': {'roles': roles}, 'region_kato': ?region, ...claims});
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

  Map<String, Object> citizenRoute() => {
        'patientRef': 'SYN-75-028B-381-01',
        'regionKato': '75',
        'organization': {'moCode': '028B', 'moName': 'Институт', 'profileCode': '381', 'profileName': 'Офтальмология'},
        'forecast': {'p50Days': 47, 'p90Days': 106, 'fromModel': true},
        'timeline': [
          {'code': 'referral_issued', 'order': 1, 'title': 'Направление выдано', 'date': '2025-02-06', 'status': 'done'},
          {'code': 'waitlisted', 'order': 3, 'title': 'Внесено в лист ожидания', 'date': '2025-02-17', 'status': 'current'},
          {'code': 'hospitalized', 'order': 5, 'title': 'Госпитализация', 'status': 'upcoming'},
        ],
        'alternatives': [
          {'mo': {'moCode': '22GN', 'name': dostar}, 'p50Days': 9, 'p90Days': 20, 'pRefusal': 0.1, 'distanceKm': 12},
        ],
        'decisions': [
          {'decisionId': 'd', 'recordedAt': '2025-02-20T10:00:00+00:00', 'toMoCode': '22GN', 'toMoName': dostar, 'reason': 'ближе к дому', 'kind': 'redirect'},
        ],
        'signals': [
          {'decisionId': 'a', 'recordedAt': '2025-02-19T10:00:00+00:00', 'kind': 'still_waiting', 'open': false},
        ],
      };

  testWidgets('home screen for a citizen: hero card, doctor signal with the day difference, three tiles, no weather or news', (tester) async {
    final session = await apiSession(roles: ['citizen'], api: {
      '/route/me': citizenRoute(),
      '/public/daily': {
        'regionKato': '75', 'regionName': 'г. Алматы', 'capital': 'Алматы',
        'weather': {'available': true, 'source': 'Open-Meteo', 'days': []},
        'tips': [],
        'news': {'available': true, 'source': 'Tengrinews', 'items': [{'title': 'В Алматы открыли новую поликлинику', 'url': 'https://example.kz/n1', 'publishedAt': null, 'source': 'Tengrinews'}]},
      },
    });
    await tester.pumpWidget(app(session, const HomeScreen()));
    await tester.pumpAndSettle();
    expect(find.text('МОЯ ГОСПИТАЛИЗАЦИЯ'), findsOneWidget, reason: 'label над hero — uppercase');
    expect(find.text('до 106'), findsOneWidget, reason: 'hero — 9 из 10 таких пациентов, p90');
    expect(find.text('дн. до госпитализации'), findsOneWidget);
    expect(find.text('В листе ожидания'), findsOneWidget);
    expect(find.text('прогноз модели'), findsOneWidget);
    expect(find.text('Открыть маршрут'), findsOneWidget);
    expect(find.byType(SignalCard), findsOneWidget);
    expect(find.text('Врач предложил Достар Мед'), findsOneWidget);
    expect(find.text('Там ждут на 38 дн. меньше'), findsOneWidget, reason: 'p50 текущей 47 − p50 предложенной 9');
    expect(find.text('Сколько ждут'), findsOneWidget);
    expect(find.text('Лекарства'), findsOneWidget);
    expect(find.text('Вакцинация'), findsOneWidget);
    expect(find.textContaining('Погода'), findsNothing);
    expect(find.text('В Алматы открыли новую поликлинику'), findsNothing);
    expect(find.text('Продолжить как гость'), findsNothing);
    expect(find.text('Данные МЗ РК, I квартал 2025. Без персональных данных.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('route screen: stage k of n, timeline rows, doctor answer as a signal card and «Понятно» at the bottom', (tester) async {
    final session = await apiSession(roles: ['citizen'], api: {'/route/me': citizenRoute()});
    await tester.pumpWidget(app(session, const RouteScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Мой путь'), findsOneWidget);
    expect(find.text('ЭТАП 2 ИЗ 3'), findsOneWidget);
    expect(find.text('до 106'), findsOneWidget);
    expect(find.text('Половина — 47 дн., 9 из 10 — до 106 дн.'), findsOneWidget);
    expect(find.text('Выдано'), findsOneWidget);
    expect(find.text('06.02'), findsOneWidget);
    expect(find.text('Стационар'), findsOneWidget);
    expect(find.byType(SignalCard), findsOneWidget);
    expect(find.text('Врач предложил Достар Мед'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Понятно'), findsOneWidget);
    await tester.tap(find.text('Понятно'));
    await tester.pumpAndSettle();
    expect(session.seenDecisionId, 'd');
    expect(find.byType(SignalCard), findsNothing);
    expect(find.text('Понятно'), findsNothing);
    expect(find.text('Что сейчас'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('worklist: «Сегодня» keeps flagged patients, «Все» shows everyone, rows carry one status chip, search filters by ref', (tester) async {
    final session = await apiSession(roles: ['doctor'], region: '75', api: {
      '/journal/worklist': {
        'items': [
          worklistItem('SYN-75-0290-241-01', flags: ['stuck_over_30', 'refusal_risk'], priority: 652, days: 85),
          worklistItem('SYN-75-0290-241-02', flags: ['faster_alternative'], priority: 40, days: 12, next: 'redirect_faster'),
          worklistItem('SYN-75-0290-241-03', flags: ['patient_signal'], priority: 15, days: 40, next: 'wait_for_call', signal: {
            'kind': 'request_redirect', 'toMoCode': '22GN', 'toMoName': dostar, 'comment': 'живу рядом', 'recordedAt': '2026-09-25T10:00:00+00:00',
          }),
          worklistItem('SYN-75-0290-241-04', priority: 5, days: 3),
        ],
        'synthetic': true, 'asOf': '2025-03-31', 'regionKato': '75', 'modelBacked': true,
      },
    });
    await tester.pumpWidget(app(session, const WorklistScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Пациенты'), findsOneWidget);
    expect(find.text('Данные на 31.03.2025'), findsOneWidget, reason: 'срез старше недели — баннер W-States «данные устарели»');
    expect(find.text('Обновить'), findsNothing, reason: 'данные обновляет загрузка витрин — ссылки нет, как в вебе');
    expect(find.text('Сегодня'), findsOneWidget);
    expect(find.text('Риск отказа'), findsOneWidget);
    expect(find.text('Есть быстрее'), findsOneWidget);
    expect(find.text('Запрос пациента'), findsOneWidget);
    expect(find.text('SYN-75-0290-241-04'), findsNothing, reason: 'без флагов и сигнала — не «сегодня»');
    expect(find.textContaining('ждёт 85 дн. · Городской перинатальный центр'), findsOneWidget);
    // сортировка по приоритету: SYN-…-01 первым
    final first = tester.getTopLeft(find.text('SYN-75-0290-241-01'));
    final second = tester.getTopLeft(find.text('SYN-75-0290-241-02'));
    expect(first.dy, lessThan(second.dy));
    await tester.tap(find.text('Все'));
    await tester.pumpAndSettle();
    expect(find.text('SYN-75-0290-241-04'), findsOneWidget);
    expect(find.text('Ожидает решения'), findsOneWidget);
    await tester.tap(find.byTooltip('Поиск пациента'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '241-04');
    await tester.pumpAndSettle();
    expect(find.text('SYN-75-0290-241-04'), findsOneWidget);
    expect(find.text('SYN-75-0290-241-01'), findsNothing);
    await tester.enterText(find.byType(TextField), 'нет-такого');
    await tester.pumpAndSettle();
    expect(find.text('Ничего не найдено'), findsOneWidget, reason: 'пусто по фильтру — W-States');
    await tester.tap(find.text('Сбросить фильтры'));
    await tester.pumpAndSettle();
    expect(find.text('SYN-75-0290-241-01'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('updates are grouped by day inside one card with a coral dot on the unseen doctor answer', (tester) async {
    final session = await apiSession(roles: ['citizen'], api: {'/route/me': citizenRoute()});
    await tester.pumpWidget(app(session, const UpdatesScreen()));
    await tester.pumpAndSettle();
    expect(find.text('20 ФЕВРАЛЯ 2025'), findsOneWidget);
    expect(find.text('19 ФЕВРАЛЯ 2025'), findsOneWidget);
    expect(find.text('17 ФЕВРАЛЯ 2025'), findsOneWidget);
    expect(find.text('Врач предложил Достар Мед'), findsOneWidget);
    expect(find.text('«ближе к дому»'), findsOneWidget);
    expect(find.text('Вы подтвердили, что ждёте'), findsOneWidget);
    expect(find.text('Push-уведомления сейчас не приходят. Новые события появляются здесь.'), findsOneWidget,
        reason: 'без статуса сервисов push считается недоступным — никаких обещаний «после интеграции»');
    expect(tester.takeException(), isNull);
  });

  testWidgets('decisions journal: pills filter by subject, day groups, «совпало»/«иначе» chips and the details sheet', (tester) async {
    final session = await apiSession(roles: ['doctor'], region: '75', api: {
      '/journal/decisions': {
        'items': [
          {'decisionId': 'aaaa-1', 'subject': 'route', 'subjectId': 'SYN-75-08IV-121-01', 'recommended': {'moCode': '031N'}, 'chosen': {'moCode': '22GN'}, 'reason': 'ожидание короче', 'recordedAt': '2025-02-25T12:26:38+00:00'},
          {'decisionId': 'bbbb-2', 'subject': 'referral', 'subjectId': '75.028B.381.11', 'recommended': null, 'chosen': {'moCode': '028B'}, 'reason': 'kc', 'recordedAt': '2025-02-10T12:07:20+00:00'},
          {'decisionId': 'cccc-3', 'subject': 'route', 'subjectId': 'SYN-75-08IV-121-02', 'recommended': {'moCode': '031N'}, 'chosen': {'moCode': '031N'}, 'reason': 'профиль совпадает', 'recordedAt': '2025-02-10T09:00:00+00:00'},
        ],
        'page': 1, 'size': 50, 'total': 3,
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
    expect(find.text('Направление: 028B'), findsOneWidget, reason: 'организация вне справочника — кодом');
    expect(find.text('Оставлен: Региональный военный госпиталь'), findsOneWidget);
    expect(find.text('Совпало'), findsOneWidget);
    expect(find.text('Иначе'), findsNWidgets(2));
    expect(find.textContaining('«ожидание короче»'), findsOneWidget);
    expect(find.text('25 ФЕВРАЛЯ 2025'), findsOneWidget);
    await tester.tap(find.text('Направление'));
    await tester.pumpAndSettle();
    expect(find.text('Региональный военный госпиталь → Достар Мед'), findsNothing);
    await tester.tap(find.text('Все'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Региональный военный госпиталь → Достар Мед'));
    await tester.pumpAndSettle();
    expect(find.text('КЛЮЧ ЗАПИСИ (DECISIONID)'), findsOneWidget);
    expect(find.text('aaaa-1'), findsOneWidget);
    expect(find.textContaining('(22GN)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scribe: consent enables «Начать», the record step offers the microphone, paste fallback and the draft button', (tester) async {
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
    expect(find.text('00:00'), findsOneWidget);
    expect(find.text('RU'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
