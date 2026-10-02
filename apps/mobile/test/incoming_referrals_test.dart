import 'package:darumen/api/almaty_time.dart';
import 'package:darumen/config/env.dart';
import 'package:darumen/screens/incoming_referrals_screen.dart';
import 'package:darumen/widgets/format.dart';
import 'package:darumen/widgets/route/route_journal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/harness.dart';

/// Экран «Входящие направления» принимающей больницы: карточки в серверном порядке, кнопки только из `item.allowed`,
/// фильтры, состояния (пусто, ошибка, нет доступа, учётная запись без больницы), переход к маршруту после
/// подтверждения, тексты в обоих языках и казахский при 1.3 на телефоне 360 dp. Действия — incoming_actions_test.dart.

/// Дата API со сдвигом от сегодняшнего дня по Алматы.
String apiDay(int offset) => formatApiDate(almatyToday().add(Duration(days: offset)));

/// Полное имя направившей больницы, как его отдаёт API.
const senderName = 'Товарищество с ограниченной ответственностью "Казахский ордена "Знак Почета" научно-исследовательский институт глазных болезней"';

/// Строка `GET /journal/referrals/incoming` с осмысленными значениями по умолчанию: пациент согласился, ждут нашего
/// подтверждения.
Map<String, Object?> incomingJson(
  String id, {
  String ref = 'SYN-75-028B-381-01',
  String fromMoCode = '028B',
  String fromMoName = senderName,
  String profileCode = '381',
  bool severe = false,
  String consent = 'accepted',
  bool confirmed = false,
  bool admitted = false,
  bool discharged = false,
  String? status = 'transfer_pending_confirmation',
  String? plannedAt,
  bool overdue = false,
  String? closedReason,
  List<String> allowed = const [],
}) =>
    {
      'decisionId': id,
      'patientRef': ref,
      'fromMoCode': fromMoCode,
      'fromMoName': fromMoName,
      'profileCode': profileCode,
      'reason': 'в принимающей больнице очередь короче',
      'recordedAt': '2026-10-01T09:20:00+00:00',
      'severe': severe,
      'patientConsent': consent,
      'confirmed': confirmed,
      'confirmedAt': confirmed ? '2026-10-01T10:00:00+00:00' : null,
      'discharged': discharged,
      'dischargedAt': discharged ? '2026-10-02T10:00:00+00:00' : null,
      'status': status,
      'plannedAt': plannedAt,
      'admitted': admitted,
      'overdue': overdue,
      'allowed': allowed,
      'closedReason': closedReason,
    };

/// Восемь направлений во всех состояниях, в серверном порядке (тяжёлые первыми, затем новые).
List<Map<String, Object?>> demoIncoming() => [
      incomingJson('d-sev', ref: 'SYN-75-028B-381-03', severe: true, allowed: ['confirm', 'reject']),
      incomingJson('d-pend', ref: 'SYN-75-028B-381-04', consent: 'pending', status: 'transfer_pending_consent'),
      incomingJson('d-sched', ref: 'SYN-75-028B-381-05', confirmed: true, status: 'transferred', plannedAt: apiDay(2), allowed: ['reschedule']),
      incomingJson('d-today', ref: 'SYN-75-028B-381-06', confirmed: true, status: 'transferred', plannedAt: apiDay(0), allowed: ['admit', 'discharge', 'reschedule']),
      incomingJson('d-over',
          ref: 'SYN-75-22GN-152-07',
          fromMoCode: '22GN',
          fromMoName: 'Товарищество с ограниченной ответственностью "Достар Мед"',
          profileCode: '152',
          confirmed: true,
          status: 'transferred',
          plannedAt: apiDay(-5),
          overdue: true,
          allowed: ['admit', 'discharge', 'no_show', 'reschedule']),
      incomingJson('d-adm', ref: 'SYN-75-028B-381-08', confirmed: true, admitted: true, status: 'admitted', plannedAt: apiDay(-1), allowed: ['discharge']),
      incomingJson('d-wd', ref: 'SYN-75-028B-381-09', confirmed: true, status: 'withdrawal_requested', plannedAt: apiDay(3), allowed: ['close']),
      incomingJson('d-done',
          ref: 'SYN-75-028B-381-10', confirmed: true, admitted: true, discharged: true, status: 'closed', closedReason: 'discharged', plannedAt: apiDay(-9)),
    ];

const profilesJson = {
  'items': [
    {'profileCode': '381', 'name': 'Офтальмологические'},
    {'profileCode': '152', 'name': 'Кардиологические'},
  ],
};

