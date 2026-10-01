import 'dart:async';

import 'package:darumen/screens/patient_route_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'doctor_route_fixture.dart';
import 'support/harness.dart';

/// Действия врача на маршруте (поток 4a): оставить, перевести (с отметкой тяжести), отменить перевод, снять с листа
/// ожидания. Что уходит на сервер, свежий ключ на каждое нажатие, блокировка кнопок на время запроса, перечитывание
/// после успеха и после 409, сообщение 422 у поля причины, «Сервер недоступен» только при сбое связи.
const tall = Size(390, 3200);

/// Сервер маршрута с состоянием: GET отдаёт [route], POST на действие отвечает `reply` и меняет маршрут на `after`
/// (если задан).
class RouteServer {
  RouteServer(this.route);

  Map<String, dynamic> route;

  Map<String, Object?> api(String action, Object? Function(http.Request request) reply, {Map<String, dynamic>? after}) => {
        routePath: (http.Request _) => route,
        'POST $routePath/$action': (http.Request request) {
          final answer = reply(request);
          if (after != null) {
            route = after;
          }
          return answer;
        },
      };
}

Future<DemoBackend> pumpActions(WidgetTester tester, Map<String, Object?> api) async {
  final (session, backend) = await demoSession(DemoUser.doctor1, api: api);
  await pumpScreen(tester, session, const PatientRouteScreen(patientRef: routeRef), size: tall);
  return backend;
}

Future<void> typeReason(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
}

