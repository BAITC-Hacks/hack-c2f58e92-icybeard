import 'package:darumen/api/client.dart';
import 'package:darumen/state/staff_bell_notifier.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/harness.dart';

const _path = '/journal/notifications/bell';

Map<String, Object?> _bell({int pending = 1, List<String> confirmations = const ['c1'], List<String> discharges = const ['d1'], List<String> signals = const ['s1', 's2']}) => {
      'pendingIncomingCount': pending,
      'unreadConfirmations': [
        for (final id in confirmations)
          {'decisionId': id, 'patientRef': 'SYN-75-028B-381-01', 'toMoCode': '22GN', 'toMoName': 'Достар Мед', 'confirmedAt': '2026-10-01T09:00:00+00:00', 'read': false},
      ],
      'unreadDischarges': [
        for (final id in discharges)
          {
            'decisionId': id,
            'patientRef': 'SYN-75-028B-381-02',
            'fromMoCode': '22GN',
            'fromMoName': 'Достар Мед',
            'summary': 'лечение завершено',
            'dischargedAt': '2026-10-01T10:00:00+00:00',
            'read': false,
          },
      ],
      'patientSignals': [
        for (final id in signals) {'id': id, 'patientRef': 'SYN-75-028B-381-03', 'kind': 'request', 'moCode': '22GN', 'moName': 'Достар Мед', 'at': '2026-10-01T11:00:00+00:00'},
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('doctor with an organisation: the bell of his hospital loads at start and every 60 s in the foreground', (tester) async {
    final (session, backend) = await demoSession(DemoUser.doctor1, api: {_path: _bell()});
    final bell = StaffBellNotifier(session: session);
    expect(StaffBellNotifier.defaultInterval, const Duration(seconds: 60), reason: 'Q-15');
    bell.start();
    await tester.pump();
    expect(bell.active, isTrue);
    expect(backend.calls('GET', _path).single.url.queryParameters['moCode'], '028B');
    expect(bell.pendingIncomingCount, 1);
    expect(bell.unreadConfirmations.single.decisionId, 'c1');
    expect(bell.unreadDischarges.single.summary, 'лечение завершено');
    expect(bell.patientSignals, hasLength(2));
    expect(bell.totalUnread, 5, reason: 'как в вебе: ждут подтверждения + три непрочитанных списка');

    await tester.pump(const Duration(seconds: 60));
    expect(backend.calls('GET', _path), hasLength(2));

    for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump(const Duration(minutes: 10));
    expect(backend.calls('GET', _path), hasLength(2), reason: 'в фоне не опрашиваем');
    for (final state in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    expect(backend.calls('GET', _path), hasLength(3), reason: 'возвращение из фона — сразу');
    bell.dispose();
  });

  testWidgets('only worklist.view with an own mo_code: org_admin yes; admin without a hospital, a citizen, a doctor without mo_code — no',
      (tester) async {
    final (chief, chiefBackend) = await demoSession(DemoUser.chief1);
    final chiefBell = StaffBellNotifier(session: chief);
    chiefBell.start();
    await tester.pump();
    expect(chiefBell.active, isTrue);
    expect(chiefBackend.calls('GET', _path).single.url.queryParameters['moCode'], '028B');

    for (final (user, overrides) in [
      (DemoUser.admin1, const <String, String?>{}),
      (DemoUser.citizen1, const <String, String?>{}),
      (DemoUser.doctor1, const <String, String?>{'mo_code': null}),
      (DemoUser.regulator1, const <String, String?>{}),
    ]) {
      final (session, backend) = await demoSession(user, claimOverrides: overrides);
      final bell = StaffBellNotifier(session: session);
      bell.start();
      await tester.pump(const Duration(minutes: 2));
      expect(bell.active, isFalse, reason: '${user.name} $overrides');
      expect(bell.totalUnread, 0);
      expect(backend.calls('GET', _path), isEmpty, reason: '${user.name} $overrides');
      bell.dispose();
    }
    chiefBell.dispose();
  });

  testWidgets('markRead removes the item at once, posts the right kind and refetches', (tester) async {
    var server = _bell();
    final (session, backend) = await demoSession(DemoUser.doctor1, api: {
      _path: (http.Request r) => server,
      'POST /read': noContent(),
    });
    final bell = StaffBellNotifier(session: session);
    bell.start();
    await tester.pump();

    server = _bell(signals: ['s2']);
    final done = bell.markRead(StaffBellNotifier.patientSignal, 's1');
    expect(bell.patientSignals.map((s) => s.id), ['s2'], reason: 'пункт исчезает сразу');
    expect(bell.totalUnread, 4);
    await done;
    expect(backend.calls('POST', '/journal/notifications/bell/patient-signal/s1/read'), hasLength(1));
    expect(backend.calls('GET', _path), hasLength(2));

    server = _bell(confirmations: [], signals: ['s2']);
    await bell.markRead(StaffBellNotifier.referralConfirmed, 'c1');
    expect(backend.calls('POST', '/journal/notifications/bell/referral-confirmed/c1/read'), hasLength(1));
    expect(bell.unreadConfirmations, isEmpty);

    server = _bell(confirmations: [], discharges: [], signals: ['s2']);
    await bell.markRead(StaffBellNotifier.referralDischarged, 'd1');
    expect(backend.calls('POST', '/journal/notifications/bell/referral-discharged/d1/read'), hasLength(1));
    expect(bell.unreadDischarges, isEmpty);
    expect(bell.totalUnread, 2);
    expect(bell.error, isNull);
    bell.dispose();
  });

  testWidgets('a failed mark-read is recorded and the list comes back from the server', (tester) async {
    final (session, backend) = await demoSession(DemoUser.doctor1, api: {
      _path: _bell(),
      'POST /read': problem(400, 'Неизвестный вид уведомления'),
    });
    final bell = StaffBellNotifier(session: session);
    bell.start();
    await tester.pump();
    await bell.markRead(StaffBellNotifier.patientSignal, 's1');
    expect(bell.error, isA<ApiException>().having((e) => e.status, 'status', 400));
    expect(bell.patientSignals, hasLength(2), reason: 'перечитанный список — истина сервера');
    expect(backend.calls('GET', _path), hasLength(2));
    bell.dispose();
  });

  testWidgets('sign-out clears the bell and stops polling', (tester) async {
    final (session, backend) = await demoSession(DemoUser.doctor1, api: {_path: _bell(pending: 3)});
    final bell = StaffBellNotifier(session: session);
    bell.start();
    await tester.pump();
    expect(bell.pendingIncomingCount, 3);
    await session.logout();
    await tester.pump();
    expect(bell.active, isFalse);
    expect(bell.pendingIncomingCount, 0);
    expect(bell.bell, isNull);
    await tester.pump(const Duration(minutes: 3));
    expect(backend.calls('GET', _path), hasLength(1));
    bell.dispose();
  });
}
