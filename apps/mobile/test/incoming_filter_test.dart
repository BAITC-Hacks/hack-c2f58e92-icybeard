import 'package:darumen/api/models.dart';
import 'package:darumen/widgets/incoming/incoming_filter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Строка входящего направления с осмысленными значениями по умолчанию (как в ответе API).
IncomingReferral referral(
  String id, {
  String ref = 'SYN-75-028B-381-01',
  String fromMoCode = '028B',
  String fromMoName = 'ТОО "Казахский научно-исследовательский институт глазных болезней"',
  String profileCode = '381',
  bool severe = false,
  String consent = 'accepted',
  bool confirmed = false,
  bool admitted = false,
  bool discharged = false,
  String? status = 'transfer_pending_confirmation',
  String? closedReason,
  List<String> allowed = const [],
}) =>
    IncomingReferral.fromJson({
      'decisionId': id,
      'patientRef': ref,
      'fromMoCode': fromMoCode,
      'fromMoName': fromMoName,
      'profileCode': profileCode,
      'recordedAt': '2026-10-01T09:00:00+00:00',
      'severe': severe,
      'patientConsent': consent,
      'confirmed': confirmed,
      'admitted': admitted,
      'discharged': discharged,
      'status': status,
      'closedReason': closedReason,
      'allowed': allowed,
    });

