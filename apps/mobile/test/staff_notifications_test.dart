import 'dart:async';

import 'package:darumen/l10n/strings.dart';
import 'package:darumen/screens/staff_notifications_screen.dart';
import 'package:darumen/widgets/format.dart';
import 'package:darumen/widgets/route/route_journal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/harness.dart';

/// Уведомления персонала (`/doctor/notifications`, `StaffBellNotifier`): строка «Ожидают подтверждения: N» ведёт во
/// «Входящие»; подтверждения моих направлений и выписки с эпикризом прямо в пункте (Q-7) и события пациентов —
/// нажатие отмечает прочитанным и открывает маршрут пациента (ответы на запись приёма — скрайб, как в вебе, если он
/// есть у пользователя). Тексты всех видов в обоих языках, пустое состояние, ошибка, казахский при 1.3 на 360 dp.

const dostar = 'Товарищество с ограниченной ответственностью "Достар Мед"';
const summaryText = 'Диагноз: катаракта. Проведена факоэмульсификация. Наблюдение у офтальмолога через 7 дней.';
const eventKinds = [
  'request',
  'prefer_current',
  'still_waiting',
  'withdraw',
  'treated_elsewhere',
  'consent_accepted',
  'consent_declined',
  'scribe_granted',
  'scribe_declined',
  'scribe_withdrawn',
];

/// Реф пациента события [kind]: у каждого свой номер, чтобы найти строку и цель перехода.
String eventRef(String kind) => 'SYN-75-028B-381-${eventKinds.indexOf(kind) + 20}';

Map<String, Object?> eventJson(String kind, {String? comment}) => {
      'id': 'e-$kind',
      'patientRef': eventRef(kind),
      'kind': kind,
      'moCode': kind.startsWith('scribe_') ? null : '22GN',
      'moName': kind.startsWith('scribe_') ? null : dostar,
      'comment': comment,
      'at': '2026-10-01T11:00:00+00:00',
    };

/// Колокольчик со всеми видами пунктов: 2 ждут подтверждения, подтверждение, выписка с эпикризом, десять событий
/// пациентов и одно незнакомое.
Map<String, Object?> fullBell() => {
      'pendingIncomingCount': 2,
      'unreadConfirmations': [
        {'decisionId': 'c-1', 'patientRef': 'SYN-75-028B-381-03', 'toMoCode': '22GN', 'toMoName': dostar, 'confirmedAt': '2026-10-01T10:00:00+00:00'},
      ],
      'unreadDischarges': [
        {
          'decisionId': 'x-1',
          'patientRef': 'SYN-75-028B-381-05',
          'fromMoCode': '22GN',
          'fromMoName': dostar,
          'summary': summaryText,
          'dischargedAt': '2026-10-02T08:30:00+00:00',
        },
      ],
      'patientSignals': [
        for (final kind in eventKinds) eventJson(kind, comment: kind == 'request' ? 'Ближе к дому' : null),
        eventJson('something_new'),
      ],
    };

const tall = Size(390, 3000);