/// Ответы API принимающей больницы: список, справочник профилей и колокольчик с [pending] ждущими подтверждения.
Map<String, Object?> receivingApi({List<Object?>? incoming, int pending = 1}) => {
      '/journal/referrals/incoming': incoming ?? demoIncoming(),
      '/refdata/profiles': profilesJson,
      '/journal/notifications/bell': {'pendingIncomingCount': pending},
    };

/// Высокий телефон 360 dp: все карточки строятся сразу (список ленивый).
const tallNarrow = Size(360, 4200);
const tallPhone = Size(390, 4200);

Finder card(String id) => find.byKey(ValueKey('incoming-card-$id'));
Finder inCard(String id, Finder f) => find.descendant(of: card(id), matching: f);

/// Кнопка действия с подписью [label] в карточке [id].
Finder actionButton(String id, String label) =>
    find.ancestor(of: inCard(id, find.text(label)), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));

const ruActions = ['Подтвердить приём', 'Отказать', 'Госпитализирован', 'Выписать', 'Перенести', 'Не пришёл'];

/// Подписи кнопок действий в карточке — в порядке появления.
List<String> actionsOf(WidgetTester tester, String id, {List<String> labels = ruActions}) {
  final found = <(double, String)>[];
  for (final label in labels) {
    final f = actionButton(id, label);
    if (f.evaluate().isNotEmpty) {
      final pos = tester.getTopLeft(f.first);
      found.add((pos.dy * 10000 + pos.dx, label));
    }
  }
  found.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final f in found) f.$2];
}

