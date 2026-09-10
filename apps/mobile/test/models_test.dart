import 'package:darumen/api/models.dart';
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
      'nextAction': 'уточнить дату', 'explanation': 'очередь 1784', 'moCode': '028B', 'moName': 'Институт', 'profileCode': '381', 'daysWaiting': 72,
    });
    expect(w.expectedDate, isNull);
    expect(w.riskFlags, ['stuck_over_30']);
    final c = CheckResponse.fromJson({'covered': true, 'program': 'Программа 90', 'fillDaysP50': 3, 'shortage': {'flag': false, 'score': 0.1, 'basis': 'ok'}});
    expect(c.covered, isTrue);
    expect(c.fillDaysP90, isNull);
    expect(c.shortage.score, 0.1);
  });
}