void main() {
  final short = shortOrgName(dostar);

  testWidgets('every kind of item with the web texts; the discharge summary is in the item (Q-7); «новых: N»', (tester) async {
    final (session, _) = await demoSession(DemoUser.doctor1, api: {'/journal/notifications/bell': fullBell()});
    await pumpScreen(tester, session, const StaffNotificationsScreen(), size: tall);

    expect(find.text('Уведомления'), findsOneWidget);
    expect(find.text('новых: 15'), findsOneWidget, reason: '2 ждут + подтверждение + выписка + 11 событий');
    expect(find.text('Ожидают подтверждения: 2'), findsOneWidget);
    expect(find.text('Направление в $short подтверждено'), findsOneWidget);
    expect(find.text('SYN-75-028B-381-03 · ${journalMoment('2026-10-01T10:00:00+00:00')}'), findsOneWidget);
    expect(find.text('Пациент выписан из $short, эпикриз готов'), findsOneWidget);
    expect(find.text(summaryText), findsOneWidget, reason: 'эпикриз — прямо в пункте');
    expect(find.text('ЭПИКРИЗ ВЫПИСКИ'), findsOneWidget);
    expect(find.text('Пациент ${eventRef('request')} просит рассмотреть: $short'), findsOneWidget);
    expect(find.text('«Ближе к дому»'), findsOneWidget);
    expect(find.text('Пациенту ${eventRef('withdraw')} госпитализация больше не нужна — подтвердите снятие'), findsOneWidget);
    expect(find.text('Пациент ${eventRef('scribe_withdrawn')} отозвал разрешение на запись приёма'), findsOneWidget);
    final ru = S.of('ru');
    for (final kind in eventKinds) {
      expect(find.text(ru.staffBellPatientEvent(kind, ref: eventRef(kind), org: short)), findsOneWidget, reason: kind);
    }
    expect(find.text('Событие пациента ${eventRef('something_new')}'), findsOneWidget, reason: 'незнакомый вид — запасная подпись');
    expect(find.textContaining('something_new'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Kazakh texts, and Kazakh at 1.3 on a 360 dp phone without overflow', (tester) async {
    final (session, _) = await demoSession(DemoUser.doctor1, api: {'/journal/notifications/bell': fullBell()});
    await pumpScreen(tester, session, const StaffNotificationsScreen(), size: const Size(360, 3600), locale: 'kk', textScale: 1.3);
    expect(find.text('Хабарламалар'), findsOneWidget);
    expect(find.text('жаңа: 15'), findsOneWidget);
    expect(find.text('Растауды күтуде: 2'), findsOneWidget);
    expect(find.text('$short ұйымына жолдама расталды'), findsOneWidget);
    expect(find.text('Пациент $short ұйымынан шығарылды, эпикриз дайын'), findsOneWidget);
    expect(find.text('ШЫҒАРУ ЭПИКРИЗІ'), findsOneWidget);
    expect(find.text('${eventRef('request')} пациенті қарауды сұрайды: $short'), findsOneWidget);
    expect(find.text('${eventRef('scribe_granted')} пациенті қабылдауды жазуға рұқсат берді'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dark theme: every kind of item renders from theme tokens without errors', (tester) async {
    final (session, _) = await demoSession(DemoUser.doctor1, api: {'/journal/notifications/bell': fullBell()});
    await pumpScreen(tester, session, const StaffNotificationsScreen(), size: tall, dark: true);
    expect(find.text(summaryText), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty bell → «Новых уведомлений нет», no counter line', (tester) async {
    final (session, _) = await demoSession(DemoUser.doctor1);
    await pumpScreen(tester, session, const StaffNotificationsScreen());
    expect(find.text('Новых уведомлений нет'), findsOneWidget);
    expect(find.textContaining('новых:'), findsNothing);
  });

  testWidgets('a user without a bell (admin without a hospital) sees the empty state and asks nothing', (tester) async {
    final (session, backend) = await demoSession(DemoUser.admin1);
    await pumpScreen(tester, session, const StaffNotificationsScreen());
    expect(find.text('Новых уведомлений нет'), findsOneWidget);
    expect(backend.calls('GET', '/journal/notifications/bell'), isEmpty);
  });

  testWidgets('the bell failed before any data → the load error with «Повторить»; retry shows the items', (tester) async {
    final (session, backend) = await demoSession(DemoUser.doctor1, api: {'/journal/notifications/bell': problem(503, 'Service Unavailable')});
    await pumpScreen(tester, session, const StaffNotificationsScreen());
    expect(find.text('Не удалось загрузить данные'), findsOneWidget);
    backend.routes['/journal/notifications/bell'] = {'pendingIncomingCount': 1};
    await tester.tap(find.text('Повторить'));
    await pumpFrames(tester);
    expect(find.text('Ожидает подтверждения: 1'), findsOneWidget, reason: 'веб bell.pendingIncomingOne');
  });

  testWidgets('a failed poll over shown data keeps the items and puts the error above them', (tester) async {
    final (session, backend) = await demoSession(DemoUser.doctor1, api: {'/journal/notifications/bell': {'pendingIncomingCount': 2}});
    await pumpScreen(tester, session, const StaffNotificationsScreen(), pollInterval: const Duration(seconds: 5));
    expect(find.text('Ожидают подтверждения: 2'), findsOneWidget);
    backend.routes['/journal/notifications/bell'] = problem(503, 'Service Unavailable');
    await tester.pump(const Duration(seconds: 5));
    await pumpFrames(tester);
    expect(find.text('Ожидают подтверждения: 2'), findsOneWidget, reason: 'показанные данные остаются');
    expect(find.text('Сервер недоступен. Повторите попытку позже.'), findsOneWidget);
  });

  group('taps', () {
    Future<(DemoBackend, GoRouter)> open(WidgetTester tester, DemoUser user) async {
      final (session, backend) = await demoSession(user, api: {
        '/journal/notifications/bell': fullBell(),
        'POST /read': noContent(),
      });
      final router = await pumpRouterApp(tester, session, location: '/doctor/patients', size: tall);
      unawaited(router.push('/doctor/notifications'));
      await pumpFrames(tester);
      expect(router.state.uri.path, '/doctor/notifications');
      return (backend, router);
    }

    testWidgets('«Ожидают подтверждения» opens the incoming tab and marks nothing', (tester) async {
      final (backend, router) = await open(tester, DemoUser.doctor1);
      await tester.tap(find.text('Ожидают подтверждения: 2'));
      await pumpFrames(tester);
      expect(router.state.uri.path, '/doctor/incoming');
      expect(backend.requests.where((r) => r.method == 'POST' && r.url.path.endsWith('/read')), isEmpty);
    });

    testWidgets('a confirmation marks itself read and opens the patient route (Q-7)', (tester) async {
      final (backend, router) = await open(tester, DemoUser.doctor1);
      await tester.tap(find.text('Направление в $short подтверждено'));
      await pumpFrames(tester);
      expect(backend.calls('POST', '/journal/notifications/bell/referral-confirmed/c-1/read'), hasLength(1));
      expect(router.state.uri.path, '/doctor/patients/SYN-75-028B-381-03');
    });

    testWidgets('a discharge marks itself read and opens the patient route (Q-7)', (tester) async {
      final (backend, router) = await open(tester, DemoUser.doctor1);
      await tester.tap(find.text('Пациент выписан из $short, эпикриз готов'));
      await pumpFrames(tester);
      expect(backend.calls('POST', '/journal/notifications/bell/referral-discharged/x-1/read'), hasLength(1));
      expect(router.state.uri.path, '/doctor/patients/SYN-75-028B-381-05');
    });

    testWidgets('a patient request marks the event read and opens the patient route', (tester) async {
      final (backend, router) = await open(tester, DemoUser.doctor1);
      await tester.tap(find.text('Пациент ${eventRef('request')} просит рассмотреть: $short'));
      await pumpFrames(tester);
      expect(backend.calls('POST', '/journal/notifications/bell/patient-signal/e-request/read'), hasLength(1));
      expect(router.state.uri.path, '/doctor/patients/${eventRef('request')}');
    });

    testWidgets('a scribe answer opens the scribe of that patient for a doctor with scribe.use (web parity)', (tester) async {
      final (backend, router) = await open(tester, DemoUser.doctor1);
      await tester.tap(find.text('Пациент ${eventRef('scribe_granted')} разрешил записать приём'));
      await pumpFrames(tester);
      expect(backend.calls('POST', '/journal/notifications/bell/patient-signal/e-scribe_granted/read'), hasLength(1));
      expect(router.state.uri.path, '/doctor/patients/${eventRef('scribe_granted')}/scribe');
    });

    testWidgets('without scribe.use (org_admin) a scribe answer opens the patient route instead', (tester) async {
      final (_, router) = await open(tester, DemoUser.chief1);
      await tester.tap(find.text('Пациент ${eventRef('scribe_declined')} не разрешил записать приём'));
      await pumpFrames(tester);
      expect(router.state.uri.path, '/doctor/patients/${eventRef('scribe_declined')}');
    });
  });
}
