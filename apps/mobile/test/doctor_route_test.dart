import 'package:darumen/screens/patient_route_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'doctor_route_fixture.dart';
import 'support/harness.dart';

/// Маршрут пациента для врача (/doctor/patients/:ref): шапка с больницей, статусом и приоритетом, «Текущая больница»
/// с риском отказа словами и факторами прогноза, карточка решения или карточка перевода — только по progress.allowed,
/// этапы, журнал голосом персонала, анализы, ссылки на скрайб, входящие и ассистент нового направления.
const tall = Size(390, 3200);

Future<void> pumpRoute(WidgetTester tester, Map<String, dynamic> route, {String locale = 'ru', double textScale = 1, Size size = tall, DemoUser user = DemoUser.doctor1}) async {
  final (session, _) = await demoSession(user, locale: locale, api: {routePath: route});
  await pumpScreen(tester, session, const PatientRouteScreen(patientRef: routeRef), locale: locale, textScale: textScale, size: size);
}

void main() {
  testWidgets('врач чужой больницы: шапка, «Текущая больница», «Что сделать», журнал и сноска; решений нет', (tester) async {
    await pumpRoute(tester, fixtureMap('route-doctor'));
    expect(find.text('Маршрут пациента'), findsOneWidget);
    expect(find.text('ПАЦИЕНТ'), findsOneWidget);
    expect(find.text(routeRef), findsOneWidget);
    expect(find.byTooltip('Высокий приоритет · 9 из 10'), findsOneWidget);
    expect(find.text('Риск отказа'), findsOneWidget);
    expect(find.text('Есть быстрее'), findsOneWidget);
    expect(find.text('> 30 дней'), findsOneWidget);
    expect(find.text('В листе ожидания'), findsWidgets, reason: 'строка статуса маршрута');
    expect(find.text('Городская больница скорой неотложной помощи'), findsOneWidget, reason: 'больница — коротким именем');
    expect(find.text('Травматологические для взрослых · 224E'), findsOneWidget);
    expect(find.text('01.01.2025'), findsOneWidget, reason: 'в листе ожидания с');
    expect(find.text('89 дн.'), findsOneWidget);
    expect(find.text('9 из 10'), findsOneWidget);
    expect(find.text('ТЕКУЩАЯ БОЛЬНИЦА'), findsOneWidget);
    expect(find.text('≈ 23 дн.'), findsOneWidget);
    expect(find.text('≈ 54 дн.'), findsOneWidget);
    expect(find.text('выше среднего'), findsOneWidget, reason: 'больницы не было в обучении: риск словами, 39 % — выше среднего');
    expect(find.text('ЧТО СДЕЛАТЬ'), findsOneWidget);
    expect(find.text('предложить перенаправление в организацию с меньшим ожиданием'), findsOneWidget);
    expect(find.textContaining('Обоснование: очередь 37 направлений'), findsOneWidget);
    expect(find.text('Оставить в текущей'), findsNothing, reason: 'allowed пуст — кнопок решения нет');
    expect(find.text('Записать приём'), findsNothing, reason: 'врач не сторона маршрута');
    expect(find.text('ПЕРЕВОД'), findsOneWidget, reason: 'вместо решения — карточка состояния');
    expect(find.text('Решения и запросы'), findsOneWidget);
    expect(find.text('Решений пока нет.'), findsOneWidget);
    expect(find.textContaining('Синтетический маршрут на реальных очередях · данные на 31.03.2025'), findsOneWidget);

    await tester.tap(find.text('Из чего сложился прогноз'));
    await pumpFrames(tester);
    expect(find.text('Направляет другая организация'), findsOneWidget);
    expect(find.text('Эта больница'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('«Оставить или перевести»: запрос пациента, последняя попытка, «хочет остаться», варианты с метками веба', (tester) async {
    await pumpRoute(
      tester,
      doctorRoute(
        status: 'kept',
        signals: [requestSignal()],
        prefersCurrent: true,
        blocked: ['08UM'],
        lastAttempt: {'outcome': 'cancelled', 'toMoCode': '22GN', 'toMoName': dostar, 'at': '2026-09-24T10:00:00+00:00', 'reason': 'передумали'},
      ),
    );
    expect(find.text('ОСТАВИТЬ ИЛИ ПЕРЕВЕСТИ'), findsOneWidget);
    expect(find.textContaining('Пациент просит рассмотреть: Региональный военный госпиталь'), findsOneWidget);
    expect(find.textContaining('«живу рядом»'), findsOneWidget);
    expect(find.textContaining('Последняя попытка: Перевод отменён: Достар Мед — «передумали»'), findsOneWidget);
    expect(find.text('Пациент просит оставить его в своей больнице'), findsOneWidget);
    expect(find.text('Просит пациент'), findsOneWidget, reason: 'метка у больницы из запроса');
    expect(find.textContaining('031N · 9 из 10 ждут до 12 дн. · риск отказа 36 %'), findsOneWidget);
    expect(find.text('половина ждёт ≈ 4 дн.'), findsOneWidget);
    expect(find.textContaining('Приват клиник'), findsNothing, reason: 'отказавшая или отклонённая больница не предлагается');
    expect(find.text('ПРИЧИНА РЕШЕНИЯ (ОБЯЗАТЕЛЬНО)'), findsOneWidget);
    expect(find.text('Отметка нужна только при переводе: выберите больницу в списке'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged, isNull, reason: 'тяжёлый случай — только с выбранной больницей');
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Перевести в выбранную')).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Оставить в текущей')).onPressed, isNotNull);
    expect(find.text('Нужен другой профиль или новое направление?'), findsOneWidget);
    expect(find.text('ПЕРЕВОД'), findsNothing);

    await tester.tap(find.textContaining('Казахский научно-исследовательский институт онкологии'));
    await pumpFrames(tester);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged, isNotNull);
    expect(find.text('Отметка нужна только при переводе: выберите больницу в списке'), findsNothing);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Перевести в выбранную')).onPressed, isNotNull);
    await tester.tap(find.byType(SwitchListTile));
    await pumpFrames(tester);
    await tester.tap(find.textContaining('Казахский научно-исследовательский институт онкологии'));
    await pumpFrames(tester);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isFalse, reason: 'снятый выбор снимает и отметку тяжести');
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Перевести в выбранную')).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('больница соседнего региона подписана «сосед: регион» по справочнику регионов', (tester) async {
    final (session, backend) = await demoSession(DemoUser.doctor1, api: {
      routePath: doctorRoute(alternatives: [
        {'mo': {'moCode': '71AA', 'name': 'ТОО "Астана Мед"', 'regionKato': '71'}, 'p50Days': 6, 'p90Days': 15, 'pRefusal': 0.05, 'distanceKm': 0, 'isNeighborRegion': true},
      ]),
      '/refdata/regions': {
        'items': [
          {'regionKato': '71', 'name': 'г. Астана'},
        ],
      },
    });
    await pumpScreen(tester, session, const PatientRouteScreen(patientRef: routeRef), size: tall);
    expect(find.text('71AA · сосед: г. Астана · 9 из 10 ждут до 15 дн. · риск отказа 5 %'), findsOneWidget);
    expect(backend.calls('GET', '/refdata/regions'), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('перевод ждёт согласия: карточка «Перевод» с больницей, причиной, тяжёлым случаем и отменой', (tester) async {
    await pumpRoute(tester, doctorRoute(status: 'transfer_pending_consent', allowed: ['cancel_transfer'], transfer: transferTo(severe: true)));
    expect(find.text('ПЕРЕВОД'), findsOneWidget);
    expect(find.text('Перевод предложен: ждём согласия пациента'), findsWidgets);
    expect(find.textContaining('Перевод в Региональный военный госпиталь'), findsOneWidget);
    expect(find.text('Причина: там раньше дата'), findsOneWidget);
    expect(find.text('Тяжёлый случай'), findsOneWidget);
    expect(find.text('ПРИЧИНА ОТМЕНЫ (ОБЯЗАТЕЛЬНО)'), findsOneWidget);
    expect(find.text('Отменить перевод'), findsOneWidget);
    expect(find.text('Снять с листа ожидания'), findsNothing);
    expect(find.text('Оставить в текущей'), findsNothing);
    expect(find.text('Открыть входящие'), findsNothing, reason: 'больница пациента, не принимающая');
    expect(tester.takeException(), isNull);
  });

  testWidgets('после подтверждения: больнице пациента — «За пациента отвечает …», принимающей — дата, «дата прошла» и входящие', (tester) async {
    final (session, _) = await demoSession(DemoUser.doctor1, api: {
      routePath: doctorRoute(
        status: 'transferred',
        allowed: ['reschedule', 'admit', 'no_show'],
        side: 'receiving',
        overdue: true,
        transfer: transferTo(plannedAt: '2026-10-03'),
      ),
    });
    final router = await pumpRouterApp(tester, session, location: '/doctor/patients/$routeRef', size: tall);
    expect(find.text('Переведён, дата назначена'), findsWidgets);
    expect(find.text('Дата госпитализации: 03.10.2026'), findsOneWidget);
    expect(find.text('Дата прошла: нужно отметить госпитализацию или неявку'), findsOneWidget);
    expect(find.text('Перенести'), findsNothing, reason: 'действия принимающей — на экране входящих');
    expect(find.text('Отменить перевод'), findsNothing);
    await tester.tap(find.text('Открыть входящие'));
    await pumpFrames(tester);
    expect(router.state.uri.path, '/doctor/incoming');
    tester.takeException();
  });

  testWidgets('больница пациента после подтверждённого перевода видит, кто теперь отвечает', (tester) async {
    await pumpRoute(
      tester,
      doctorRoute(status: 'transferred', allowed: const [], responsibleMoCode: '031N', responsibleMoName: military, transfer: transferTo(plannedAt: '2026-10-03')),
    );
    expect(find.textContaining('За пациента отвечает Региональный военный госпиталь'), findsOneWidget);
    expect(find.textContaining('дальнейшие действия — у неё.'), findsOneWidget);
    expect(find.text('Открыть входящие'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('завершённый маршрут: статус с причиной закрытия, без действий', (tester) async {
    await pumpRoute(tester, doctorRoute(status: 'closed', allowed: const [], closedReason: 'discharged', transfer: transferTo(plannedAt: '2026-10-03')));
    expect(find.text('Маршрут завершён · Выписан'), findsOneWidget);
    expect(find.text('Выписан'), findsOneWidget, reason: 'причина закрытия справа в карточке перевода');
    expect(find.byType(FilledButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('журнал маршрута — голосом персонала: предложенный перевод с тяжёлым случаем и запрос пациента', (tester) async {
    await pumpRoute(
      tester,
      doctorRoute(journal: [
        {'id': 'j2', 'at': '2026-09-25T12:00:00+00:00', 'kind': 'redirect', 'role': 'doctor', 'moCode': '22GN', 'moName': dostar, 'reason': 'ближе', 'severe': true},
        {'id': 'j1', 'at': '2026-09-25T10:00:00+00:00', 'kind': 'request', 'role': 'citizen', 'moCode': '22GN', 'moName': dostar, 'reason': 'живу рядом'},
      ]),
    );
    expect(find.text('Предложен перевод: Достар Мед'), findsOneWidget);
    expect(find.text('Пациент просит рассмотреть: Достар Мед'), findsOneWidget);
    expect(find.textContaining('тяжёлый случай'), findsOneWidget);
    expect(find.textContaining('Комментарий пациента'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ссылки: «Записать приём» — скрайб этого пациента, «Подобрать в ассистенте» — новое направление с больницей и профилем', (tester) async {
    final (session, _) = await demoSession(DemoUser.doctor1, api: {routePath: doctorRoute()});
    final router = await pumpRouterApp(tester, session, location: '/doctor/patients/$routeRef', size: tall);
    await tester.tap(find.text('Подобрать в ассистенте'));
    await pumpFrames(tester);
    expect(router.state.uri.path, '/doctor/referral');
    expect(router.state.uri.queryParameters, {'moCode': '224E', 'profileCode': '171'});
    tester.takeException();
    router.pop();
    await pumpFrames(tester);
    await tester.tap(find.text('Записать приём'));
    await pumpFrames(tester);
    expect(router.state.uri.path, '/doctor/patients/$routeRef/scribe');
    tester.takeException();
  });

  testWidgets('у главврача без scribe.use и referral.assist нет ни скрайба, ни ассистента', (tester) async {
    await pumpRoute(tester, doctorRoute(), user: DemoUser.chief1);
    expect(find.text('Оставить в текущей'), findsOneWidget, reason: 'решение даёт allowed с сервера');
    expect(find.text('Записать приём'), findsNothing);
    expect(find.text('Подобрать в ассистенте'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('404 — «Маршрут с таким рефом не найден» и ссылка на рабочий список', (tester) async {
    final (session, _) = await demoSession(DemoUser.doctor1, api: {routePath: problem(404, 'Пациент не найден')});
    final router = await pumpRouterApp(tester, session, location: '/doctor/patients/$routeRef', size: tall);
    expect(find.text('Маршрут с таким рефом не найден'), findsOneWidget);
    expect(find.text(routeRef), findsWidgets);
    await tester.tap(find.text('Рабочий список'));
    await pumpFrames(tester);
    expect(router.state.uri.path, '/doctor/patients');
    tester.takeException();
  });

  testWidgets('403 — «Нет доступа» с причиной сервера, без «Сервер недоступен»', (tester) async {
    final (session, backend) = await demoSession(DemoUser.doctor1, api: {
      routePath: problem(403, 'Пациент другого региона', detail: 'врач видит маршруты пациентов только своего региона'),
    });
    await pumpScreen(tester, session, const PatientRouteScreen(patientRef: routeRef), size: tall);
    expect(find.text('Нет доступа к разделу'), findsOneWidget);
    expect(find.text('Пациент другого региона — врач видит маршруты пациентов только своего региона'), findsOneWidget);
    expect(find.textContaining('Сервер недоступен'), findsNothing);
    expect(backend.calls('GET', routePath), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('ошибка сервера при загрузке — «Повторить» перечитывает маршрут', (tester) async {
    final (session, backend) = await demoSession(DemoUser.doctor1, api: {routePath: problem(500, 'Internal')});
    await pumpScreen(tester, session, const PatientRouteScreen(patientRef: routeRef), size: tall);
    expect(find.text('Не удалось загрузить данные'), findsOneWidget);
    backend.routes[routePath] = doctorRoute();
    await tester.tap(find.text('Повторить'));
    await pumpFrames(tester);
    expect(find.text('ОСТАВИТЬ ИЛИ ПЕРЕВЕСТИ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('по-казахски при шрифте 1.3 на 360 dp: решение, факторы и журнал без переполнения', (tester) async {
    await pumpRoute(
      tester,
      doctorRoute(signals: [requestSignal(toMoCode: '22GN', toMoName: dostar)], journal: [
        {'id': 'j1', 'at': '2026-09-25T10:00:00+00:00', 'kind': 'request', 'role': 'citizen', 'moCode': '22GN', 'moName': dostar, 'reason': 'живу рядом'},
      ]),
      locale: 'kk',
      textScale: 1.3,
      size: phoneNarrow,
    );
    expect(find.text('Науқас маршруты'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Ағымдағыда қалдыру'), 300, scrollable: find.byType(Scrollable).first);
    expect(tester.takeException(), isNull);
    await scrollThrough(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('по-казахски при шрифте 1.3 на 360 dp: карточка перевода с отменой и тяжёлым случаем без переполнения', (tester) async {
    await pumpRoute(
      tester,
      doctorRoute(status: 'transfer_pending_confirmation', allowed: ['cancel_transfer'], transfer: transferTo(severe: true)),
      locale: 'kk',
      textScale: 1.3,
      size: phoneNarrow,
    );
    await tester.scrollUntilVisible(find.text('Ауыстыруды тоқтату'), 300, scrollable: find.byType(Scrollable).first);
    expect(tester.takeException(), isNull);
    await scrollThrough(tester);
    expect(tester.takeException(), isNull);
  });
}

/// Прокручивает страницу шагами, чтобы построились и проверились на переполнение все карточки.
Future<void> scrollThrough(WidgetTester tester) async {
  final list = find.byType(Scrollable).first;
  for (var i = 0; i < 12; i++) {
    await tester.drag(list, const Offset(0, -500));
    await tester.pump(const Duration(milliseconds: 200));
  }
}
