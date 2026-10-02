import 'package:darumen/api/models.dart';
import 'package:darumen/l10n/strings.dart';
import 'package:darumen/widgets/referral/referral_form.dart';
import 'package:darumen/widgets/route/forecast_factors.dart';
import 'package:flutter_test/flutter_test.dart';

/// Правила ассистента направления (ReferralView.vue веба): тело прогноза, subjectId решения
/// `регион.организация.профиль.ГГГГ-ММ-ДД`, рекомендация системы, варианты выбора, «Направляющая организация не
/// указана» в факторах, риск словами и сравнение сроков.
PredictResponse prediction({double p50 = 40, double pRefusal = 0.12, bool inTraining = true, List<Factor> factors = const []}) => PredictResponse(
      p50Days: p50,
      p90Days: p50 * 2,
      pWithin30Days: 0.4,
      pRefusal: pRefusal,
      explanation: Explanation(summary: '', factors: factors),
      model: const ModelInfo(name: 'wait', version: '1', trainedThrough: '2025-03-31'),
      refusalOrgInTraining: inTraining,
    );

Alternative alternative(String code, double p50, {double pRefusal = 0.1}) =>
    Alternative(moCode: code, name: 'Больница $code', p50Days: p50, p90Days: p50 * 2, pRefusal: pRefusal, distanceKm: 3);

void main() {
  final ru = S.of('ru');
  final kk = S.of('kk');
  const form = ReferralForm(regionKato: '75', moCode: '028B', profileCode: '381');

  group('форма', () {
    test('полная — регион, организация и профиль; тело прогноза как у веба (пустые строки — как есть)', () {
      expect(form.complete, isTrue);
      expect(form.copyWith(moCode: '').complete, isFalse);
      expect(const ReferralForm(regionKato: '75').complete, isFalse);
      expect(form.copyWith(icd10: ' H25.1 ').toRequest(), {
        'regionKato': '75',
        'moCode': '028B',
        'profileCode': '381',
        'icd10': 'H25.1',
        'referralPurpose': 'Оперативное лечение',
        'territorialType': 'Город',
        'financeSource': 'Активы Фонда на ОСМС',
        'registrationDate': '',
        'referringMoCode': '',
      });
      expect(form.copyWith(includeNeighbors: true, referringMoCode: '22GN').toAlternativesRequest(), {
        ...form.copyWith(referringMoCode: '22GN').toRequest(),
        'includeNeighbors': true,
      });
    });

    test('copyWith возвращает новую форму и не трогает исходную', () {
      final next = form.copyWith(purpose: ReferralContract.purposes[2], territorial: ReferralContract.territorial[1], registrationDate: '2025-03-01');
      expect(next.purpose, 'Диагностика');
      expect(next.territorial, 'Село');
      expect(next.registrationDate, '2025-03-01');
      expect(form.purpose, 'Оперативное лечение');
      expect(form.registrationDate, '');
    });
  });

  test('subjectId решения — регион.организация.профиль.дата: дата постановки или сегодняшний день', () {
    expect(referralSubjectId(form, today: '2026-10-02'), '75.028B.381.2026-10-02');
    expect(referralSubjectId(form.copyWith(registrationDate: ' 2025-03-01 '), today: '2026-10-02'), '75.028B.381.2025-03-01');
  });

  test('рекомендация — самая быстрая альтернатива, если она быстрее выбранной врачом, иначе сама выбранная', () {
    expect(referralRecommended(prediction(p50: 40), [alternative('22GN', 50), alternative('031N', 12), alternative('08IV', 30)], '028B'), '031N');
    expect(referralRecommended(prediction(p50: 10), [alternative('22GN', 12)], '028B'), '028B');
    expect(referralRecommended(prediction(p50: 10), const [], '028B'), '028B');
  });

  test('варианты выбора: альтернативы без организации врача, порядок сервера, вход не меняется', () {
    final input = List<Alternative>.unmodifiable([alternative('22GN', 30), alternative('028B', 40), alternative('031N', 12)]);
    expect(referralAlternatives(input, '028B').map((a) => a.moCode), ['22GN', '031N']);
    expect(input, hasLength(3));
  });

  test('сравнение сроков по округлённым дням: быстрее, дольше, без подписи при равенстве', () {
    expect(referralCompare(ru, 40.4, 12.6), 'на 27 дн. быстрее');
    expect(referralCompare(ru, 12, 30), 'на 18 дн. дольше');
    expect(referralCompare(kk, 12, 30), '18 күн ұзағырақ');
    expect(referralCompare(ru, 12.2, 11.8), isNull);
  });

  test('риск отказа: процент, а для больницы вне обучения — словами', () {
    expect(referralRisk(ru, 0.29, inTraining: true), '29 %');
    expect(referralRisk(ru, 0.29, inTraining: false), 'выше среднего');
    expect(referralRisk(kk, 0.03, inTraining: false), 'орташадан төмен');
  });

  group('факторы прогноза', () {
    const sameMo = Factor(name: 'same_mo', contribution: 6.2, text: 'Направляет эта же МО: False (+6.2 дн.)');
    const queue = Factor(name: 'queue_len', contribution: 9, text: 'Длина очереди: 133 (+9.0 дн.)');

    test('направляющая организация не указана — строка same_mo говорит это прямо и подсказывает, что изменить', () {
      final rows = referralFactors(ru, prediction(factors: const [queue, sameMo]), profileName: 'Офтальмологические', referringSet: false);
      expect(rows.map((r) => r.label), ['Длина очереди: 133', ru.assistReferringUnset]);
      expect(rows.last.hint, ru.assistReferringUnsetHint);
      expect(rows.last.effect, ru.factorAddsDays(6));
      expect(rows.last.direction, FactorDirection.plus);
    });

    test('указана — подпись кита «Направляет другая организация»', () {
      final rows = referralFactors(ru, prediction(factors: const [sameMo]), referringSet: true);
      expect(rows.single.label, ru.factorSameMo(false));
    });
  });
}
