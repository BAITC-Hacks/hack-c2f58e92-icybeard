import 'dart:async';

import 'package:darumen/screens/route_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'citizen_support.dart';
import 'support/harness.dart';

/// «Мой путь»: карточка состояния маршрута (F1–F6) с кнопками только из `progress.allowed`, что уходит на сервер,
/// 409 (сначала перечитать, потом текст сервера), двойное нажатие, листы подтверждения (Q5) и необязательная причина
/// отказа (Q7). Разделы ниже карточки — в citizen_route_sections_test.dart.
const consentPath = '/route/me/consent';
const signalsPath = '/route/me/signals';

/// «Мой путь» гражданина на высоком телефоне; [route] — ответ `GET /route/me` (функция — последовательность ответов).
Future<DemoBackend> pumpRoute(
  WidgetTester tester,
  Object route, {
  Map<String, Object?> api = const {},
  String locale = 'ru',
  double textScale = 1,
  Size size = phoneTall,
  bool dark = false,
}) async {
  final (session, backend) = await demoSession(DemoUser.citizen1, api: {'/route/me': route, ...api}, locale: locale);
  await pumpScreen(tester, session, const RouteScreen(), locale: locale, textScale: textScale, size: size, dark: dark);
  return backend;
}

/// Тап по кнопке действия с подписью [label] (первой на экране или, с [last], — в открытом листе) и кадры до ответа
/// сервера.
Future<void> tapAction(WidgetTester tester, String label, {bool last = false}) async {
  final finder = last ? find.text(label).last : find.text(label).first;
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await pumpFrames(tester);
}

