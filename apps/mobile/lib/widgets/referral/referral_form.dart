import 'package:flutter/foundation.dart';

import '../../api/models.dart';
import '../../l10n/strings.dart';
import '../format.dart';
import '../route/forecast_factors.dart';

// Правила ассистента направления — порт ReferralView.vue и lib/decision.ts веба: форма прогноза, subjectId решения,
// рекомендация системы, варианты выбора, сравнение сроков, риск отказа и строки «Из чего сложился прогноз». Чистые
// функции и неизменяемая форма; экран только вызывает их.

/// Значения категориальных признаков — контракт модели (русские литералы, как в вебе `referralContract.ts`); в
/// интерфейсе — переводимые подписи `S.purposeLabels` / `S.territorialLabels` в том же порядке.
abstract final class ReferralContract {
  static const purposes = ['Оперативное лечение', 'Консервативное лечение', 'Диагностика', 'Реабилитация'];
  static const territorial = ['Город', 'Село'];
  static const financeSource = 'Активы Фонда на ОСМС';
}

/// Параметры нового направления. Прогноз считается, когда заданы регион, организация и профиль ([complete]).
@immutable
class ReferralForm {
  const ReferralForm({
    required this.regionKato,
    this.moCode = '',
    this.profileCode = '',
    this.icd10 = '',
    this.purpose = 'Оперативное лечение',
    this.territorial = 'Город',
    this.registrationDate = '',
    this.referringMoCode = '',
    this.includeNeighbors = false,
  });

  final String regionKato;

  /// Организация, которую выбрал врач; '' — ещё не выбрана.
  final String moCode;
  final String profileCode;
  final String icd10;

  /// Значение из [ReferralContract.purposes].
  final String purpose;

  /// Значение из [ReferralContract.territorial].
  final String territorial;

  /// `yyyy-MM-dd`; '' — по последним данным очереди (сервис моделей берёт день после них).
  final String registrationDate;

  /// Направляющая организация; '' — не указана (модель считает направление пришедшим со стороны).
  final String referringMoCode;

  /// Показать и соседние регионы в альтернативах.
  final bool includeNeighbors;

  bool get complete => regionKato.isNotEmpty && moCode.isNotEmpty && profileCode.isNotEmpty;

  ReferralForm copyWith({
    String? regionKato,
    String? moCode,
    String? profileCode,
    String? icd10,
    String? purpose,
    String? territorial,
    String? registrationDate,
    String? referringMoCode,
    bool? includeNeighbors,
  }) =>
      ReferralForm(
        regionKato: regionKato ?? this.regionKato,
        moCode: moCode ?? this.moCode,
        profileCode: profileCode ?? this.profileCode,
        icd10: icd10 ?? this.icd10,
        purpose: purpose ?? this.purpose,
        territorial: territorial ?? this.territorial,
        registrationDate: registrationDate ?? this.registrationDate,
        referringMoCode: referringMoCode ?? this.referringMoCode,
        includeNeighbors: includeNeighbors ?? this.includeNeighbors,
      );

  /// Тело `POST /queue/predict` — как у веба: пустые строки уходят как есть.
  Map<String, dynamic> toRequest() => {
        'regionKato': regionKato,
        'moCode': moCode,
        'profileCode': profileCode,
        'icd10': icd10.trim(),
        'referralPurpose': purpose,
        'territorialType': territorial,
        'financeSource': ReferralContract.financeSource,
        'registrationDate': registrationDate.trim(),
        'referringMoCode': referringMoCode,
      };

  /// Тело `POST /queue/alternatives` (`limit: 5` добавляет клиент).
  Map<String, dynamic> toAlternativesRequest() => {...toRequest(), 'includeNeighbors': includeNeighbors};
}

/// subjectId решения в журнале — формат веба `регион.организация.профиль.ГГГГ-ММ-ДД` (`referralSubjectId` в
/// lib/decision.ts): дата постановки в очередь, если указана, иначе [today] (день по Алматы, `almatyTodayString()`).
String referralSubjectId(ReferralForm form, {required String today}) {
  final date = form.registrationDate.trim();
  return [form.regionKato, form.moCode, form.profileCode, date.isEmpty ? today : date].join('.');
}

/// Рекомендация системы для журнала: самая быстрая по медиане альтернатива, если она быстрее организации врача,
/// иначе сама организация врача [moCode].
String referralRecommended(PredictResponse prediction, List<Alternative> alternatives, String moCode) {
  final fastest = alternatives.fold<Alternative?>(null, (best, a) => best == null || a.p50Days < best.p50Days ? a : best);
  return fastest != null && fastest.p50Days < prediction.p50Days ? fastest.moCode : moCode;
}

/// Альтернативы для выбора — в порядке сервера, без организации, которую врач уже выбрал (она — первый вариант).
List<Alternative> referralAlternatives(List<Alternative> alternatives, String moCode) => [
      for (final a in alternatives)
        if (a.moCode != moCode) a,
    ];

/// «на N дн. быстрее» / «на N дн. дольше» по тем же округлённым дням, что видны в строках (`≈ N`); одинаково — null.
String? referralCompare(S s, double baselineDays, double otherDays) {
  final diff = roundedDaysDiff(baselineDays, otherDays) ?? 0;
  if (diff == 0) return null;
  return diff > 0 ? s.assistFasterBy(diff) : s.assistSlowerBy(-diff);
}

/// Риск отказа: процент, а для больницы, которой не было в обучении модели, — словами (`refusalWords`).
String referralRisk(S s, double pRefusal, {required bool inTraining}) => inTraining ? pct(pRefusal) : refusalWords(s, pRefusal);

/// Строки «Из чего сложился прогноз» (кит `forecastFactors`); пока направляющая организация не указана, строка
/// same_mo говорит это прямо и подсказывает, где её указать (веб `doctor.referral.referringUnset*`).
List<ForecastFactorView> referralFactors(S s, PredictResponse prediction, {String? profileName, required bool referringSet}) => [
      for (final row in forecastFactors(prediction.explanation.factors, s, profileName: profileName))
        row.name == 'same_mo' && !referringSet ? row.copyWith(label: s.assistReferringUnset, hint: s.assistReferringUnsetHint) : row,
    ];
