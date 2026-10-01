import 'package:darumen/api/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/api/api_fixtures.dart';

void main() {
  group('CitizenNotifications (§3.7, real sample route-me-notifications.json)', () {
    // Урезано до двух характерных строк настоящего ответа: redirect (needsAction) и tests_expiring (count, moName=null).
    final notifications = CitizenNotifications.fromJson({
      'unread': 4,
      'items': [
        {
          'id': 'd2a6afd6-c158-49ab-96ef-385974a9fe4a',
          'kind': 'redirect',
          'at': '2026-09-22T07:14:48.883134+00:00',
          'moName': 'Военный госпиталь',
          'plannedAt': null,
          'reason': 'ozhidanie koroche, profil sovpadaet',
          'needsAction': true,
          'read': false,
          'count': null,
        },
        {
          'id': '733d41f7-fa74-164e-b0f5-6fe56cf7d470',
          'kind': 'tests_expiring',
          'at': '2026-10-01T17:59:38.2107175+00:00',
          'moName': null,
          'plannedAt': '2025-03-31',
          'reason': null,
          'needsAction': false,
          'read': false,
          'count': 7,
        },
      ],
    });

    test('unread count and item list length', () {
      expect(notifications.unread, 4);
      expect(notifications.items, hasLength(2));
    });

    test('a redirect awaiting the citizen answer has needsAction true', () {
      final item = notifications.items.first;
      expect(item.kind, 'redirect');
      expect(item.needsAction, isTrue);
      expect(item.read, isFalse);
      expect(item.count, isNull);
      expect(item.moName, 'Военный госпиталь');
    });

    test('tests_expiring carries a count and no moName', () {
      final item = notifications.items.last;
      expect(item.kind, RouteCodes.notificationTestsExpiring);
      expect(item.count, 7);
      expect(item.moName, isNull);
      expect(item.plannedAt, '2025-03-31');
      expect(item.needsAction, isFalse);
    });

    test('no route in the region → unread 0, items empty (§3.7)', () {
      final empty = CitizenNotifications.fromJson(const {'unread': 0, 'items': []});
      expect(empty.unread, 0);
      expect(empty.items, isEmpty);
    });

    test('scribe_consent carries the consent requestId as id and needs an answer; scribe_leaflet does not', () {
      final parsed = CitizenNotifications.fromJson({
        'unread': 1,
        'items': [
          {'id': 'r-1', 'kind': 'scribe_consent', 'at': '2026-10-01T09:00:00+00:00', 'moName': 'Институт', 'reason': 'плановый приём', 'needsAction': true, 'read': false},
          {'id': 'h-1', 'kind': 'scribe_leaflet', 'at': '2026-10-01T10:00:00+00:00', 'moName': 'Институт', 'needsAction': false, 'read': true},
        ],
      });
      expect(parsed.items.first.kind, RouteCodes.notificationScribeConsent);
      expect(parsed.items.first.id, 'r-1');
      expect(parsed.items.first.needsAction, isTrue);
      expect(parsed.items.first.reason, 'плановый приём');
      expect(parsed.items.last.kind, RouteCodes.notificationScribeLeaflet);
      expect(parsed.items.last.read, isTrue);
      expect(parsed.items.last.plannedAt, isNull);
      expect(parsed.items.last.count, isNull);
    });

    test('defaults are safe when the envelope fields are absent', () {
      final defaulted = CitizenNotifications.fromJson(const {});
      expect(defaulted.unread, 0);
      expect(defaulted.items, isEmpty);
    });

    test('an item with only id/kind/at parses with safe defaults', () {
      final item = CitizenNotification.fromJson({'id': 'n-1', 'kind': 'close', 'at': '2026-10-01T09:00:00+00:00'});
      expect(item.kind, RouteCodes.journalClose);
      expect(item.needsAction, isFalse);
      expect(item.read, isFalse);
      expect(item.moName, isNull);
      expect(item.plannedAt, isNull);
      expect(item.reason, isNull);
      expect(item.count, isNull);
    });

    test('confirm and reschedule carry the planned date', () {
      final item = CitizenNotification.fromJson({'id': 'n-2', 'kind': 'confirm', 'at': 'x', 'moName': 'Достар Мед', 'plannedAt': '2026-10-10'});
      expect(item.plannedAt, '2026-10-10');
      expect(item.moName, 'Достар Мед');
    });

    test('items are unmodifiable — the envelope is immutable', () {
      final parsed = CitizenNotifications.fromJson({
        'items': [
          {'id': 'a', 'kind': 'keep', 'at': 'x'},
        ],
      });
      expect(() => parsed.items.clear(), throwsUnsupportedError);
    });
  });

  group('NotificationBell (§3.8, doctor bell)', () {
    test('parses pendingIncomingCount, confirmations, discharges and patientSignals', () {
      final bell = NotificationBell.fromJson({
        'pendingIncomingCount': 1,
        'unreadConfirmations': [
          {'decisionId': 'd1', 'patientRef': 'SYN-75-028B-381-01', 'toMoCode': '22GN', 'toMoName': 'Достар Мед', 'confirmedAt': '2026-10-01T09:00:00+00:00', 'read': false},
        ],
        'unreadDischarges': [
          {
            'decisionId': 'd2',
            'patientRef': 'SYN-75-028B-381-02',
            'fromMoCode': '22GN',
            'fromMoName': 'Достар Мед',
            'summary': 'лечение завершено',
            'dischargedAt': '2026-10-01T10:00:00+00:00',
            'read': false,
          },
        ],
        'patientSignals': [
          {'id': 's1', 'patientRef': 'SYN-75-028B-381-03', 'kind': 'request', 'moCode': '22GN', 'moName': 'Достар Мед', 'comment': 'живу рядом', 'at': '2026-10-01T11:00:00+00:00'},
        ],
      });
      expect(bell.pendingIncomingCount, 1);
      expect(bell.unreadConfirmations.single.toMoName, 'Достар Мед');
      expect(bell.unreadDischarges.single.summary, 'лечение завершено');
      expect(bell.patientSignals.single.kind, 'request');
      expect(bell.patientSignals.single.comment, 'живу рядом');
    });

    test('patientSignals is nullable in the DTO — absent means an empty list, not a crash', () {
      final bell = NotificationBell.fromJson({'pendingIncomingCount': 0, 'unreadConfirmations': [], 'unreadDischarges': []});
      expect(bell.patientSignals, isEmpty);
    });

    test('no hospital in scope → zeros and empty lists (§3.8), not an error', () {
      final bell = NotificationBell.fromJson(const {});
      expect(bell.pendingIncomingCount, 0);
      expect(bell.unreadConfirmations, isEmpty);
      expect(bell.unreadDischarges, isEmpty);
      expect(bell.patientSignals, isEmpty);
    });

    test('confirmations and discharges tolerate missing names and flags', () {
      final bell = NotificationBell.fromJson({
        'unreadConfirmations': [
          {'decisionId': 'd1', 'patientRef': 'SYN-75-028B-381-01', 'toMoCode': '22GN', 'confirmedAt': '2026-10-01T09:00:00+00:00'},
        ],
        'unreadDischarges': [
          {'decisionId': 'd2', 'patientRef': 'SYN-75-028B-381-02', 'fromMoCode': '22GN', 'dischargedAt': '2026-10-01T10:00:00+00:00'},
        ],
        'patientSignals': null,
      });
      expect(bell.unreadConfirmations.single.toMoName, '22GN', reason: 'имя — фолбэк на код');
      expect(bell.unreadConfirmations.single.read, isFalse);
      expect(bell.unreadDischarges.single.fromMoName, '22GN');
      expect(bell.unreadDischarges.single.summary, '');
      expect(bell.unreadDischarges.single.read, isFalse);
      expect(bell.patientSignals, isEmpty, reason: 'null в DTO — пустой список');
    });

    test('totalUnread sums pending incoming, confirmations, discharges and patient signals', () {
      final bell = NotificationBell.fromJson({
        'pendingIncomingCount': 2,
        'unreadConfirmations': [
          {'decisionId': 'd1', 'patientRef': 'r', 'toMoCode': 'a', 'confirmedAt': 'x', 'read': false},
        ],
        'unreadDischarges': [],
        'patientSignals': [
          {'id': 's1', 'patientRef': 'r', 'kind': 'withdraw', 'at': 'x'},
          {'id': 's2', 'patientRef': 'r', 'kind': 'request', 'at': 'x'},
        ],
      });
      expect(bell.totalUnread, 5);
      expect(NotificationBell.fromJson(const {}).totalUnread, 0);
    });

    test('a discharge keeps its summary and the discharging hospital; the lists are unmodifiable', () {
      final bell = NotificationBell.fromJson({
        'unreadDischarges': [
          {'decisionId': 'd2', 'patientRef': 'r', 'fromMoCode': '22GN', 'fromMoName': 'Достар Мед', 'summary': 'эпикриз', 'dischargedAt': 'x', 'read': false},
        ],
      });
      final discharge = bell.unreadDischarges.single;
      expect(discharge.decisionId, 'd2');
      expect(discharge.fromMoCode, '22GN');
      expect(discharge.dischargedAt, 'x');
      expect(() => bell.unreadDischarges.clear(), throwsUnsupportedError);
      expect(() => bell.patientSignals.clear(), throwsUnsupportedError);
    });

    test('patient event kinds extend beyond journal kinds (scribe_granted etc.)', () {
      final event = PatientEvent.fromJson({'id': 's2', 'patientRef': 'SYN-75-028B-381-04', 'kind': 'scribe_granted', 'at': '2026-10-01T11:00:00+00:00'});
      expect(event.kind, RouteCodes.patientEventScribeGranted);
      expect(event.moCode, isNull);
      expect(event.comment, isNull);
    });
  });

  group('real response (test/fixtures/api/route-me-notifications.json)', () {
    test('parses the whole feed in server order; the redirect awaiting an answer is the current transfer', () {
      final feed = CitizenNotifications.fromJson(apiFixtureObject('route-me-notifications.json'));
      final route = PatientRoute.fromJson(apiFixtureObject('route-me.json'));
      expect(feed.unread, 4);
      expect(feed.items.map((i) => i.kind), ['redirect', 'tests_expiring', 'redirect', 'keep']);
      expect(feed.items.every((i) => RouteCodes.notificationKinds.contains(i.kind)), isTrue);
      expect(feed.items.where((i) => i.needsAction).single.id, route.progress!.transfer!.decisionId);
      expect(feed.items.where((i) => !i.read), hasLength(feed.unread));
    });
  });
}
