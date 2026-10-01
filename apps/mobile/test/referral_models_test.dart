import 'package:darumen/api/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/api/api_fixtures.dart';

void main() {
  group('IncomingReferral (§3.6, §5.8 — bare array from GET /journal/referrals/incoming)', () {
    test('parses a full row exactly as the API documents it', () {
      final r = IncomingReferral.fromJson({
        'decisionId': 'd2a6afd6-c158-49ab-96ef-385974a9fe4a',
        'patientRef': 'SYN-75-028B-381-01',
        'fromMoCode': '028B',
        'fromMoName': 'Институт глазных болезней',
        'profileCode': '381',
        'reason': 'в принимающей больнице очередь короче',
        'recordedAt': '2026-09-25T19:26:38.487527+00:00',
        'severe': false,
        'patientConsent': 'accepted',
        'confirmed': false,
        'confirmedAt': null,
        'discharged': false,
        'dischargedAt': null,
        'status': 'transfer_pending_confirmation',
        'plannedAt': null,
        'admitted': false,
        'overdue': false,
        'allowed': ['confirm', 'reject'],
        'closedReason': null,
      });
      expect(r.decisionId, 'd2a6afd6-c158-49ab-96ef-385974a9fe4a');
      expect(r.fromMoCode, '028B');
      expect(r.patientConsent, 'accepted');
      expect(r.status, RouteCodes.statusTransferPendingConfirmation);
      expect(r.allowed, ['confirm', 'reject']);
      expect(r.severe, isFalse);
      expect(r.confirmed, isFalse);
      expect(r.admitted, isFalse);
      expect(r.overdue, isFalse);
    });

    test('can() reflects allowed exactly, like PatientRoute.can', () {
      final r = IncomingReferral.fromJson({
        'decisionId': 'd', 'patientRef': 'SYN-75-028B-381-01', 'fromMoCode': '028B', 'profileCode': '381',
        'recordedAt': '2026-01-01T00:00:00+00:00', 'patientConsent': 'pending', 'allowed': ['confirm', 'reject'], //
      });
      expect(r.can('confirm'), isTrue);
      expect(r.can('reject'), isTrue);
      expect(r.can('admit'), isFalse);
    });

    test('a confirmed, severe, discharged row parses the discharge fields', () {
      final r = IncomingReferral.fromJson({
        'decisionId': 'd',
        'patientRef': 'SYN-75-028B-381-01',
        'fromMoCode': '028B',
        'profileCode': '381',
        'reason': 'тяжёлый случай',
        'recordedAt': '2026-01-01T00:00:00+00:00',
        'severe': true,
        'patientConsent': 'accepted',
        'confirmed': true,
        'confirmedAt': '2026-01-02T00:00:00+00:00',
        'discharged': true,
        'dischargedAt': '2026-01-10T00:00:00+00:00',
        'status': 'closed',
        'plannedAt': '2026-01-05',
        'admitted': true,
        'overdue': false,
        'allowed': [],
        'closedReason': 'discharged',
      });
      expect(r.severe, isTrue);
      expect(r.discharged, isTrue);
      expect(r.dischargedAt, '2026-01-10T00:00:00+00:00');
      expect(r.closedReason, RouteCodes.closedDischarged);
      expect(r.allowed, isEmpty);
    });

    test('fromMoName falls back to fromMoCode when absent; optional fields default safely', () {
      final r = IncomingReferral.fromJson({
        'decisionId': 'd', 'patientRef': 'SYN-75-028B-381-01', 'fromMoCode': '028B', 'profileCode': '381', //
        'recordedAt': '2026-01-01T00:00:00+00:00', 'patientConsent': 'pending', //
      });
      expect(r.fromMoName, '028B');
      expect(r.reason, isNull);
      expect(r.status, isNull);
      expect(r.plannedAt, isNull);
      expect(r.closedReason, isNull);
      expect(r.allowed, isEmpty);
      expect(r.severe, isFalse);
      expect(r.confirmed, isFalse);
      expect(r.discharged, isFalse);
      expect(r.admitted, isFalse);
      expect(r.overdue, isFalse);
    });

    test('the real response for a hospital without incoming transfers (incoming-028B.json) is an empty bare array', () {
      final list = (apiFixture('incoming-028B.json') as List<dynamic>).map((e) => IncomingReferral.fromJson(e as Map<String, dynamic>)).toList();
      expect(list, isEmpty);
    });

    test('allowed is unmodifiable and keeps the server order', () {
      final r = IncomingReferral.fromJson({'decisionId': 'd', 'patientRef': 'p', 'allowed': ['admit', 'discharge', 'reschedule']});
      expect(r.allowed, ['admit', 'discharge', 'reschedule']);
      expect(() => r.allowed.add('close'), throwsUnsupportedError);
      expect(RouteCodes.actions, containsAll(r.allowed));
    });
  });
}
