import 'package:darumen/screens/worklist_screen.dart';
import 'package:darumen/widgets/bell_button.dart';
import 'package:darumen/widgets/circle_button.dart';
import 'package:darumen/widgets/route/priority_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

/// Рабочий список врача (/doctor/patients): бейдж приоритета 0…10, один чип статуса по восьми флагам, следующий шаг
/// словами, фильтр со счётчиками в листе, сортировка, тап по строке — сразу маршрут пациента, без кнопок в строке;
/// баннер устаревших данных, колокольчик и ассистент в шапке.
const dostar = 'Товарищество с ограниченной ответственностью "Достар Мед"';

Map<String, Object?> worklistRow(
  String ref, {
  List<String> flags = const [],
  int priority = 5,
  int days = 30,
  String next = 'wait_for_call',
  String stageCode = 'waiting',
  Map<String, Object?>? signal,
}) =>
    {
      'patientRef': ref,
      'synthetic': true,
      'stage': 'ожидает',
      'stageCode': stageCode,
      'expectedDate': '2025-03-31',
      'riskFlags': flags,
      'priority': priority,
      'nextAction': 'ждать вызова',
      'nextActionCode': next,
      'explanation': '',
      'moCode': '028B',
      'moName': demoOrganizations['028B'],
      'profileCode': '381',
      'regionKato': '75',
      'daysWaiting': days,
      'patientSignal': signal,
    };

Map<String, Object?> page(List<Map<String, Object?>> items, {String asOf = '2025-03-31', bool modelBacked = true}) =>
    {'items': items, 'synthetic': true, 'asOf': asOf, 'regionKato': '75', 'modelBacked': modelBacked};

final signalRow = worklistRow(
  'SYN-75-028B-381-03',
  flags: ['patient_signal'],
  priority: 4,
  days: 40,
  signal: {'kind': 'request_redirect', 'toMoCode': '22GN', 'toMoName': dostar, 'comment': 'живу рядом', 'recordedAt': '2026-09-25T10:00:00+00:00'},
);

const refdata = <String, Object?>{
  '/refdata/regions': {
    'items': [
      {'regionKato': '75', 'name': 'г. Алматы'},
    ],
  },
  '/refdata/profiles': {
    'items': [
      {'profileCode': '171', 'name': 'Травматологические для взрослых'},
      {'profileCode': '381', 'name': 'Офтальмологические'},
    ],
  },
};

