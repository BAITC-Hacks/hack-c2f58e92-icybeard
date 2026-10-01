import 'package:darumen/api/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Урезанный, но настоящий `GET /route/me` — гражданин с переводом, ожидающим согласия (route-me.json, §samples).
Map<String, dynamic> routeMeTransferPendingConsent() => {
      'patientRef': 'SYN-75-08IV-121-01',
      'organization': {'moCode': '08IV', 'moName': 'Онкоцентр', 'profileCode': '121', 'profileName': 'Хирургические для взрослых'},
      'forecast': {'p50Days': 1.5, 'p90Days': 20.7, 'fromModel': true},
      'alternatives': [
        {
          'mo': {'moCode': '031N', 'name': 'Военный госпиталь', 'regionKato': '75'},
          'p50Days': 2.3,
          'p90Days': 10.4,
          'pRefusal': 0.51,
          'distanceKm': 0,
        },
        {
          'mo': {'moCode': '22GN', 'name': 'Достар Мед', 'regionKato': '75'},
          'p50Days': 3.7,
          'p90Days': 14.7,
          'pRefusal': 0.41,
          'distanceKm': 0,
        },
        {
          'mo': {'moCode': '227G', 'name': 'Медцентр Рахат', 'regionKato': '75'},
          'p50Days': 6.4,
          'p90Days': 21.4,
          'pRefusal': 0.55,
          'distanceKm': 0,
        },
      ],
      'decisions': [
        {
          'decisionId': '34dc8035-192c-4cee-8eb2-68e8e1cba559',
          'role': 'doctor',
          'recordedAt': '2026-09-25T19:26:38.487527+00:00',
          'toMoCode': '22GN',
          'toMoName': 'Достар Мед',
          'reason': 'ozhidanie_koroche',
          'kind': 'redirect',
          'patientConsent': 'pending',
          'severe': false,
        },
        {
          'decisionId': 'df3238d3-f033-4070-b444-3d61773e7422',
          'role': 'doctor',
          'recordedAt': '2026-09-25T19:14:39.387079+00:00',
          'toMoCode': '08IV',
          'toMoName': 'Онкоцентр',
          'reason': 'профиль требует именно этой клиники',
          'kind': 'keep',
          'patientConsent': null,
          'severe': false,
        },
      ],
      'progress': {
        'status': 'transfer_pending_consent',
        'originMoCode': '08IV',
        'responsibleMoCode': '08IV',
        'responsibleMoName': 'Онкоцентр',
        'transfer': {
          'decisionId': 'd2a6afd6-c158-49ab-96ef-385974a9fe4a',
          'toMoCode': '031N',
          'toMoName': 'Военный госпиталь',
          'severe': false,
          'reason': 'ozhidanie koroche, profil sovpadaet',
          'proposedAt': '2026-09-22T07:14:48.883134+00:00',
          'consentAt': null,
          'confirmedAt': null,
          'plannedAt': null,
          'admittedAt': null,
        },
        'lastAttempt': null,
        'prefersCurrent': false,
        'closedReason': null,
        'closedAt': null,
        'overdue': false,
        'allowed': ['accept_transfer', 'decline_transfer', 'withdraw'],
        // блокируем 031N — он уже и есть предлагаемая цель перевода; проверяем, что offeredAlternatives его вычитает
        'blockedMoCodes': ['031N'],
        'side': 'citizen',
      },
      'journal': [
        {
          'id': '34dc8035-192c-4cee-8eb2-68e8e1cba559',
          'at': '2026-09-25T19:26:38.487527+00:00',
          'kind': 'redirect',
          'role': 'doctor',
          'moCode': '22GN',
          'moName': 'Достар Мед',
          'reason': 'ozhidanie_koroche',
          'plannedAt': null,
          'severe': false,
        },
        {
          'id': 'cc0f88c0-947f-41e2-b2b6-648d66a48429',
          'at': '2026-09-25T19:14:30.350524+00:00',
          'kind': 'still_waiting',
          'role': 'citizen',
          'moCode': null,
          'moName': null,
          'reason': null,
          'plannedAt': null,
          'severe': false,
        },
      ],
    };

