import 'package:darumen/api/models.dart';
import 'package:darumen/l10n/strings.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