void main() {
  testWidgets('строки: бейдж приоритета, один чип по порядку флагов, шаг словами, сигнал пациента без кнопок в строке', (tester) async {
    final (session, _) = await demoSession(DemoUser.doctor1, api: {
      ...refdata,
      '/journal/worklist': page([...fixtureMap('worklist')['items'] as List<dynamic>, signalRow].cast<Map<String, Object?>>()),
    });
    await pumpScreen(tester, session, const WorklistScreen(), size: phoneTall);
    expect(find.text('Пациенты'), findsOneWidget);
    expect(find.textContaining('г. Алматы · Плановая госпитализация'), findsOneWidget);
    expect(find.textContaining('список синтетический, без персональных данных'), findsOneWidget);
    expect(find.byKey(const ValueKey('stale-banner')), findsOneWidget, reason: 'срез старше недели — баннер без кнопки «Обновить»');
    expect(find.text('Обновить'), findsNothing);
    expect(find.byType(PriorityBadge), findsNWidgets(5));
    expect(find.byTooltip('Высокий приоритет · 9 из 10'), findsOneWidget);
    expect(find.byTooltip('Средний приоритет · 4 из 10'), findsOneWidget);
    expect(find.text('Риск отказа'), findsNWidgets(2), reason: '224E и 233U: риск отказа важнее «есть быстрее» и «> 30 дней»');
    expect(find.text('Идёт перевод'), findsNWidgets(2), reason: 'перевод важнее риска отказа');
    expect(find.text('Запрос пациента'), findsOneWidget);
    expect(find.text('Следующий шаг: предложить быстрее'), findsOneWidget);
    expect(find.text('Следующий шаг: ждём пациента'), findsNWidgets(2));
    expect(find.text('Следующий шаг: проверить документы'), findsOneWidget);
    expect(find.text('Пациент просит рассмотреть: Достар Мед — «живу рядом»'), findsOneWidget);
    expect(find.textContaining('Травматологические для взрослых'), findsOneWidget, reason: 'профиль койки из справочника');
    expect(find.text('показаны 5 из 5'), findsOneWidget);
    expect(find.text('Направить'), findsNothing, reason: 'Q-16: ответ пациенту — только на маршруте');
    expect(find.text('Оставить'), findsNothing);
    final first = tester.getTopLeft(find.text('SYN-75-224E-171-01'));
    final signal = tester.getTopLeft(find.text('SYN-75-028B-381-03'));
    expect(first.dy, lessThan(signal.dy), reason: 'приоритет 9 выше приоритета 4');
    expect(tester.takeException(), isNull);
  });

  testWidgets('фильтр — лист со счётчиками вместо KPI, поиск по номеру, «ничего не найдено» и сброс', (tester) async {
    final (session, _) = await demoSession(DemoUser.doctor1, api: {...refdata, '/journal/worklist': fixtureMap('worklist')});
    await pumpScreen(tester, session, const WorklistScreen(), size: phoneTall);
    expect(find.text('пациентов ждут госпитализации'), findsNothing, reason: 'Q-3: без KPI-плиток');
    await tester.tap(find.text('Все пациенты · 4'));
    await pumpFrames(tester);
    expect(find.text('Ждут больше 30 дней · 4'), findsOneWidget);
    expect(find.text('Идёт перевод · 2'), findsOneWidget);
    expect(find.text('Дата госпитализации прошла · 0'), findsOneWidget);
    await tester.tap(find.text('Идёт перевод · 2'));
    await pumpFrames(tester);
    expect(find.text('Идёт перевод · 2'), findsOneWidget, reason: 'выбранный пункт — в поле фильтра');
    expect(find.text('SYN-75-224E-171-01'), findsNothing);
    expect(find.text('SYN-75-225T-251-01'), findsOneWidget);
    expect(find.text('показаны 2 из 4'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'нет-такого');
    await pumpFrames(tester);
    expect(find.text('Ничего не найдено'), findsOneWidget);
    expect(find.text('По этому фильтру или запросу пациентов нет.'), findsOneWidget);
    await tester.tap(find.text('Сбросить фильтры'));
    await pumpFrames(tester);
    expect(find.text('Все пациенты · 4'), findsOneWidget);
    expect(find.text('SYN-75-224E-171-01'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '08iv');
    await pumpFrames(tester);
    expect(find.text('SYN-75-08IV-121-01'), findsOneWidget);
    expect(find.text('SYN-75-233U-152-01'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('сортировка: лист колонок веба, повторный выбор меняет направление', (tester) async {
    final (session, _) = await demoSession(DemoUser.doctor1, api: {...refdata, '/journal/worklist': fixtureMap('worklist')});
    await pumpScreen(tester, session, const WorklistScreen(), size: phoneTall);
    double top(String ref) => tester.getTopLeft(find.text(ref)).dy;
    await tester.tap(find.byTooltip('Сортировка'));
    await pumpFrames(tester);
    expect(find.text('Приоритет ↓'), findsOneWidget, reason: 'текущая сортировка — со стрелкой');
    await tester.tap(find.text('Ждёт, дн.'));
    await pumpFrames(tester);
    expect(top('SYN-75-224E-171-01'), lessThan(top('SYN-75-233U-152-01')), reason: '89 дн. выше 85 дн.');
    expect(top('SYN-75-233U-152-01'), lessThan(top('SYN-75-08IV-121-01')));
    await tester.tap(find.byTooltip('Сортировка'));
    await pumpFrames(tester);
    await tester.tap(find.text('Ждёт, дн. ↓'));
    await pumpFrames(tester);
    expect(top('SYN-75-08IV-121-01'), lessThan(top('SYN-75-224E-171-01')), reason: 'по возрастанию: 49 дн. первым');
    expect(tester.takeException(), isNull);
  });

  testWidgets('тап по строке открывает маршрут пациента; при возврате список перечитывается', (tester) async {
    final (session, backend) = await demoSession(DemoUser.doctor1, api: {
      ...refdata,
      '/journal/worklist': fixtureMap('worklist'),
      '/route/SYN-75-224E-171-01': fixtureMap('route-doctor'),
    });
    final router = await pumpRouterApp(tester, session, location: '/doctor/patients', size: phoneTall);
    expect(backend.calls('GET', '/journal/worklist'), hasLength(1));
    await tester.tap(find.text('SYN-75-224E-171-01'));
    await pumpFrames(tester);
    expect(router.state.uri.path, '/doctor/patients/SYN-75-224E-171-01');
    expect(find.text('Маршрут пациента'), findsOneWidget);
    await tester.tap(find.byTooltip('Назад'));
    await pumpFrames(tester);
    expect(router.state.uri.path, '/doctor/patients');
    expect(backend.calls('GET', '/journal/worklist'), hasLength(2), reason: 'после решения на маршруте строка показывает новый шаг');
    expect(tester.takeException(), isNull);
  });

  testWidgets('шапка: колокольчик персонала; ассистент направления открывает /doctor/referral поверх вкладок', (tester) async {
    final (session, _) = await demoSession(DemoUser.doctor1, api: {...refdata, '/journal/worklist': fixtureMap('worklist')});
    final router = await pumpRouterApp(tester, session, location: '/doctor/patients', size: phoneTall);
    expect(find.descendant(of: find.byType(BellButton), matching: find.byType(CircleIconButton)), findsOneWidget);
    await tester.tap(find.byTooltip('Ассистент направления'));
    await pumpFrames(tester);
    expect(router.state.uri.path, '/doctor/referral');
    expect(tester.takeException(), isNull);
  });

  testWidgets('главврач без referral.assist: нет ни ассистента в шапке, ни «Создать направление» в пустом списке', (tester) async {
    final (chief, _) = await demoSession(DemoUser.chief1, api: {...refdata, '/journal/worklist': page(const [])});
    await pumpScreen(tester, chief, const WorklistScreen(), size: phoneTall);
    expect(find.text('В списке нет пациентов'), findsOneWidget);
    expect(find.byTooltip('Ассистент направления'), findsNothing);
    expect(find.text('Создать направление'), findsNothing);
    expect(find.descendant(of: find.byType(BellButton), matching: find.byType(CircleIconButton)), findsOneWidget, reason: 'у главврача есть своя больница');
    expect(tester.takeException(), isNull);
  });

  testWidgets('пустой список: текст веба, свежая дата в подзаголовке и «Создать направление» с referral.assist', (tester) async {
    final (session, backend) = await demoSession(DemoUser.doctor1, api: {...refdata, '/journal/worklist': page(const [], asOf: '2099-01-01')});
    final router = await pumpRouterApp(tester, session, location: '/doctor/patients', size: phoneTall);
    expect(find.text('В списке нет пациентов'), findsOneWidget);
    expect(find.text('Пациенты появятся после первого направления в листе ожидания региона.'), findsOneWidget);
    expect(find.byKey(const ValueKey('stale-banner')), findsNothing);
    expect(find.textContaining('данные на 01.01.2099'), findsOneWidget, reason: 'свежий срез — дата в подзаголовке');
    await tester.tap(find.text('Создать направление'));
    await pumpFrames(tester);
    expect(router.state.uri.path, '/doctor/referral');
    expect(backend.calls('GET', '/journal/worklist'), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('ошибка загрузки — «Не удалось загрузить данные» и «Повторить», после повтора список на месте', (tester) async {
    final (session, backend) = await demoSession(DemoUser.doctor1, api: {...refdata, '/journal/worklist': problem(500, 'Internal')});
    await pumpScreen(tester, session, const WorklistScreen(), size: phoneTall);
    expect(find.text('Не удалось загрузить данные'), findsOneWidget);
    expect(find.textContaining('Сервер недоступен:'), findsNothing, reason: 'без сырого текста исключения');
    backend.routes['/journal/worklist'] = fixtureMap('worklist');
    await tester.tap(find.text('Повторить'));
    await pumpFrames(tester);
    expect(find.text('SYN-75-224E-171-01'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('403 — состояние «Нет доступа к разделу» с причиной сервера', (tester) async {
    final (session, _) = await demoSession(DemoUser.doctor1, api: {...refdata, '/journal/worklist': problem(403, 'Forbidden', detail: 'no_organization')});
    await pumpScreen(tester, session, const WorklistScreen(), size: phoneTall);
    expect(find.text('Нет доступа к разделу'), findsOneWidget);
    expect(find.text('К учётной записи не привязана организация: раздел откроется, когда администратор её укажет.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pull-to-refresh держит список на экране, ошибка повторной загрузки — снекбаром «Сервер недоступен»', (tester) async {
    final (session, backend) = await demoSession(DemoUser.doctor1, api: {...refdata, '/journal/worklist': fixtureMap('worklist')});
    await pumpScreen(tester, session, const WorklistScreen(), size: phoneTall);
    backend.routes['/journal/worklist'] = problem(503, 'Service Unavailable');
    await tester.fling(find.text('SYN-75-224E-171-01'), const Offset(0, 400), 1000);
    await pumpFrames(tester);
    expect(backend.calls('GET', '/journal/worklist'), hasLength(2));
    expect(find.text('SYN-75-224E-171-01'), findsOneWidget, reason: 'прежний список остаётся');
    expect(find.text('Сервер недоступен. Повторите попытку позже.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('приоритеты без модели — пометка веба и метка «расчёт по правилу»', (tester) async {
    final (session, _) = await demoSession(DemoUser.doctor1, api: {...refdata, '/journal/worklist': page([signalRow], modelBacked: false)});
    await pumpScreen(tester, session, const WorklistScreen(), size: phoneTall);
    expect(find.text('Сервис моделей недоступен: приоритеты временно посчитаны по агрегатам витрины очереди, не моделью'), findsOneWidget);
    expect(find.text('расчёт по правилу'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('по-казахски при шрифте 1.3 на телефоне 360 dp: строки, фильтр и сортировка без переполнения', (tester) async {
    final (session, _) = await demoSession(DemoUser.doctor1, locale: 'kk', api: {
      ...refdata,
      '/journal/worklist': page([...fixtureMap('worklist')['items'] as List<dynamic>, signalRow].cast<Map<String, Object?>>()),
    });
    await pumpScreen(tester, session, const WorklistScreen(), locale: 'kk', textScale: 1.3, size: phoneNarrow);
    expect(find.text('Пациенттер'), findsOneWidget);
    expect(find.text('Бас тарту қаупі'), findsWidgets);
    expect(find.text('Келесі қадам: жылдамырағын ұсыну'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Барлық пациенттер · 5'));
    await pumpFrames(tester);
    expect(find.text('Жылдамырақ қабылдайтын аурухана бар · 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tapAt(const Offset(180, 40));
    await pumpFrames(tester);
    await tester.tap(find.byTooltip('Сұрыптау'));
    await pumpFrames(tester);
    expect(find.text('Басымдық ↓'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