void main() {
  group('list', () {
    testWidgets('cards in the server order: ref, severe mark, profile and sender, consent chip, status, planned date, overdue', (tester) async {
      final (session, backend) = await demoSession(DemoUser.doctor2, api: receivingApi());
      await pumpScreen(tester, session, const IncomingReferralsScreen(), size: tallPhone);

      final request = backend.calls('GET', '/journal/referrals/incoming').single;
      expect(request.url.queryParameters['includeConfirmed'], 'true', reason: 'как веб: подтверждённые тоже, отбор — фильтрами');
      expect(request.url.queryParameters['moCode'], '22GN', reason: 'своя больница учётной записи — явно, верно для области own и all');

      final ids = ['d-sev', 'd-pend', 'd-sched', 'd-today', 'd-over', 'd-adm', 'd-wd', 'd-done'];
      final tops = [for (final id in ids) tester.getTopLeft(card(id)).dy];
      expect(tops, [...tops]..sort(), reason: 'серверный порядок не пересортирован');

      expect(find.text('Входящие направления'), findsOneWidget);
      expect(find.text('Переводы пациентов из других больниц в вашу · 8 направлений'), findsOneWidget);

      expect(inCard('d-sev', find.text('SYN-75-028B-381-03')), findsOneWidget);
      expect(inCard('d-sev', find.text('Тяжёлый случай')), findsOneWidget);
      expect(inCard('d-sev', find.text('Офтальмологические')), findsOneWidget);
      expect(inCard('d-sev', find.textContaining(shortOrgName(senderName))), findsOneWidget);
      expect(inCard('d-sev', find.textContaining('028B')), findsWidgets);
      expect(inCard('d-sev', find.text(journalMoment('2026-10-01T09:20:00+00:00'))), findsOneWidget);
      expect(inCard('d-sev', find.text('Пациент согласился')), findsOneWidget);
      expect(inCard('d-sev', find.text('Пациент согласился: ждём ответа больницы')), findsOneWidget);
      expect(inCard('d-pend', find.text('Тяжёлый случай')), findsNothing);
      expect(inCard('d-pend', find.text('Ждём согласия пациента')), findsOneWidget);

      expect(inCard('d-sched', find.text('Дата госпитализации: ${routeDate(apiDay(2))}')), findsOneWidget);
      expect(inCard('d-sched', find.text('Дата прошла')), findsNothing);
      expect(inCard('d-over', find.text('Дата прошла')), findsOneWidget);
      expect(inCard('d-over', find.text('Кардиологические')), findsOneWidget);
      expect(inCard('d-done', find.text('Маршрут завершён · Выписан')), findsOneWidget);
      expect(find.textContaining('Подтвердить приём можно после согласия пациента'), findsOneWidget, reason: 'сноска веба');
      expect(tester.takeException(), isNull);
    });

    testWidgets('scope «all» (a database from before the narrowed worklist permission): the own hospital in the query, no 422', (tester) async {
      final (session, backend) = await demoSession(DemoUser.doctor2, api: {
        ...receivingApi(),
        // так отвечает сервер врачу с областью all: без moCode — 422 «Нужна организация»
        '/journal/referrals/incoming': (http.Request request) =>
            request.url.queryParameters['moCode'] == '22GN' ? demoIncoming() : problem(422, 'Нужна организация'),
      });
      await pumpScreen(tester, session, const IncomingReferralsScreen(), size: tallPhone);
      expect(backend.calls('GET', '/journal/referrals/incoming').single.url.queryParameters, containsPair('moCode', '22GN'));
      expect(card('d-sev'), findsOneWidget);
      expect(find.text('Нужна организация'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('buttons exactly from allowed, in the web order; discharged → «Выписан», nothing allowed → «действий нет»', (tester) async {
      final (session, _) = await demoSession(DemoUser.doctor2, api: receivingApi());
      await pumpScreen(tester, session, const IncomingReferralsScreen(), size: tallPhone);

      expect(actionsOf(tester, 'd-sev'), ['Подтвердить приём', 'Отказать']);
      expect(actionsOf(tester, 'd-pend'), isEmpty);
      expect(inCard('d-pend', find.text('действий нет')), findsOneWidget);
      expect(actionsOf(tester, 'd-sched'), ['Перенести']);
      expect(actionsOf(tester, 'd-today'), ['Госпитализирован', 'Выписать', 'Перенести']);
      expect(actionsOf(tester, 'd-over'), ['Госпитализирован', 'Выписать', 'Перенести', 'Не пришёл']);
      expect(actionsOf(tester, 'd-adm'), ['Выписать']);
      expect(actionsOf(tester, 'd-wd'), isEmpty, reason: 'close — не кнопка карточки (Q-18)');
      expect(inCard('d-wd', find.text('Открыть маршрут')), findsOneWidget, reason: 'снять с листа ожидания можно на странице пациента');
      expect(inCard('d-wd', find.text('Пациент просит снять с листа ожидания')), findsOneWidget);
      expect(actionsOf(tester, 'd-done'), isEmpty);
      expect(inCard('d-done', find.text('Выписан')), findsOneWidget);
      expect(inCard('d-done', find.text('действий нет')), findsNothing);

      for (final id in ['d-sev', 'd-today', 'd-over']) {
        for (final label in actionsOf(tester, id)) {
          final button = actionButton(id, label);
          expect(tester.getSize(button).height, greaterThanOrEqualTo(44), reason: 'палец, а не мышь: $id $label');
          expect(tester.widget<ButtonStyleButton>(button).enabled, isTrue);
        }
      }
    });

    testWidgets('Kazakh: the same list with the web Kazakh texts', (tester) async {
      final (session, _) = await demoSession(DemoUser.doctor2, api: receivingApi());
      await pumpScreen(tester, session, const IncomingReferralsScreen(), size: tallPhone, locale: 'kk');
      expect(find.text('Кіріс жолдамалар'), findsOneWidget);
      expect(find.text('Басқа ауруханалардан сіздің ауруханаңызға ауыстырылатын пациенттер · 8 жолдама'), findsOneWidget);
      expect(inCard('d-sev', find.text('Қабылдауды растау')), findsOneWidget);
      expect(inCard('d-sev', find.text('Бас тарту')), findsOneWidget);
      expect(inCard('d-sev', find.text('Ауыр жағдай')), findsOneWidget);
      expect(inCard('d-sev', find.text('Пациент келісті')), findsOneWidget);
      expect(inCard('d-over', find.text('Күн өтті')), findsOneWidget);
      expect(inCard('d-over', find.text('Келмеді')), findsOneWidget);
      expect(inCard('d-pend', find.text('әрекет жоқ')), findsOneWidget);
      expect(inCard('d-done', find.text('Шығарылды')), findsOneWidget);
      expect(find.text('Барлық кезеңдер · 8'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Kazakh at text scale 1.3 on a 360 dp phone: list, filters, search and an open stage sheet without overflow', (tester) async {
      final (session, _) = await demoSession(DemoUser.doctor2, api: receivingApi());
      await pumpScreen(tester, session, const IncomingReferralsScreen(), size: tallNarrow, locale: 'kk', textScale: 1.3);
      expect(tester.takeException(), isNull, reason: 'карточки и фильтры без переполнения');
      await tester.tap(find.byTooltip('Іздеу'));
      await pumpFrames(tester);
      expect(find.text('Пациент, аурухана немесе бейін'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('incoming-stage')));
      await pumpFrames(tester);
      expect(find.text('Мәртебесі'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dark theme: every card state renders from theme tokens without errors', (tester) async {
      final (session, _) = await demoSession(DemoUser.doctor2, api: receivingApi());
      await pumpScreen(tester, session, const IncomingReferralsScreen(), size: tallPhone, dark: true);
      expect(card('d-done'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the standard 360×800 phone in Kazakh at 1.3: the first cards and the filter row fit', (tester) async {
      final (session, _) = await demoSession(DemoUser.doctor2, api: receivingApi());
      await pumpScreen(tester, session, const IncomingReferralsScreen(), size: phoneNarrow, locale: 'kk', textScale: 1.3);
      expect(find.byKey(const ValueKey('incoming-severe')), findsOneWidget);
      expect(card('d-sev'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('states', () {
    testWidgets('no referrals → the web empty state; no filters, no footnote', (tester) async {
      final (session, _) = await demoSession(DemoUser.doctor2, api: receivingApi(incoming: const []));
      await pumpScreen(tester, session, const IncomingReferralsScreen());
      expect(find.text('Входящих направлений нет'), findsOneWidget);
      expect(find.text('Здесь появятся направления из других организаций, как только врач их отправит.'), findsOneWidget);
      expect(find.byKey(const ValueKey('incoming-stage')), findsNothing);
      expect(find.textContaining('Подтвердить приём можно'), findsNothing);
    });

    testWidgets('server error → «Не удалось загрузить данные» with «Повторить»; retry reloads and shows the list', (tester) async {
      final (session, backend) = await demoSession(DemoUser.doctor2, api: {
        ...receivingApi(),
        '/journal/referrals/incoming': problem(503, 'Service Unavailable'),
      });
      await pumpScreen(tester, session, const IncomingReferralsScreen(), size: tallPhone);
      expect(find.text('Не удалось загрузить данные'), findsOneWidget);
      expect(find.textContaining('Сервер недоступен:'), findsNothing, reason: 'никакого сырого текста исключения');
      backend.routes['/journal/referrals/incoming'] = demoIncoming();
      await tester.tap(find.text('Повторить'));
      await pumpFrames(tester);
      expect(backend.calls('GET', '/journal/referrals/incoming'), hasLength(2));
      expect(card('d-sev'), findsOneWidget);
    });

    testWidgets('403 → the no-access state with the server reason', (tester) async {
      final (session, _) = await demoSession(DemoUser.doctor2, api: {
        ...receivingApi(),
        '/journal/referrals/incoming': problem(403, 'Forbidden', detail: 'other_organization'),
      });
      await pumpScreen(tester, session, const IncomingReferralsScreen());
      expect(find.text('Нет доступа к разделу'), findsOneWidget);
      expect(find.text('Это данные другой организации — доступ открыт только к своей.'), findsOneWidget);
    });

    testWidgets('a user without a hospital (admin1, Q-2): «не привязана к больнице», a pointer to the web, no 422 request', (tester) async {
      final opened = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/url_launcher'), (call) async {
        opened.add((call.arguments as Map<Object?, Object?>)['url']! as String);
        return true;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/url_launcher'), null));
      final (session, backend) = await demoSession(DemoUser.admin1, api: receivingApi());
      await pumpScreen(tester, session, const IncomingReferralsScreen());
      expect(find.text('Ваша учётная запись не привязана к больнице'), findsOneWidget);
      expect(find.textContaining('в веб-версии'), findsOneWidget);
      expect(find.text('Открыть веб'), findsOneWidget);
      expect(backend.calls('GET', '/journal/referrals/incoming'), isEmpty, reason: 'без больницы сервер ответил бы 422');
      expect(find.byTooltip('Поиск'), findsNothing);
      await tester.tap(find.text('Открыть веб'));
      await pumpFrames(tester);
      expect(opened, ['${Env.webBase}/doctor/referrals/incoming'], reason: 'прямо на страницу входящих веб-кабинета, где выбирают больницу');
      expect(tester.takeException(), isNull);
    });

    testWidgets('pull to refresh re-reads the list and the bell, keeping the cards on screen', (tester) async {
      final (session, backend) = await demoSession(DemoUser.doctor2, api: receivingApi());
      await pumpScreen(tester, session, const IncomingReferralsScreen(), size: phoneNarrow);
      final bellBefore = backend.calls('GET', '/journal/notifications/bell').length;
      await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
      await pumpFrames(tester);
      expect(backend.calls('GET', '/journal/referrals/incoming'), hasLength(2));
      expect(backend.calls('GET', '/journal/notifications/bell').length, greaterThan(bellBefore));
      expect(card('d-sev'), findsOneWidget);
    });

    testWidgets('a new pending referral on the bell (polling) re-reads the list without pull-to-refresh', (tester) async {
      final (session, backend) = await demoSession(DemoUser.doctor2, api: receivingApi(incoming: const [], pending: 0));
      await pumpScreen(tester, session, const IncomingReferralsScreen(), pollInterval: const Duration(seconds: 5));
      expect(find.text('Входящих направлений нет'), findsOneWidget);
      backend.routes['/journal/notifications/bell'] = {'pendingIncomingCount': 1};
      backend.routes['/journal/referrals/incoming'] = [incomingJson('d-new', ref: 'SYN-75-028B-381-11', allowed: ['confirm', 'reject'])];
      await tester.pump(const Duration(seconds: 5));
      await pumpFrames(tester);
      expect(backend.calls('GET', '/journal/referrals/incoming'), hasLength(2));
      expect(card('d-new'), findsOneWidget);
    });
  });

  group('filters', () {
    testWidgets('stage sheet lists every stage with its count; picking one filters and shows «показаны N из M»', (tester) async {
      final (session, _) = await demoSession(DemoUser.doctor2, api: receivingApi());
      await pumpScreen(tester, session, const IncomingReferralsScreen(), size: tallPhone);
      expect(find.text('Все этапы · 8'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('incoming-stage')));
      await pumpFrames(tester);
      for (final label in [
        'Все этапы · 8',
        'Ждём согласия пациента · 1',
        'Нужно подтвердить приём · 1',
        'Дата назначена · 4',
        'Госпитализирован · 1',
        'Завершено · 1',
      ]) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      await tester.tap(find.text('Дата назначена · 4'));
      await pumpFrames(tester);
      expect(find.text('показаны 4 из 8'), findsOneWidget);
      expect(card('d-sched'), findsOneWidget);
      expect(card('d-sev'), findsNothing);
      expect(card('d-done'), findsNothing);
    });

    testWidgets('«Только тяжёлые · N» toggles; search by sender, profile or ref; nothing found → reset', (tester) async {
      final (session, _) = await demoSession(DemoUser.doctor2, api: receivingApi());
      await pumpScreen(tester, session, const IncomingReferralsScreen(), size: tallPhone);
      await tester.tap(find.text('Только тяжёлые · 1'));
      await pumpFrames(tester);
      expect(card('d-sev'), findsOneWidget);
      expect(card('d-pend'), findsNothing);
      await tester.tap(find.text('Только тяжёлые · 1'));
      await pumpFrames(tester);
      expect(card('d-pend'), findsOneWidget);

      await tester.tap(find.byTooltip('Поиск'));
      await pumpFrames(tester);
      await tester.enterText(find.byType(TextField), 'достар');
      await pumpFrames(tester);
      expect(card('d-over'), findsOneWidget);
      expect(card('d-sev'), findsNothing);
      await tester.enterText(find.byType(TextField), 'КАРДИО');
      await pumpFrames(tester);
      expect(card('d-over'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '381-09');
      await pumpFrames(tester);
      expect(card('d-wd'), findsOneWidget);
      expect(find.text('показаны 1 из 8'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'нет такого');
      await pumpFrames(tester);
      expect(find.text('Ничего не найдено'), findsOneWidget);
      await tester.tap(find.text('Сбросить фильтры'));
      await pumpFrames(tester);
      expect(card('d-sev'), findsOneWidget);
      expect(card('d-done'), findsOneWidget);
    });
  });

  group('navigation', () {
    testWidgets('a confirmed referral opens the patient route; an unconfirmed ref is not a link', (tester) async {
      final (session, _) = await demoSession(DemoUser.doctor2, api: receivingApi());
      final router = await pumpRouterApp(tester, session, location: '/doctor/incoming', size: tallPhone);
      await tester.tap(find.text('SYN-75-028B-381-03'));
      await pumpFrames(tester);
      expect(router.state.uri.path, '/doctor/incoming', reason: 'до подтверждения маршрут принимающей больнице не открыт');
      await tester.tap(find.text('SYN-75-028B-381-05'));
      await pumpFrames(tester);
      expect(router.state.uri.path, '/doctor/patients/SYN-75-028B-381-05');
    });

    testWidgets('«Открыть маршрут» on a referral the patient wants to leave opens the route, where it is closed (Q-18)', (tester) async {
      final (session, _) = await demoSession(DemoUser.doctor2, api: receivingApi());
      final router = await pumpRouterApp(tester, session, location: '/doctor/incoming', size: tallPhone);
      await tester.tap(inCard('d-wd', find.text('Открыть маршрут')));
      await pumpFrames(tester);
      expect(router.state.uri.path, '/doctor/patients/SYN-75-028B-381-09');
    });
  });
}