void main() {
  group('RouteProgress / RouteTransfer / RouteTransferAttempt (real sample, route-me.json)', () {
    final route = PatientRoute.fromJson(routeMeTransferPendingConsent());

    test('progress parses status, allowed, blockedMoCodes and side', () {
      expect(route.progress, isNotNull);
      expect(route.progress!.status, RouteCodes.statusTransferPendingConsent);
      expect(route.progress!.originMoCode, '08IV');
      expect(route.progress!.responsibleMoCode, '08IV');
      expect(route.progress!.allowed, ['accept_transfer', 'decline_transfer', 'withdraw']);
      expect(route.progress!.blockedMoCodes, ['031N']);
      expect(route.progress!.side, 'citizen');
      expect(route.progress!.prefersCurrent, isFalse);
      expect(route.progress!.overdue, isFalse);
      expect(route.progress!.closedReason, isNull);
      expect(route.progress!.lastAttempt, isNull);
    });

    test('transfer parses the pending redirect proposal', () {
      final transfer = route.progress!.transfer!;
      expect(transfer.decisionId, 'd2a6afd6-c158-49ab-96ef-385974a9fe4a');
      expect(transfer.toMoCode, '031N');
      expect(transfer.toMoName, 'Военный госпиталь');
      expect(transfer.severe, isFalse);
      expect(transfer.proposedAt, '2026-09-22T07:14:48.883134+00:00');
      expect(transfer.confirmedAt, isNull);
      expect(transfer.plannedAt, isNull);
    });

    test('journal parses newest-first entries with nullable moCode/moName/reason', () {
      expect(route.journal, hasLength(2));
      expect(route.journal.first.kind, 'redirect');
      expect(route.journal.first.role, 'doctor');
      expect(route.journal.first.moCode, '22GN');
      expect(route.journal.last.kind, 'still_waiting');
      expect(route.journal.last.moCode, isNull);
      expect(route.journal.last.reason, isNull);
    });

    test('decisions carry patientConsent and severe', () {
      final redirect = route.decisions.firstWhere((d) => d.kind == 'redirect');
      expect(redirect.patientConsent, 'pending');
      expect(redirect.severe, isFalse);
      final keep = route.decisions.firstWhere((d) => d.kind == 'keep');
      expect(keep.patientConsent, isNull);
      expect(keep.severe, isFalse);
    });

    test('can() reflects progress.allowed exactly', () {
      expect(route.can('accept_transfer'), isTrue);
      expect(route.can('decline_transfer'), isTrue);
      expect(route.can('withdraw'), isTrue);
      expect(route.can('redirect'), isFalse);
      expect(route.can('keep'), isFalse);
      expect(route.can('unknown_future_action'), isFalse);
    });

    test('offeredAlternatives removes hospitals in progress.blockedMoCodes', () {
      expect(route.alternatives.map((a) => a.moCode), containsAll(['031N', '22GN', '227G']));
      expect(route.offeredAlternatives.map((a) => a.moCode), ['22GN', '227G']);
    });
  });

  group('tolerant parsing', () {
    test('a route without progress/journal (old server) does not crash: progress is null, journal is empty', () {
      final route = PatientRoute.fromJson({
        'patientRef': 'SYN-75-028B-381-01',
        'organization': {'moCode': '028B', 'moName': 'Институт', 'profileCode': '381', 'profileName': 'Офтальмология'},
        'forecast': {'p50Days': 47, 'p90Days': 106},
      });
      expect(route.progress, isNull);
      expect(route.journal, isEmpty);
      expect(route.can('redirect'), isFalse, reason: 'null progress → can() никогда не падает, всегда false');
      expect(route.offeredAlternatives, isEmpty, reason: 'нет progress, нет alternatives — просто пустой список');
    });

    test('offeredAlternatives returns alternatives unchanged when blockedMoCodes is empty', () {
      final route = PatientRoute.fromJson({
        'patientRef': 'SYN-75-028B-381-01',
        'organization': {'moCode': '028B', 'moName': 'Институт', 'profileCode': '381', 'profileName': 'Офтальмология'},
        'forecast': {'p50Days': 47, 'p90Days': 106},
        'alternatives': [
          {
            'mo': {'moCode': 'X', 'name': 'X'},
            'p50Days': 1.0,
            'p90Days': 2.0,
            'pRefusal': 0.1,
            'distanceKm': 0,
          },
        ],
        'progress': {'status': 'waiting', 'originMoCode': '028B', 'responsibleMoCode': '028B', 'responsibleMoName': 'Институт', 'allowed': [], 'side': 'origin'},
      });
      expect(route.offeredAlternatives, hasLength(1));
    });

    test('RouteTransfer.toMoName falls back to the code when absent', () {
      final transfer = RouteTransfer.fromJson({'decisionId': 'd', 'toMoCode': '22GN', 'proposedAt': '2026-01-01T00:00:00+00:00'});
      expect(transfer.toMoName, '22GN');
      expect(transfer.severe, isFalse);
      expect(transfer.reason, isNull);
    });

    test('RouteTransferAttempt parses a rejection', () {
      final attempt = RouteTransferAttempt.fromJson({
        'outcome': 'rejected',
        'toMoCode': '22GN',
        'toMoName': 'Достар Мед',
        'at': '2026-09-20T10:00:00+00:00',
        'reason': 'нет мест по профилю',
      });
      expect(attempt.outcome, RouteCodes.attemptRejected);
      expect(attempt.reason, 'нет мест по профилю');
    });

    test('an unknown progress.status string is kept as-is, not rejected', () {
      final progress = RouteProgress.fromJson({
        'status': 'some_future_status',
        'originMoCode': '028B',
        'responsibleMoCode': '028B',
        'responsibleMoName': 'Институт',
        'allowed': ['withdraw'],
        'side': 'citizen',
      });
      expect(progress.status, 'some_future_status');
      expect(progress.allowed, ['withdraw']);
    });
  });

  group('RouteCodes additions (§5.2) carry the exact server strings', () {
    test('route status codes', () {
      expect(RouteCodes.statusWaiting, 'waiting');
      expect(RouteCodes.statusKept, 'kept');
      expect(RouteCodes.statusTransferPendingConsent, 'transfer_pending_consent');
      expect(RouteCodes.statusTransferPendingConfirmation, 'transfer_pending_confirmation');
      expect(RouteCodes.statusTransferred, 'transferred');
      expect(RouteCodes.statusAdmitted, 'admitted');
      expect(RouteCodes.statusWithdrawalRequested, 'withdrawal_requested');
      expect(RouteCodes.statusClosed, 'closed');
    });

    test('action codes', () {
      expect(RouteCodes.actionRequestTransfer, 'request_transfer');
      expect(RouteCodes.actionAcceptTransfer, 'accept_transfer');
      expect(RouteCodes.actionDeclineTransfer, 'decline_transfer');
      expect(RouteCodes.actionCancelTransfer, 'cancel_transfer');
      expect(RouteCodes.actionClose, 'close');
      expect(RouteCodes.actionConfirm, 'confirm');
      expect(RouteCodes.actionReject, 'reject');
      expect(RouteCodes.actionReschedule, 'reschedule');
      expect(RouteCodes.actionAdmit, 'admit');
      expect(RouteCodes.actionNoShow, 'no_show');
      expect(RouteCodes.actionDischarge, 'discharge');
    });

    test('side codes', () {
      expect(RouteCodes.sideNone, 'none');
      expect(RouteCodes.sideCitizen, 'citizen');
      expect(RouteCodes.sideOrigin, 'origin');
      expect(RouteCodes.sideReceiving, 'receiving');
    });

    test('new worklist flags and next-action codes', () {
      expect(RouteCodes.flagTransferPending, 'transfer_pending');
      expect(RouteCodes.flagTransferredIn, 'transferred_in');
      expect(RouteCodes.flagPrefersCurrent, 'prefers_current');
      expect(RouteCodes.flagDateOverdue, 'date_overdue');
      expect(RouteCodes.nextAwaitConsent, 'await_consent');
      expect(RouteCodes.nextConfirmAdmission, 'confirm_admission');
      expect(RouteCodes.nextDischargeWhenDone, 'discharge_when_done');
      expect(RouteCodes.nextConfirmWithdrawal, 'confirm_withdrawal');
    });

    test('new signal kind and stage code', () {
      expect(RouteCodes.preferCurrent, 'prefer_current');
      expect(RouteCodes.transferStage, 'transfer');
    });
  });
}