void main() {
  group('incomingStageOf — the web stageOf of IncomingReferralsView.vue', () {
    test('consent pending → consent; accepted → confirm', () {
      expect(incomingStageOf(referral('a', consent: 'pending', status: 'transfer_pending_consent')), IncomingStage.consent);
      expect(incomingStageOf(referral('b')), IncomingStage.confirm);
    });

    test('confirmed → scheduled, admitted → admitted', () {
      expect(incomingStageOf(referral('c', confirmed: true, status: 'transferred')), IncomingStage.scheduled);
      expect(incomingStageOf(referral('d', confirmed: true, admitted: true, status: 'admitted')), IncomingStage.admitted);
      expect(incomingStageOf(referral('e', confirmed: true, status: 'admitted')), IncomingStage.admitted, reason: 'статус без флага admitted');
    });

    test('discharged, any closed reason or status closed → closed (wins over admitted)', () {
      expect(incomingStageOf(referral('f', confirmed: true, admitted: true, discharged: true, status: 'closed', closedReason: 'discharged')), IncomingStage.closed);
      expect(incomingStageOf(referral('g', confirmed: true, status: 'closed', closedReason: 'no_show')), IncomingStage.closed);
      expect(incomingStageOf(referral('h', confirmed: true, status: 'closed')), IncomingStage.closed);
    });

    test('an unknown status from a newer server falls back to the consent/confirmation flags, never throws', () {
      expect(incomingStageOf(referral('i', status: 'something_new')), IncomingStage.confirm);
      expect(incomingStageOf(referral('j', consent: '', status: null)), IncomingStage.consent);
    });
  });

  group('incomingStageCounts and incomingSevereCount', () {
    test('counts every stage, zero for absent ones; empty list → all zero', () {
      final items = [
        referral('a', consent: 'pending'),
        referral('b'),
        referral('c'),
        referral('d', confirmed: true, status: 'transferred', severe: true),
        referral('e', confirmed: true, status: 'closed', closedReason: 'discharged', discharged: true, severe: true),
      ];
      final counts = incomingStageCounts(items);
      expect(counts, {
        IncomingStage.consent: 1,
        IncomingStage.confirm: 2,
        IncomingStage.scheduled: 1,
        IncomingStage.admitted: 0,
        IncomingStage.closed: 1,
      });
      expect(incomingSevereCount(items), 2);
      expect(incomingStageCounts(const []).values, everyElement(0));
      expect(incomingSevereCount(const []), 0);
    });
  });

  group('IncomingFilter', () {
    final items = [
      referral('sev', ref: 'SYN-75-028B-381-03', severe: true),
      referral('pend', ref: 'SYN-75-028B-381-04', consent: 'pending', status: 'transfer_pending_consent'),
      referral('sched', ref: 'SYN-75-22GN-152-01', fromMoCode: '22GN', fromMoName: 'ТОО "Достар Мед"', profileCode: '152', confirmed: true, status: 'transferred'),
    ];
    const names = {'381': 'Офтальмологические', '152': 'Кардиологические'};

    test('none keeps the server order and every item; the result is a new list', () {
      final shown = applyIncomingFilter(items, IncomingFilter.none, names);
      expect(shown.map((i) => i.decisionId), ['sev', 'pend', 'sched']);
      expect(identical(shown, items), isFalse);
      expect(IncomingFilter.none.isActive, isFalse);
    });

    test('stage, severe-only and query combine with AND', () {
      expect(applyIncomingFilter(items, const IncomingFilter(stage: IncomingStage.confirm), names).map((i) => i.decisionId), ['sev']);
      expect(applyIncomingFilter(items, const IncomingFilter(severeOnly: true), names).map((i) => i.decisionId), ['sev']);
      expect(applyIncomingFilter(items, const IncomingFilter(stage: IncomingStage.consent, severeOnly: true), names), isEmpty);
    });

    test('search matches the ref, the sender name and code, and the profile name, case-insensitively (Cyrillic too)', () {
      List<String> find(String q) => applyIncomingFilter(items, IncomingFilter(query: q), names).map((i) => i.decisionId).toList();
      expect(find('381-04'), ['pend']);
      expect(find('syn-75-22gn'), ['sched']);
      expect(find('достар'), ['sched']);
      expect(find('22gn'), ['sched']);
      expect(find('КАРДИО'), ['sched']);
      expect(find('  глазных  '), ['sev', 'pend'], reason: 'пробелы по краям не мешают');
      expect(find('нет такого'), isEmpty);
    });

    test('search tolerates special characters and an unknown profile code (matched by the code itself)', () {
      expect(applyIncomingFilter(items, const IncomingFilter(query: '"Достар'), names).map((i) => i.decisionId), ['sched']);
      expect(applyIncomingFilter(items, const IncomingFilter(query: '(.*)'), names), isEmpty, reason: 'не регулярное выражение');
      expect(applyIncomingFilter(items, const IncomingFilter(query: '152'), const {}).map((i) => i.decisionId), ['sched']);
    });

    test('withStage / withSevereOnly / withQuery return new filters; null stage clears it; isActive follows', () {
      const base = IncomingFilter();
      final staged = base.withStage(IncomingStage.closed);
      expect(staged.stage, IncomingStage.closed);
      expect(base.stage, isNull, reason: 'исходный фильтр не меняется');
      expect(staged.withStage(null).stage, isNull);
      expect(base.withSevereOnly(true).severeOnly, isTrue);
      expect(base.withQuery('x').query, 'x');
      expect(staged.isActive, isTrue);
      expect(base.withQuery('   ').isActive, isFalse, reason: 'пустой поиск — не фильтр');
    });

    test('a large list (10 000 rows) filters quickly and keeps the order', () {
      final big = [for (var i = 0; i < 10000; i++) referral('id-$i', ref: 'SYN-75-028B-381-${i.toString().padLeft(5, '0')}', severe: i.isEven)];
      final watch = Stopwatch()..start();
      final shown = applyIncomingFilter(big, const IncomingFilter(severeOnly: true, query: 'syn-75'), names);
      watch.stop();
      expect(shown, hasLength(5000));
      expect(shown.first.decisionId, 'id-0');
      expect(watch.elapsedMilliseconds, lessThan(1000));
    });
  });

  group('incomingActions — buttons only from item.allowed, in the web order', () {
    test('order: confirm, reject, admit, discharge, reschedule, no_show; unknown and close codes are not card buttons', () {
      final item = referral('a', allowed: ['reschedule', 'no_show', 'discharge', 'admit', 'close', 'something_new']);
      expect(incomingActions(item), ['admit', 'discharge', 'reschedule', 'no_show']);
      expect(incomingActions(referral('b', allowed: ['reject', 'confirm'])), ['confirm', 'reject']);
      expect(incomingActions(referral('c')), isEmpty);
    });
  });
}