void main() {
  group('F1 transfer proposed', () {
    testWidgets('the state card under the head card: title, body, doctor reason, three actions from allowed', (tester) async {
      await pumpRoute(tester, routeMe());
      expect(find.text('Ваша больница'.toUpperCase()), findsOneWidget);
      expect(find.text('Перевод'), findsNothing, reason: 'с карточкой действия список этапов свёрнут — кнопки остаются на экране');
      await tapAction(tester, '6 этапов · 3 пройдено');
      expect(find.text('Перевод'), findsOneWidget, reason: 'шестой этап — заголовок сервера в вертикальном списке');
      expect(find.text('Врач предлагает перевод'), findsOneWidget);
      expect(find.textContaining('В больницу: Региональный военный госпиталь'), findsOneWidget);
      expect(find.text('Причина врача: «ozhidanie koroche, profil sovpadaet»'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Согласен'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Отказаться'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Больше не нужно'), findsOneWidget);
      expect(find.text('Вы ещё ждёте госпитализацию?'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('«Согласен» sends the transfer decision with a fresh key, reloads the route and confirms', (tester) async {
      final backend = await pumpRoute(tester, routeMe(), api: {'POST $consentPath': recorded()});
      final before = backend.calls('GET', '/api/v1/route/me').length;
      await tapAction(tester, 'Согласен');
      expect(backend.calls('POST', consentPath), hasLength(1));
      expect(backend.lastBody('POST', consentPath), {'decisionId': transferId, 'accepted': true});
      expect(backend.calls('POST', consentPath).single.headers['Idempotency-Key'], isNotEmpty);
      expect(backend.calls('POST', consentPath).single.url.queryParameters['regionKato'], '75');
      expect(backend.calls('GET', '/api/v1/route/me').length, before + 1, reason: 'после успеха маршрут перечитан');
      expect(find.text('Вы согласились на перевод'), findsOneWidget, reason: 'один термин «перевод» (Q19)');
    });

    testWidgets('a double tap writes one record: the buttons are disabled while the answer is in flight', (tester) async {
      final reply = Completer<http.Response>();
      final backend = await pumpRoute(tester, routeMe(), api: {'POST $consentPath': (_) => reply.future});
      await tester.ensureVisible(find.text('Согласен'));
      await tester.pump();
      await tester.tap(find.text('Согласен'));
      await tester.pump();
      await tester.tap(find.text('Согласен'), warnIfMissed: false);
      await tester.pump();
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Согласен')).onPressed, isNull);
      expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Отказаться')).onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget, reason: 'спиннер только у нажатой кнопки');
      reply.complete(recorded());
      await pumpFrames(tester);
      expect(backend.calls('POST', consentPath), hasLength(1));
    });

    testWidgets('«Отказаться» asks first, with an optional reason; the reason goes into the body', (tester) async {
      final backend = await pumpRoute(tester, routeMe(), api: {'POST $consentPath': recorded()});
      await tapAction(tester, 'Отказаться');
      expect(find.text('Отказаться от перевода?'), findsOneWidget);
      expect(find.textContaining('больше не предложат'), findsOneWidget);
      await tapAction(tester, 'Отмена');
      expect(backend.calls('POST', consentPath), isEmpty, reason: '«Отмена» ничего не отправляет');

      await tapAction(tester, 'Отказаться');
      await tester.enterText(find.byType(TextField), '  далеко ездить  ');
      await tapAction(tester, 'Отказаться', last: true);
      expect(backend.lastBody('POST', consentPath), {'decisionId': transferId, 'accepted': false, 'reason': 'далеко ездить'});
      expect(find.text('Вы отказались от перевода'), findsOneWidget);
    });

    testWidgets('a decline without a reason sends no reason', (tester) async {
      final backend = await pumpRoute(tester, routeMe(), api: {'POST $consentPath': recorded()});
      await tapAction(tester, 'Отказаться');
      await tapAction(tester, 'Отказаться', last: true);
      expect(backend.lastBody('POST', consentPath), {'decisionId': transferId, 'accepted': false});
    });

    testWidgets('409: the route is reloaded first, then the server title and detail are shown', (tester) async {
      var reads = 0;
      final backend = await pumpRoute(
        tester,
        (_) => ++reads == 1 ? json(routeMe()) : json(routeMe(status: 'transfer_pending_confirmation')),
        api: {'POST $consentPath': problem(409, 'Ждём ответа больницы', detail: 'пациент уже дал согласие', stateCode: 'transfer_pending_confirmation')},
      );
      await tapAction(tester, 'Согласен');
      expect(backend.calls('GET', '/api/v1/route/me'), hasLength(2));
      expect(find.text('Ждём ответа больницы — пациент уже дал согласие'), findsOneWidget);
      expect(find.text('Отозвать согласие'), findsOneWidget, reason: 'на экране уже новое состояние');
      expect(find.text('Согласен'), findsNothing);
      expect(find.textContaining('Сервер недоступен'), findsNothing);
    });

    testWidgets('a network failure says «Сервер недоступен» without the exception text', (tester) async {
      await pumpRoute(tester, routeMe(), api: {'POST $consentPath': (_) => throw http.ClientException('Connection refused')});
      await tapAction(tester, 'Согласен');
      expect(find.text('Сервер недоступен. Повторите попытку позже.'), findsOneWidget);
      expect(find.textContaining('Connection refused'), findsNothing);
    });

    testWidgets('«Больше не нужно» asks to confirm and sends withdraw with the optional comment', (tester) async {
      final backend = await pumpRoute(tester, routeMe(), api: {'POST $signalsPath': recorded()});
      await tapAction(tester, 'Больше не нужно');
      expect(find.text('Снять вас с листа ожидания?'), findsOneWidget);
      expect(find.text('Больница подтвердит снятие. Если передумали, нажмите «Я ещё жду».'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'лечусь в другом городе');
      await tapAction(tester, 'Больше не нужно', last: true);
      expect(backend.lastBody('POST', signalsPath), {'kind': 'withdraw', 'comment': 'лечусь в другом городе'});
      expect(find.text('Ответ записан, врач его увидит'), findsOneWidget);
    });
  });

  group('F2–F6', () {
    testWidgets('F2 waiting for the hospital: «Отозвать согласие» confirms and withdraws the consent', (tester) async {
      final backend = await pumpRoute(tester, routeMe(status: 'transfer_pending_confirmation'), api: {'POST $consentPath': recorded()});
      expect(find.text('Ждём ответа больницы'), findsOneWidget);
      expect(find.textContaining('подтвердит приём и назначит дату'), findsOneWidget);
      expect(find.text('Согласен'), findsNothing);
      expect(find.text('Причина врача: «ozhidanie koroche, profil sovpadaet»'), findsNothing, reason: 'причина — только на предложении');
      await tapAction(tester, 'Отозвать согласие');
      expect(find.text('Отозвать согласие?'), findsOneWidget);
      await tapAction(tester, 'Отозвать согласие', last: true);
      expect(backend.lastBody('POST', consentPath), {'decisionId': transferId, 'accepted': false});
      expect(find.text('Согласие отозвано'), findsOneWidget);
    });

    testWidgets('F3 transferred: the date, the overdue note, «Отказаться от госпитализации»; no forecast and no «Где быстрее» (Q18)', (tester) async {
      final backend = await pumpRoute(
        tester,
        routeMe(status: 'transferred', overdue: true, transfer: {'plannedAt': '2026-10-05', 'confirmedAt': '2026-10-01T09:00:00+00:00'}, alternatives: []),
        api: {'POST $signalsPath': recorded()},
      );
      expect(find.text('Дата госпитализации назначена'), findsWidgets);
      expect(find.textContaining('ждёт вас 05.10.2026.'), findsOneWidget);
      expect(find.text('Дата прошла. Если вы не попали в больницу, свяжитесь с ней.'), findsOneWidget);
      expect(find.text('Прогноз'.toUpperCase()), findsNothing);
      expect(find.text('Где быстрее'.toUpperCase()), findsNothing);
      await tapAction(tester, 'Отказаться от госпитализации');
      expect(find.text('Отказаться от госпитализации?'), findsOneWidget);
      await tapAction(tester, 'Отказаться от госпитализации', last: true);
      expect(backend.lastBody('POST', signalsPath), {'kind': 'withdraw'});
    });

    testWidgets('F4 admitted: «Вы в больнице» with the hospital, no buttons anywhere', (tester) async {
      await pumpRoute(tester, routeMe(status: 'admitted', alternatives: []));
      expect(find.text('Вы в больнице'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('F5 withdrawal requested: «Я ещё жду» sends still_waiting without a confirmation', (tester) async {
      final backend = await pumpRoute(tester, routeMe(status: 'withdrawal_requested'), api: {'POST $signalsPath': recorded()});
      expect(find.text('Вы попросили снять вас с листа ожидания'), findsOneWidget);
      expect(find.text('Больше не нужно'), findsNothing, reason: 'снятие уже запрошено');
      await tapAction(tester, 'Я ещё жду');
      expect(backend.lastBody('POST', signalsPath), {'kind': 'still_waiting'});
      expect(find.text('Ответ записан, врач его увидит'), findsOneWidget);
    });

    testWidgets('F6 closed after discharge: «Маршрут завершён» in the citizen voice, no actions, no forecast', (tester) async {
      await pumpRoute(tester, routeMe(status: 'closed', closedReason: 'discharged', alternatives: []));
      expect(find.text('Маршрут завершён'), findsOneWidget);
      expect(find.textContaining('Вы выписаны: Региональный военный госпиталь'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.text('Прогноз'.toUpperCase()), findsNothing);
    });
  });

  group('waiting and kept', () {
    testWidgets('nothing to answer: no action card, and the vertical stage list starts open', (tester) async {
      await pumpRoute(tester, routeMe(status: 'waiting', decisions: [], signals: []));
      expect(find.text('Внесено в лист ожидания'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.text('Вы ещё ждёте госпитализацию?'), findsNothing);
    });

    testWidgets('validation card: «Да, жду» and «Уже лечился» go at once, «Больше не нужно» asks first', (tester) async {
      final backend = await pumpRoute(tester, routeMe(status: 'waiting', validationDue: true, decisions: [], signals: []), api: {'POST $signalsPath': recorded()});
      expect(find.text('Вы ещё ждёте госпитализацию?'), findsOneWidget);
      await tapAction(tester, 'Да, жду');
      expect(backend.lastBody('POST', signalsPath), {'kind': 'still_waiting'});
      await tapAction(tester, 'Уже лечился в другом месте');
      expect(backend.lastBody('POST', signalsPath), {'kind': 'treated_elsewhere'});
      expect(backend.calls('POST', signalsPath), hasLength(2));
      await tapAction(tester, 'Больше не нужно');
      expect(find.text('Снять вас с листа ожидания?'), findsOneWidget);
    });

    testWidgets('doctor answer: kept with the reason, «Понятно» hides it for good, «Сравнить ожидание» is offered', (tester) async {
      await pumpRoute(tester, routeMe(status: 'kept', decisions: [decision('d-keep', kind: 'keep')], signals: [signal('still_waiting')]));
      expect(find.text('Врач оставил в текущей организации'), findsOneWidget);
      expect(find.text('Причина врача: «ближе к дому»'), findsOneWidget);
      expect(find.text('Сравнить ожидание'), findsOneWidget);
      await tapAction(tester, 'Понятно');
      expect(find.text('Врач оставил в текущей организации'), findsNothing);
    });

    testWidgets('doctor redirect that the citizen declined: the alternative wait and the consent chip', (tester) async {
      await pumpRoute(tester, routeMe(status: 'kept', decisions: [decision('d-red', toMoCode: '22GN', consent: 'declined')], signals: []));
      expect(find.text('Врач предложил другую организацию'), findsOneWidget);
      expect(find.textContaining('Достар Мед · ≈ 4 дн. — половина ждёт не дольше'), findsOneWidget);
      expect(find.text('Вы отказались от перевода'), findsOneWidget);
    });
  });

  testWidgets('no route in the region (404): the not-found state with a way to «Сколько ждут»', (tester) async {
    await pumpRoute(tester, problem(404, 'Нет очередей в регионе'));
    expect(find.text('Маршрут не найден: в регионе нет активных очередей'), findsOneWidget);
    expect(find.text('Сколько ждут'), findsOneWidget);
    expect(find.text('Не удалось загрузить данные'), findsNothing);
  });

  testWidgets('a server failure while loading shows the load error with «Повторить»', (tester) async {
    var reads = 0;
    await pumpRoute(tester, (_) => ++reads == 1 ? problem(503, 'Service Unavailable') : json(routeMe()));
    expect(find.text('Не удалось загрузить данные'), findsOneWidget);
    await tapAction(tester, 'Повторить');
    expect(find.text('Врач предлагает перевод'), findsOneWidget);
  });

  testWidgets('the dark theme draws the state card, the scribe card and the sections without errors', (tester) async {
    await pumpRoute(tester, routeMe(), api: {'/route/me/scribe': [scribeConsent('req-d', 'pending')]}, dark: true);
    expect(find.text('Врач предлагает перевод'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Решения и запросы'), 300);
    expect(tester.takeException(), isNull);
  });

  testWidgets('kazakh at 1.3 on a 360 dp phone: every state card fits', (tester) async {
    for (final route in [
      routeMe(),
      routeMe(status: 'transfer_pending_confirmation'),
      routeMe(status: 'transferred', overdue: true, transfer: {'plannedAt': '2026-10-05'}, alternatives: []),
      routeMe(status: 'withdrawal_requested'),
      routeMe(status: 'closed', closedReason: 'no_show', alternatives: []),
      routeMe(status: 'waiting', validationDue: true, decisions: [], signals: []),
    ]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpRoute(tester, route, locale: 'kk', textScale: 1.3, size: phoneNarrow);
      expect(tester.takeException(), isNull, reason: (route['progress'] as Map)['status'] as String);
    }
    expect(find.text('Емдеуге жатқызуды әлі күтіп отырсыз ба?'), findsOneWidget);
  });
}
