import 'package:darumen/api/models.dart';
import 'package:darumen/l10n/strings.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/api/api_fixtures.dart';

void main() {
  test('predict response parses the API shape', () {
    final json = {
      'p50Days': 101.0, 'p90Days': 122.6, 'pWithin30Days': 0.015, 'pRefusal': 0.5,
      'queue': {'len': 1784, 'ageP50': 47, 'throughputPerDay': 11.36},
      'explanation': {'summary': 'Базовое ожидание 14 дн.', 'factors': [{'name': 'mo_code', 'contribution': 26.1, 'text': 'организация: 028B'}]},
      'model': {'name': 'wait_quantile', 'version': '1.0.0', 'trainedThrough': '2025-02-28'},
    };
    final p = PredictResponse.fromJson(json);
    expect(p.p50Days, 101.0);
    expect(p.queue!.len, 1784);
    expect(p.explanation.factors.single.contribution, 26.1);
    expect(p.model.trainedThrough, '2025-02-28');
  });

  test('worklist and medicines parse with optional fields', () {
    final w = WorklistItem.fromJson({
      'patientRef': 'SYN-75-028B-01', 'stage': 'ожидает', 'expectedDate': null, 'riskFlags': ['stuck_over_30'], 'priority': 12,
      'nextAction': 'уточнить дату', 'nextActionCode': 'clarify_date', 'explanation': 'очередь 1784', 'moCode': '028B', 'moName': 'Институт', 'profileCode': '381', 'daysWaiting': 72,
    });
    expect(w.expectedDate, isNull);
    expect(w.riskFlags, ['stuck_over_30']);
    expect(w.nextActionCode, 'clarify_date');
    // старый ответ без кода — подпись API как есть, без падения
    expect(WorklistItem.fromJson({
      'patientRef': 'SYN-75-028B-381-02', 'stage': 'ожидает', 'riskFlags': [], 'priority': 1,
      'nextAction': 'ждать вызова', 'explanation': '', 'moCode': '028B', 'profileCode': '381', 'daysWaiting': 3,
    }).nextActionCode, '');
    expect(S.of('kk').nextActionText('wait_for_call', 'ждать вызова'), 'шақыруды күту');
    expect(S.of('kk').nextActionText('', 'ждать вызова'), 'ждать вызова');
    // открытый сигнал пациента в строке списка
    final signalled = WorklistItem.fromJson({
      'patientRef': 'SYN-75-028B-381-03', 'stage': 'ожидает', 'riskFlags': ['patient_signal'], 'priority': 15,
      'nextAction': 'ждать вызова', 'explanation': '', 'moCode': '028B', 'profileCode': '381', 'daysWaiting': 40,
      'patientSignal': {'kind': 'request_redirect', 'toMoCode': '22GN', 'toMoName': 'Больница №2', 'comment': 'живу рядом', 'recordedAt': '2026-09-25T10:00:00+00:00'},
    });
    expect(signalled.patientSignal?.toMoName, 'Больница №2');
    expect(signalled.riskFlags, contains(RouteCodes.patientSignalFlag));
  });

  test('route parses citizen signals and the validation prompt', () {
    final route = PatientRoute.fromJson({
      'patientRef': 'SYN-75-028B-381-01',
      'organization': {'moCode': '028B', 'moName': 'Институт', 'profileCode': '381', 'profileName': 'Офтальмология'},
      'forecast': {'p50Days': 47, 'p90Days': 106, 'fromModel': true},
      'signals': [
        {'decisionId': 'a', 'recordedAt': '2026-09-25T10:00:00+00:00', 'kind': 'request_redirect', 'toMoCode': '22GN', 'toMoName': 'Больница №2', 'open': true},
        {'decisionId': 'b', 'recordedAt': '2026-09-20T10:00:00+00:00', 'kind': 'still_waiting', 'open': false},
      ],
      'validationDue': true,
    });
    expect(route.validationDue, isTrue);
    expect(route.openRequest?.toMoCode, '22GN');
    expect(route.signals, hasLength(2));
    // старый ответ без сигналов
    final plain = PatientRoute.fromJson({
      'patientRef': 'SYN-75-028B-381-01',
      'organization': {'moCode': '028B', 'moName': 'Институт', 'profileCode': '381', 'profileName': 'Офтальмология'},
      'forecast': {'p50Days': 47, 'p90Days': 106},
    });
    expect(plain.signals, isEmpty);
    expect(plain.validationDue, isFalse);
    expect(plain.openSignal, isNull);
    final c = CheckResponse.fromJson({'covered': true, 'program': 'Программа 90', 'fillDaysP50': 3, 'shortage': {'flag': false, 'score': 0.1, 'basis': 'ok'}});
    expect(c.covered, isTrue);
    expect(c.fillDaysP90, isNull);
    expect(c.shortage.score, 0.1);
  });

  group('DecisionRecord (§5.11) — actor/role/recommended/chosen and the derived event (§3.13)', () {
    // Настоящие строки journal/decisions из decisions.json и route-me.json (один и тот же пациент
    // SYN-75-08IV-121-01, origin = 08IV): redirect и keep приходят с одинаковой формой chosen — {moCode} —
    // отличить их можно только сравнением moCode с origin, зашитым в subjectId (реф).
    test('redirect: chosen.moCode differs from the origin encoded in the ref → event redirect', () {
      final r = DecisionRecord.fromJson({
        'decisionId': '34dc8035-192c-4cee-8eb2-68e8e1cba559',
        'actor': 'doctor1',
        'role': 'doctor',
        'subject': 'route',
        'subjectId': 'SYN-75-08IV-121-01',
        'recommended': {'moCode': '031N'},
        'chosen': {'moCode': '22GN'},
        'reason': 'ozhidanie_koroche',
        'recordedAt': '2026-09-25T19:26:38.487527+00:00',
      });
      expect(r.actor, 'doctor1');
      expect(r.role, 'doctor');
      expect(r.recommendedMoCode, '031N');
      expect(r.chosenMoCode, '22GN');
      expect(r.event, 'redirect');
    });

    test('keep: chosen.moCode equals the origin encoded in the ref → event keep', () {
      final r = DecisionRecord.fromJson({
        'decisionId': 'df3238d3-f033-4070-b444-3d61773e7422',
        'actor': 'doctor1',
        'role': 'doctor',
        'subject': 'route',
        'subjectId': 'SYN-75-08IV-121-01',
        'recommended': {'moCode': '031N'},
        'chosen': {'moCode': '08IV'},
        'reason': 'профиль требует именно этой клиники',
        'recordedAt': '2026-09-25T19:14:39.387079+00:00',
      });
      expect(r.event, 'keep');
    });

    test('referral: subject referral has no recommended/chosen distinction beyond moCode → event referral', () {
      final r = DecisionRecord.fromJson({
        'decisionId': 'edc3c328-0c9c-42be-a746-106e79bf8e1a',
        'actor': 'doctor1',
        'role': 'doctor',
        'subject': 'referral',
        'subjectId': '75.028B.381.11',
        'recommended': null,
        'chosen': {'moCode': '028B'},
        'reason': 'kc',
        'recordedAt': '2026-09-10T21:07:20.090004+00:00',
      });
      expect(r.recommendedMoCode, isNull);
      expect(r.chosenMoCode, '028B');
      expect(r.event, 'referral');
    });

    test('cancel transfer: chosen.cancels, no moCode, no recommended → event cancel', () {
      final r = DecisionRecord.fromJson({
        'decisionId': 'd', 'subject': 'route', 'subjectId': 'SYN-75-08IV-121-01', 'chosen': {'cancels': 't-1'}, 'recordedAt': 'x', //
      });
      expect(r.event, 'cancel');
      expect(r.chosenMoCode, isNull);
    });

    test('close: chosen.closes → event close', () {
      final r = DecisionRecord.fromJson({
        'decisionId': 'd', 'subject': 'route', 'subjectId': 'SYN-75-08IV-121-01', 'chosen': {'closes': 'withdrawn'}, 'recordedAt': 'x', //
      });
      expect(r.event, 'close');
    });

    test('confirm: chosen.confirms with moCode and plannedAt → event confirm', () {
      final r = DecisionRecord.fromJson({
        'decisionId': 'd', 'subject': 'route', 'subjectId': 'SYN-75-08IV-121-01',
        'chosen': {'moCode': '22GN', 'confirms': 't-1', 'plannedAt': '2026-10-10'}, 'recordedAt': 'x', //
      });
      expect(r.event, 'confirm');
      expect(r.chosenMoCode, '22GN');
    });

    test('reject: chosen.rejects → event reject', () {
      final r = DecisionRecord.fromJson({
        'decisionId': 'd', 'subject': 'route', 'subjectId': 'SYN-75-08IV-121-01', 'chosen': {'moCode': '22GN', 'rejects': 't-1'}, 'recordedAt': 'x', //
      });
      expect(r.event, 'reject');
    });

    test('reschedule: chosen.reschedules → event reschedule', () {
      final r = DecisionRecord.fromJson({
        'decisionId': 'd', 'subject': 'route', 'subjectId': 'SYN-75-08IV-121-01',
        'chosen': {'moCode': '22GN', 'reschedules': 't-1', 'plannedAt': '2026-10-20'}, 'recordedAt': 'x', //
      });
      expect(r.event, 'reschedule');
    });

    test('admit: chosen.admits → event admit', () {
      final r = DecisionRecord.fromJson({
        'decisionId': 'd', 'subject': 'route', 'subjectId': 'SYN-75-08IV-121-01', 'chosen': {'moCode': '22GN', 'admits': 't-1'}, 'recordedAt': 'x', //
      });
      expect(r.event, 'admit');
    });

    test('no-show: chosen.noShow → event no_show', () {
      final r = DecisionRecord.fromJson({
        'decisionId': 'd', 'subject': 'route', 'subjectId': 'SYN-75-08IV-121-01', 'chosen': {'moCode': '22GN', 'noShow': 't-1'}, 'recordedAt': 'x', //
      });
      expect(r.event, 'no_show');
    });

    test('discharge: chosen.discharges with a summary → event discharge', () {
      final r = DecisionRecord.fromJson({
        'decisionId': 'd', 'subject': 'route', 'subjectId': 'SYN-75-08IV-121-01',
        'chosen': {'moCode': '22GN', 'discharges': 't-1', 'summary': 'выписан'}, 'recordedAt': 'x', //
      });
      expect(r.event, 'discharge');
    });

    // Q-8: строки журнала по маршруту подписываются подписями вида журнала — поэтому сигнал и согласие гражданина
    // разворачиваются в те же коды, что journal[].kind (RouteJournalKinds.Build на сервере), а не в общее «signal».
    test('citizen signal: chosen.signal maps to the journal kind (request_redirect → request, …)', () {
      DecisionRecord signal(String kind) => DecisionRecord.fromJson({
            'decisionId': 'd', 'role': 'citizen', 'subject': 'route', 'subjectId': 'SYN-75-08IV-121-01',
            'chosen': {'signal': kind, 'moCode': '22GN'}, 'recommended': {'moCode': '08IV'}, 'recordedAt': 'x', //
          });
      expect(signal('request_redirect').event, RouteCodes.journalRequest);
      expect(signal('prefer_current').event, RouteCodes.journalPreferCurrent);
      expect(signal('still_waiting').event, RouteCodes.journalStillWaiting);
      expect(signal('withdraw').event, RouteCodes.journalWithdraw);
      expect(signal('treated_elsewhere').event, RouteCodes.journalTreatedElsewhere);
      expect(signal('some_future_signal').event, DecisionCodes.eventOther);
    });

    test('citizen consent: chosen.consent maps to consent_accepted / consent_declined', () {
      DecisionRecord consent(String value) => DecisionRecord.fromJson({
            'decisionId': 'd', 'role': 'citizen', 'subject': 'route', 'subjectId': 'SYN-75-08IV-121-01',
            'chosen': {'consent': value, 'decisionId': 't-1'}, 'recordedAt': 'x', //
          });
      expect(consent('accepted').event, RouteCodes.journalConsentAccepted);
      expect(consent('declined').event, RouteCodes.journalConsentDeclined);
      expect(consent('maybe').event, DecisionCodes.eventOther);
    });

    test('a signal or consent written by a non-citizen role is not the patient voice → other (as on the server)', () {
      final bySignal = DecisionRecord.fromJson({
        'decisionId': 'd', 'role': 'doctor', 'subject': 'route', 'subjectId': 'SYN-75-08IV-121-01',
        'chosen': {'signal': 'withdraw'}, 'recordedAt': 'x', //
      });
      final byConsent = DecisionRecord.fromJson({
        'decisionId': 'd', 'role': 'org_admin', 'subject': 'route', 'subjectId': 'SYN-75-08IV-121-01',
        'chosen': {'consent': 'accepted', 'decisionId': 't-1'}, 'recordedAt': 'x', //
      });
      expect(bySignal.event, DecisionCodes.eventOther);
      expect(byConsent.event, DecisionCodes.eventOther);
    });

    test('a citizen cannot write staff events: a citizen record with confirms is other', () {
      final r = DecisionRecord.fromJson({
        'decisionId': 'd', 'role': 'citizen', 'subject': 'route', 'subjectId': 'SYN-75-08IV-121-01',
        'chosen': {'moCode': '22GN', 'confirms': 't-1'}, 'recordedAt': 'x', //
      });
      expect(r.event, DecisionCodes.eventOther);
    });

    test('keep/redirect: origin comparison ignores case, severe marks a redirect, an unparsable ref gives other', () {
      DecisionRecord doctor(String ref, Map<String, dynamic> chosen) =>
          DecisionRecord.fromJson({'decisionId': 'd', 'role': 'doctor', 'subject': 'route', 'subjectId': ref, 'chosen': chosen, 'recordedAt': 'x'});
      expect(doctor('SYN-75-08iv-121-01', {'moCode': '08IV'}).event, RouteCodes.journalKeep);
      expect(doctor('SYN-75-08IV-121-01', {'moCode': '22GN', 'severe': true}).event, RouteCodes.journalRedirect);
      expect(doctor('not-a-ref', {'moCode': '22GN'}).event, DecisionCodes.eventOther);
      expect(doctor('not-a-ref', {'moCode': '22GN', 'severe': true}).event, RouteCodes.journalRedirect);
    });

    test('scribe bookkeeping: subject scribe → event scribe, hidden from the route/referral journal view', () {
      final r = DecisionRecord.fromJson({
        'decisionId': 'd', 'subject': 'scribe', 'subjectId': 'SYN-75-08IV-121-01', 'chosen': {'scribeConsent': 'granted', 'requestId': 'r-1'}, 'recordedAt': 'x', //
      });
      expect(r.event, 'scribe');
    });

    test('an unrecognized subject/shape falls back to other instead of throwing', () {
      expect(DecisionRecord.fromJson({'decisionId': 'd', 'subject': 'anomaly', 'recordedAt': 'x'}).event, 'other');
      expect(DecisionRecord.fromJson({'decisionId': 'd', 'subject': 'route', 'recordedAt': 'x'}).event, 'other', reason: 'chosen отсутствует');
      expect(
        DecisionRecord.fromJson({'decisionId': 'd', 'subject': 'route', 'subjectId': 'SYN-75-08IV-121-01', 'chosen': {'somethingNew': true}, 'recordedAt': 'x'}).event,
        'other',
      );
    });

    test('actor/role default to empty strings, not null, when absent (old server)', () {
      final r = DecisionRecord.fromJson({'decisionId': 'd', 'subject': 'referral', 'chosen': {'moCode': '028B'}, 'recordedAt': 'x'});
      expect(r.actor, '');
      expect(r.role, '');
    });

    test('recommended/chosen keep the whole JSON object and are unmodifiable; a non-object becomes null', () {
      final r = DecisionRecord.fromJson({
        'decisionId': 'd', 'subject': 'route', 'subjectId': 'SYN-75-08IV-121-01', 'role': 'doctor',
        'chosen': {'moCode': '22GN', 'confirms': 't-1', 'plannedAt': '2026-10-10'}, 'recommended': 'строка', 'recordedAt': 'x', //
      });
      expect(r.chosen, {'moCode': '22GN', 'confirms': 't-1', 'plannedAt': '2026-10-10'});
      expect(r.recommended, isNull);
      expect(() => r.chosen!['moCode'] = 'X', throwsUnsupportedError);
    });

    test('outcome follows the web rule: no recommendation → none, equal JSON → matched, else differ', () {
      DecisionRecord record(Object? recommended, Object? chosen) =>
          DecisionRecord.fromJson({'decisionId': 'd', 'subject': 'route', 'recommended': recommended, 'chosen': chosen, 'recordedAt': 'x'});
      expect(record(null, {'moCode': '028B'}).outcome, DecisionCodes.outcomeNone);
      expect(record({'moCode': '031N'}, {'moCode': '031N'}).outcome, DecisionCodes.outcomeMatched);
      expect(record({'moCode': '031N'}, {'moCode': '22GN'}).outcome, DecisionCodes.outcomeDiffer);
      expect(record({'moCode': '031N'}, {'moCode': '031N', 'severe': true}).outcome, DecisionCodes.outcomeDiffer);
      expect(record({'moCode': '031N'}, null).outcome, DecisionCodes.outcomeDiffer);
    });

    test('DecisionCodes carry the exact subject strings of the journal', () {
      expect(DecisionCodes.subjects, ['referral', 'route', 'scribe', 'anomaly']);
      expect(DecisionCodes.eventReferral, 'referral');
      expect(DecisionCodes.eventScribe, 'scribe');
      expect(DecisionCodes.eventOther, 'other');
    });
  });

  group('real responses (test/fixtures/api)', () {
    test('worklist.json: priority on the 0…10 scale, every flag and next-action code known', () {
      final page = WorklistResponse.fromJson(apiFixtureObject('worklist.json'));
      expect(page.items, hasLength(4));
      expect(page.modelBacked, isTrue);
      for (final row in page.items) {
        expect(row.priority, inInclusiveRange(0, 10), reason: row.patientRef);
        expect(row.riskFlags.every(RouteCodes.riskFlags.contains), isTrue, reason: '${row.riskFlags}');
        expect(RouteCodes.nextActions, contains(row.nextActionCode));
      }
      final pending = page.items.where((w) => w.riskFlags.contains(RouteCodes.flagTransferPending));
      expect(pending.map((w) => w.nextActionCode), everyElement(RouteCodes.nextAwaitConsent));
    });

    test('decisions.json: events and outcomes of the real journal page', () {
      final items = ((apiFixtureObject('decisions.json')['items']) as List<dynamic>).map((d) => DecisionRecord.fromJson(d as Map<String, dynamic>)).toList();
      expect(items.map((d) => d.event), [
        RouteCodes.journalRedirect,
        RouteCodes.journalKeep,
        RouteCodes.journalRedirect,
        RouteCodes.journalRedirect,
        DecisionCodes.eventReferral,
      ]);
      expect(items.map((d) => d.outcome), [
        DecisionCodes.outcomeDiffer,
        DecisionCodes.outcomeDiffer,
        DecisionCodes.outcomeMatched,
        DecisionCodes.outcomeMatched,
        DecisionCodes.outcomeNone,
      ]);
      expect(items.map((d) => d.actor).toSet(), {'doctor1'});
    });

    test('me-doctor.json and me-citizen.json: hospital, region and grants', () {
      final doctor = Me.fromJson(apiFixtureObject('me-doctor.json'));
      expect(doctor.moCode, '028B');
      expect(doctor.roles, ['doctor']);
      expect(doctor.grants, isNotNull);
      final citizen = Me.fromJson(apiFixtureObject('me-citizen.json'));
      expect(citizen.moCode, isNull);
      expect(citizen.regionKato, '75');
      expect(citizen.iinMasked, '00••••••••01');
    });
  });

  group('NotificationSettings per event (Q12: the citizen switch «Изменения моего маршрута»)', () {
    NotificationSettings settings() => NotificationSettings.fromJson({
          'events': [
            {'code': 'security', 'titleRu': 'Безопасность', 'inApp': true, 'email': true, 'sms': false, 'push': false, 'locked': true},
            {'code': 'route_updates', 'titleRu': 'Изменения моего маршрута', 'titleKk': 'Менің бағытымдағы өзгерістер', 'inApp': true, 'email': false, 'sms': false, 'push': false},
            {'code': 'patient_signals', 'inApp': true, 'email': true, 'sms': false, 'push': false},
          ],
          'quietFrom': '22:00',
          'quietTo': '07:00',
          'quietExceptRegulator': true,
          'digest': 'daily',
        });

    test('event(code) finds one event; an absent code gives null', () {
      expect(settings().event(NotificationSettings.routeUpdates)!.titleKk, 'Менің бағытымдағы өзгерістер');
      expect(settings().event('missing'), isNull);
    });

    test('withEventChannel switches one channel of one event and keeps everything else, including web-only settings', () {
      final before = settings();
      final after = before.withEventChannel(NotificationSettings.routeUpdates, NotificationChannel.inApp, false);
      expect(after.event(NotificationSettings.routeUpdates)!.inApp, isFalse);
      expect(after.event('patient_signals')!.inApp, isTrue);
      expect(after.event('security')!.inApp, isTrue);
      expect(after.quietFrom, '22:00');
      expect(after.quietTo, '07:00');
      expect(after.quietExceptRegulator, isTrue);
      expect(after.digest, 'daily');
      expect(before.event(NotificationSettings.routeUpdates)!.inApp, isTrue, reason: 'исходный объект не меняется');
      expect(() => after.events.clear(), throwsUnsupportedError);
    });

    test('a locked event and an absent code are left untouched', () {
      final s = settings();
      expect(s.withEventChannel('security', NotificationChannel.inApp, false).event('security')!.inApp, isTrue);
      expect(s.withEventChannel('missing', NotificationChannel.inApp, false).toJson(), s.toJson());
    });
  });

  group('Alternative', () {
    Map<String, dynamic> alternative(Map<String, dynamic> mo) =>
        {'mo': mo, 'p50Days': 2.3, 'p90Days': 10.4, 'pRefusal': 0.5, 'distanceKm': 0, 'isNeighborRegion': true};

    test('keeps the region of the hospital for the neighbour-region caption', () {
      final item = Alternative.fromJson(alternative({'moCode': '031N', 'name': 'Госпиталь', 'regionKato': '19'}));
      expect(item.regionKato, '19');
      expect(item.isNeighborRegion, isTrue);
    });

    test('region is null when the server does not send it', () {
      expect(Alternative.fromJson(alternative({'moCode': '031N', 'name': 'Госпиталь'})).regionKato, isNull);
    });
  });
}