void main() {
  testWidgets('«Оставить в текущей»: без причины — подсказка у поля и ничего не уходит; с причиной — POST keep с ключом и перечитывание', (tester) async {
    final server = RouteServer(doctorRoute(signals: [requestSignal()]));
    final backend = await pumpActions(tester, server.api('keep', (_) => recorded('keep-1'), after: doctorRoute(status: 'kept')));
    await tester.tap(find.text('Оставить в текущей'));
    await pumpFrames(tester);
    expect(find.text('Укажите причину перенаправления'), findsOneWidget);
    expect(backend.calls('POST', '$routePath/keep'), isEmpty);

    await typeReason(tester, '  профиль требует этой клиники  ');
    expect(find.text('Укажите причину перенаправления'), findsNothing, reason: 'подсказка уходит, когда врач пишет');
    await tester.tap(find.text('Оставить в текущей'));
    await pumpFrames(tester);
    final post = backend.calls('POST', '$routePath/keep').single;
    expect(backend.lastBody('POST', '$routePath/keep'), {'reason': 'профиль требует этой клиники'});
    expect(post.headers['Idempotency-Key'], matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(find.text('Решение записано в журнал'), findsOneWidget);
    expect(backend.calls('GET', routePath), hasLength(2), reason: 'успех — маршрут перечитан');
    expect(find.text('Оставлен в своей больнице'), findsWidgets, reason: 'новый статус после перечитывания');
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty, reason: 'форма очищена');
    expect(tester.takeException(), isNull);
  });

  testWidgets('«Перевести в выбранную» с отметкой тяжести: тело {toMoCode, reason, severe: true}, затем карточка «Перевод»', (tester) async {
    final server = RouteServer(doctorRoute());
    final backend = await pumpActions(
      tester,
      server.api('redirect', (_) => recorded('red-1'),
          after: doctorRoute(status: 'transfer_pending_consent', allowed: ['cancel_transfer'], transfer: transferTo(toMoCode: '028S', toMoName: 'АО "Казахский НИИ онкологии"', severe: true))),
    );
    await tester.tap(find.textContaining('Казахский научно-исследовательский институт онкологии'));
    await pumpFrames(tester);
    await tester.tap(find.byType(SwitchListTile));
    await pumpFrames(tester);
    await typeReason(tester, 'там раньше дата');
    await tester.tap(find.text('Перевести в выбранную'));
    await pumpFrames(tester);
    expect(backend.lastBody('POST', '$routePath/redirect'), {'toMoCode': '028S', 'reason': 'там раньше дата', 'severe': true});
    expect(find.text('Перенаправление записано в журнал'), findsOneWidget);
    expect(find.text('ПЕРЕВОД'), findsOneWidget);
    expect(find.text('Перевод предложен: ждём согласия пациента'), findsWidgets);
    expect(find.text('Отменить перевод'), findsOneWidget);
    expect(find.text('Перевести в выбранную'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('больница из запроса пациента, которой нет среди альтернатив, тоже предлагается (Q-5); без тяжести severe не уходит', (tester) async {
    final server = RouteServer(doctorRoute(signals: [requestSignal(toMoCode: '22GN', toMoName: dostar, comment: null)]));
    final backend = await pumpActions(tester, server.api('redirect', (_) => recorded()));
    expect(find.text('Достар Мед'), findsOneWidget);
    expect(find.text('Просит пациент'), findsOneWidget);
    await tester.tap(find.text('Достар Мед'));
    await pumpFrames(tester);
    await typeReason(tester, 'просьба пациента');
    await tester.tap(find.text('Перевести в выбранную'));
    await pumpFrames(tester);
    expect(backend.lastBody('POST', '$routePath/redirect'), {'toMoCode': '22GN', 'reason': 'просьба пациента'});
    expect(tester.takeException(), isNull);
  });

  testWidgets('409: сначала маршрут перечитан, потом текст сервера «заголовок — пояснение»; карточка решения уходит', (tester) async {
    final server = RouteServer(doctorRoute());
    final backend = await pumpActions(
      tester,
      server.api(
        'keep',
        (_) => problem(409, 'Ждём ответа пациента', detail: 'по маршруту есть перевод, на который пациент ещё не ответил', stateCode: 'transfer_pending_consent'),
        after: doctorRoute(status: 'transfer_pending_consent', allowed: ['cancel_transfer'], transfer: transferTo()),
      ),
    );
    await typeReason(tester, 'оставляем');
    await tester.tap(find.text('Оставить в текущей'));
    await pumpFrames(tester);
    expect(backend.calls('GET', routePath), hasLength(2));
    expect(find.text('Ждём ответа пациента — по маршруту есть перевод, на который пациент ещё не ответил'), findsOneWidget);
    expect(find.text('Оставить в текущей'), findsNothing);
    expect(find.text('Отменить перевод'), findsOneWidget);
    expect(find.textContaining('Сервер недоступен'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('409 «Эту больницу предлагать нельзя» при переводе — текст сервера после перечитывания', (tester) async {
    final server = RouteServer(doctorRoute());
    await pumpActions(
      tester,
      server.api('redirect', (_) => problem(409, 'Эту больницу предлагать нельзя', detail: 'эта больница уже отказала в приёме по этому направлению'),
          after: doctorRoute(blocked: ['031N'])),
    );
    await tester.tap(find.textContaining('Региональный военный госпиталь'));
    await pumpFrames(tester);
    await typeReason(tester, 'быстрее');
    await tester.tap(find.text('Перевести в выбранную'));
    await pumpFrames(tester);
    expect(find.text('Эту больницу предлагать нельзя — эта больница уже отказала в приёме по этому направлению'), findsOneWidget);
    expect(find.textContaining('Региональный военный госпиталь'), findsNothing, reason: 'после перечитывания отказавшая больница ушла из списка');
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Перевести в выбранную')).onPressed, isNull, reason: 'выбор исчезнувшей больницы снят');
    expect(tester.takeException(), isNull);
  });

  testWidgets('422: сообщение сервера под полем причины, без снекбара; следующее нажатие — новый ключ', (tester) async {
    final server = RouteServer(doctorRoute());
    final backend = await pumpActions(
      tester,
      server.api('keep', (_) => problem(422, 'Ошибка валидации', errors: {'reason': ['обязательное поле']})),
    );
    await typeReason(tester, 'x');
    await tester.tap(find.text('Оставить в текущей'));
    await pumpFrames(tester);
    expect(find.text('обязательное поле'), findsOneWidget);
    expect(find.textContaining('Ошибка валидации'), findsNothing);
    await tester.tap(find.text('Оставить в текущей'));
    await pumpFrames(tester);
    final keys = backend.calls('POST', '$routePath/keep').map((r) => r.headers['Idempotency-Key']).toList();
    expect(keys, hasLength(2));
    expect(keys.toSet(), hasLength(2), reason: 'один ключ — одно нажатие');
    expect(tester.takeException(), isNull);
  });

  testWidgets('двойное нажатие не создаёт второй записи: пока запрос идёт, кнопки решения выключены', (tester) async {
    final gate = Completer<http.Response>();
    final server = RouteServer(doctorRoute());
    final backend = await pumpActions(tester, server.api('keep', (_) => gate.future, after: doctorRoute(status: 'kept')));
    await typeReason(tester, 'оставляем');
    await tester.tap(find.text('Оставить в текущей'));
    await tester.pump();
    await tester.tap(find.text('Оставить в текущей'), warnIfMissed: false);
    await tester.pump();
    expect(backend.calls('POST', '$routePath/keep'), hasLength(1));
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Оставить в текущей')).onPressed, isNull);
    gate.complete(recorded());
    await pumpFrames(tester);
    expect(backend.calls('POST', '$routePath/keep'), hasLength(1));
    expect(find.text('Решение записано в журнал'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('сбой связи — «Сервер недоступен. Повторите попытку позже.», причина остаётся в поле', (tester) async {
    final server = RouteServer(doctorRoute());
    await pumpActions(tester, server.api('keep', (_) => throw http.ClientException('offline')));
    await typeReason(tester, 'оставляем');
    await tester.tap(find.text('Оставить в текущей'));
    await pumpFrames(tester);
    expect(find.text('Сервер недоступен. Повторите попытку позже.'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'оставляем');
    expect(tester.takeException(), isNull);
  });

  testWidgets('«Отменить перевод»: без причины — «Укажите причину»; с причиной — POST cancel-transfer и «Перевод отменён»', (tester) async {
    final server = RouteServer(doctorRoute(status: 'transfer_pending_confirmation', allowed: ['cancel_transfer'], transfer: transferTo()));
    final backend = await pumpActions(tester, server.api('cancel-transfer', (_) => recorded(), after: doctorRoute(status: 'kept')));
    await tester.tap(find.text('Отменить перевод'));
    await pumpFrames(tester);
    expect(find.text('Укажите причину'), findsOneWidget);
    expect(backend.calls('POST', '$routePath/cancel-transfer'), isEmpty);
    await typeReason(tester, 'пациент передумал');
    await tester.tap(find.text('Отменить перевод'));
    await pumpFrames(tester);
    expect(backend.lastBody('POST', '$routePath/cancel-transfer'), {'reason': 'пациент передумал'});
    expect(find.text('Перевод отменён'), findsOneWidget);
    expect(find.text('ОСТАВИТЬ ИЛИ ПЕРЕВЕСТИ'), findsOneWidget, reason: 'после отмены решение снова доступно');
    expect(tester.takeException(), isNull);
  });

  testWidgets('просьба пациента снять с листа: запрос с комментарием, «Снять с листа ожидания» — POST close', (tester) async {
    final server = RouteServer(doctorRoute(
      status: 'withdrawal_requested',
      allowed: ['close'],
      signals: [
        {'decisionId': 'w', 'recordedAt': '2026-09-26T10:00:00+00:00', 'kind': 'withdraw', 'comment': 'уже прооперировали', 'open': true},
      ],
    ));
    final backend = await pumpActions(tester, server.api('close', (_) => recorded(), after: doctorRoute(status: 'closed', allowed: const [], closedReason: 'withdrawn')));
    expect(find.text('Пациент просит снять с листа ожидания'), findsWidgets);
    expect(find.textContaining('Пациент отказался от ожидания — «уже прооперировали»'), findsOneWidget);
    expect(find.text('ПРИЧИНА (НАПРИМЕР: ПОДТВЕРДИЛИ ПО ТЕЛЕФОНУ) (ОБЯЗАТЕЛЬНО)'), findsOneWidget);
    await typeReason(tester, 'подтвердили по телефону');
    await tester.tap(find.text('Снять с листа ожидания'));
    await pumpFrames(tester);
    expect(backend.lastBody('POST', '$routePath/close'), {'reason': 'подтвердили по телефону'});
    expect(find.text('Пациент снят с листа ожидания'), findsOneWidget);
    expect(find.text('Маршрут завершён · Снят по просьбе пациента'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('принимающая больница после подтверждения закрывает маршрут по просьбе пациента прямо на маршруте (Q-18)', (tester) async {
    final server = RouteServer(doctorRoute(
      status: 'withdrawal_requested',
      allowed: ['close'],
      side: 'receiving',
      transfer: transferTo(plannedAt: '2026-10-03'),
      signals: [
        {'decisionId': 't', 'recordedAt': '2026-09-27T10:00:00+00:00', 'kind': 'treated_elsewhere', 'open': true},
      ],
    ));
    final backend = await pumpActions(tester, server.api('close', (_) => recorded(), after: doctorRoute(status: 'closed', allowed: const [], side: 'receiving', closedReason: 'treated_elsewhere')));
    expect(find.text('Пациент уже лечился в другом месте · 27.09.2026'), findsOneWidget);
    expect(find.text('Открыть входящие'), findsOneWidget);
    expect(find.textContaining('Перевод в '), findsNothing, reason: 'при просьбе снять перевод не повторяется');
    await typeReason(tester, 'подтвердили по телефону');
    await tester.tap(find.text('Снять с листа ожидания'));
    await pumpFrames(tester);
    expect(backend.lastBody('POST', '$routePath/close'), {'reason': 'подтвердили по телефону'});
    expect(find.text('Маршрут завершён · Лечился в другом месте'), findsOneWidget);
    expect(find.text('Открыть входящие'), findsNothing, reason: 'завершённый маршрут — входящие не нужны');
    expect(tester.takeException(), isNull);
  });
}
