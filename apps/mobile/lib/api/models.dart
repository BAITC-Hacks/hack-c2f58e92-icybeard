// Модели ответов REST API Darumen (docs/api.md) — только то, что нужно мобильным экранам. Единственная точка импорта:
// экраны, состояние и тесты импортируют models.dart, а файлы ниже — его части по разделам контракта. Списки никогда не
// null, незнакомые коды сохраняются как есть; модели нового контракта (маршрут, колокольчики, входящие, скрайб, журнал)
// разбираются терпимо — отсутствующее поле получает значение по умолчанию.
export 'account_models.dart';
export 'decision_models.dart';
export 'notification_models.dart';
export 'referral_models.dart';
export 'route_codes.dart';
export 'route_models.dart';
export 'route_progress_models.dart';
export 'scribe_models.dart';
export 'service_status.dart';

/// Модель, посчитавшая прогноз: имя, версия и по какую дату данные обучения.
class ModelInfo {
  const ModelInfo({required this.name, required this.version, required this.trainedThrough});
  final String name;
  final String version;
  final String trainedThrough;
  factory ModelInfo.fromJson(Map<String, dynamic> json) =>
      ModelInfo(name: json['name'] as String? ?? '', version: json['version'] as String? ?? '', trainedThrough: json['trainedThrough'] as String? ?? '');
}

class Factor {
  const Factor({required this.name, required this.contribution, required this.text});
  final String name;
  final double contribution;
  final String text;
  factory Factor.fromJson(Map<String, dynamic> json) =>
      Factor(name: json['name'] as String, contribution: (json['contribution'] as num).toDouble(), text: json['text'] as String);
}

class Explanation {
  const Explanation({required this.summary, required this.factors});
  final String summary;
  final List<Factor> factors;
  factory Explanation.fromJson(Map<String, dynamic> json) => Explanation(
        summary: json['summary'] as String? ?? '',
        factors: (json['factors'] as List<dynamic>? ?? []).map((f) => Factor.fromJson(f as Map<String, dynamic>)).toList(),
      );
}

class QueueSnapshot {
  const QueueSnapshot({required this.len, this.ageP50, required this.throughputPerDay});
  final int len;
  final double? ageP50;
  final double throughputPerDay;
  factory QueueSnapshot.fromJson(Map<String, dynamic> json) => QueueSnapshot(
        len: (json['len'] as num).toInt(),
        ageP50: (json['ageP50'] as num?)?.toDouble(),
        throughputPerDay: (json['throughputPerDay'] as num).toDouble(),
      );
}

class PredictResponse {
  const PredictResponse({
    required this.p50Days,
    required this.p90Days,
    required this.pWithin30Days,
    required this.pRefusal,
    this.queue,
    required this.explanation,
    required this.model,
    this.refusalOrgInTraining = true,
  });
  final double p50Days;
  final double p90Days;
  final double pWithin30Days;
  final double pRefusal;
  final QueueSnapshot? queue;
  final Explanation explanation;
  final ModelInfo model;

  /// false — организация не встречалась модели при обучении: риск отказа показывать словами, а не процентом.
  final bool refusalOrgInTraining;
  factory PredictResponse.fromJson(Map<String, dynamic> json) => PredictResponse(
        p50Days: (json['p50Days'] as num).toDouble(),
        p90Days: (json['p90Days'] as num).toDouble(),
        pWithin30Days: (json['pWithin30Days'] as num).toDouble(),
        pRefusal: (json['pRefusal'] as num).toDouble(),
        queue: json['queue'] == null ? null : QueueSnapshot.fromJson(json['queue'] as Map<String, dynamic>),
        explanation: Explanation.fromJson(json['explanation'] as Map<String, dynamic>),
        model: ModelInfo.fromJson(json['model'] as Map<String, dynamic>),
        refusalOrgInTraining: json['refusalOrgInTraining'] as bool? ?? true,
      );
}

class Alternative {
  const Alternative({
    required this.moCode,
    required this.name,
    required this.p50Days,
    required this.p90Days,
    required this.pRefusal,
    required this.distanceKm,
    this.isNeighborRegion = false,
    this.regionKato,
  });
  final String moCode;
  final String name;
  final double p50Days;
  final double p90Days;
  final double pRefusal;
  final double distanceKm;
  final bool isNeighborRegion;

  /// КАТО региона организации (`mo.regionKato`) — для подписи «сосед: {регион}» у больницы соседнего региона;
  /// null, если сервер его не прислал.
  final String? regionKato;
  factory Alternative.fromJson(Map<String, dynamic> json) {
    final mo = json['mo'] as Map<String, dynamic>;
    return Alternative(
      moCode: mo['moCode'] as String,
      name: mo['name'] as String,
      p50Days: (json['p50Days'] as num).toDouble(),
      p90Days: (json['p90Days'] as num).toDouble(),
      pRefusal: (json['pRefusal'] as num).toDouble(),
      distanceKm: (json['distanceKm'] as num).toDouble(),
      isNeighborRegion: json['isNeighborRegion'] as bool? ?? false,
      regionKato: mo['regionKato'] as String?,
    );
  }
}

class Region {
  const Region({required this.kato, required this.name});
  final String kato;
  final String name;
  factory Region.fromJson(Map<String, dynamic> json) => Region(kato: json['regionKato'] as String, name: json['name'] as String);
}

class BedProfile {
  const BedProfile({required this.code, required this.name});
  final String code;
  final String name;
  factory BedProfile.fromJson(Map<String, dynamic> json) => BedProfile(code: json['profileCode'] as String, name: json['name'] as String);
}

class Organization {
  const Organization({required this.moCode, required this.name});
  final String moCode;
  final String name;
  factory Organization.fromJson(Map<String, dynamic> json) => Organization(moCode: json['moCode'] as String, name: json['name'] as String);
}

class IndexItem {
  const IndexItem({required this.regionKato, required this.name, required this.indexValue, required this.rank});
  final String regionKato;
  final String name;
  final double indexValue;
  final int rank;
  factory IndexItem.fromJson(Map<String, dynamic> json) => IndexItem(
        regionKato: json['regionKato'] as String,
        name: json['name'] as String,
        indexValue: (json['indexValue'] as num).toDouble(),
        rank: (json['rank'] as num).toInt(),
      );
}

/// Строка рабочего списка врача (`GET /journal/worklist`, до 60 строк; сервер сортирует по priority, затем по
/// daysWaiting — клиент порядок не меняет). Закрытые маршруты из списка уходят; пациент, переведённый в мою больницу,
/// добавляется строкой с флагом transferred_in.
class WorklistItem {
  const WorklistItem({
    required this.patientRef,
    required this.stage,
    required this.stageCode,
    required this.expectedDate,
    required this.riskFlags,
    required this.priority,
    required this.nextAction,
    required this.explanation,
    required this.moCode,
    required this.moName,
    required this.profileCode,
    required this.regionKato,
    required this.daysWaiting,
    this.nextActionCode = '',
    this.synthetic = true,
    this.patientSignal,
  });

  /// Реф с больницей, где пациент встал в очередь; у переведённого ко мне — больница-отправитель, поэтому больницу
  /// строки брать из [moCode], а не из рефа.
  final String patientRef;

  /// Русская подпись стадии от API (старый контракт); для локализации используется [stageCode].
  final String stage;

  /// registered | waiting | called — см. WorklistBuilder.Stage* в API; у transferred всегда called.
  final String stageCode;

  /// `yyyy-MM-dd`; у transferred — дата, назначенная принимающей больницей.
  final String? expectedDate;

  /// Коды из `RouteCodes.riskFlags` (8 флагов, с поправкой на сторону); незнакомый — запасная подпись.
  final List<String> riskFlags;

  /// Фиксированная шкала 0…10: 7–10 — высокий, 4–6 — средний, 0–3 — низкий.
  final int priority;

  /// Русская подпись следующего шага от API — только запасная; для локализации — [nextActionCode].
  final String nextAction;

  /// Один из `RouteCodes.nextActions` (в списке — 13 кодов, closed бывает только на маршруте) или '' у старого сервера.
  final String nextActionCode;
  final String explanation;

  /// Больница строки; у переведённого ко мне пациента — моя (принимающая), не та, что в рефе.
  final String moCode;
  final String moName;
  final String profileCode;
  final String regionKato;

  /// Дней в очереди; после перевода не обнуляется.
  final int daysWaiting;
  final bool synthetic;

  /// Открытый сигнал гражданина (в riskFlags при этом есть RouteCodes.patientSignalFlag): только request_redirect,
  /// withdraw или treated_elsewhere — still_waiting и prefer_current открытыми не бывают.
  final PatientSignal? patientSignal;
  factory WorklistItem.fromJson(Map<String, dynamic> json) => WorklistItem(
        patientRef: json['patientRef'] as String,
        stage: json['stage'] as String,
        stageCode: json['stageCode'] as String? ?? 'waiting',
        expectedDate: json['expectedDate'] as String?,
        riskFlags: (json['riskFlags'] as List<dynamic>? ?? []).cast<String>(),
        priority: (json['priority'] as num).toInt(),
        nextAction: json['nextAction'] as String,
        nextActionCode: json['nextActionCode'] as String? ?? '',
        explanation: json['explanation'] as String,
        moCode: json['moCode'] as String,
        moName: json['moName'] as String? ?? json['moCode'] as String,
        profileCode: json['profileCode'] as String,
        regionKato: json['regionKato'] as String? ?? '',
        daysWaiting: (json['daysWaiting'] as num).toInt(),
        synthetic: json['synthetic'] as bool? ?? true,
        patientSignal: json['patientSignal'] == null ? null : PatientSignal.fromJson(json['patientSignal'] as Map<String, dynamic>),
      );
}

/// Открытый сигнал гражданина в строке рабочего списка: вид (request_redirect | withdraw | treated_elsewhere),
/// организация из просьбы «быстрее», комментарий, время.
class PatientSignal {
  const PatientSignal({required this.kind, this.toMoCode, this.toMoName, this.comment, required this.recordedAt});
  final String kind;
  final String? toMoCode;
  final String? toMoName;
  final String? comment;
  final String recordedAt;
  factory PatientSignal.fromJson(Map<String, dynamic> json) => PatientSignal(
        kind: json['kind'] as String,
        toMoCode: json['toMoCode'] as String?,
        toMoName: json['toMoName'] as String?,
        comment: json['comment'] as String?,
        recordedAt: json['recordedAt'] as String? ?? '',
      );
}

/// Конверт рабочего списка: modelBacked = false — сервис моделей был недоступен, приоритеты по агрегатам витрины.
class WorklistResponse {
  const WorklistResponse({required this.items, required this.synthetic, required this.asOf, required this.regionKato, required this.modelBacked});
  final List<WorklistItem> items;
  final bool synthetic;
  final String asOf;
  final String regionKato;
  final bool modelBacked;
  factory WorklistResponse.fromJson(Map<String, dynamic> json) => WorklistResponse(
        items: (json['items'] as List<dynamic>? ?? []).map((w) => WorklistItem.fromJson(w as Map<String, dynamic>)).toList(),
        synthetic: json['synthetic'] as bool? ?? true,
        asOf: json['asOf'] as String? ?? '',
        regionKato: json['regionKato'] as String? ?? '',
        modelBacked: json['modelBacked'] as bool? ?? false,
      );
}

class Shortage {
  const Shortage({required this.flag, required this.score, required this.basis});
  final bool flag;
  final double score;
  final String basis;
  factory Shortage.fromJson(Map<String, dynamic> json) =>
      Shortage(flag: json['flag'] as bool, score: (json['score'] as num).toDouble(), basis: json['basis'] as String? ?? '');
}

class CheckResponse {
  const CheckResponse({
    required this.covered,
    this.program,
    this.category,
    this.fillDaysP50,
    this.fillDaysP90,
    this.fillDaysP50Model,
    this.pFilled14d,
    required this.shortage,
    required this.basis,
    this.model,
  });
  final bool covered;
  final String? program;

  /// Категория спецификации программы («Программа 90 · категория 63»).
  final String? category;
  final double? fillDaysP50;
  final double? fillDaysP90;

  /// p50 модели rx_fill (метка «ML‑модель»); null, пока витрина для МНН не насчитана.
  final double? fillDaysP50Model;
  final double? pFilled14d;
  final Shortage shortage;
  final String basis;
  final ModelInfo? model;
  factory CheckResponse.fromJson(Map<String, dynamic> json) => CheckResponse(
        covered: json['covered'] as bool,
        program: json['program'] as String?,
        category: json['category'] as String?,
        fillDaysP50: (json['fillDaysP50'] as num?)?.toDouble(),
        fillDaysP90: (json['fillDaysP90'] as num?)?.toDouble(),
        fillDaysP50Model: (json['fillDaysP50Model'] as num?)?.toDouble(),
        pFilled14d: (json['pFilled14d'] as num?)?.toDouble(),
        shortage: Shortage.fromJson(json['shortage'] as Map<String, dynamic>),
        basis: json['basis'] as String? ?? '',
        model: json['model'] == null ? null : ModelInfo.fromJson(json['model'] as Map<String, dynamic>),
      );
}

class Nosology {
  const Nosology({required this.id, required this.issued12m});
  final String id;
  final int issued12m;
  factory Nosology.fromJson(Map<String, dynamic> json) => Nosology(id: json['nosologyId'] as String, issued12m: (json['issued12m'] as num).toInt());
}

class Mnn {
  const Mnn({required this.id, required this.issued12m});
  final String id;
  final int issued12m;
  factory Mnn.fromJson(Map<String, dynamic> json) => Mnn(id: json['mnnId'] as String, issued12m: (json['issued12m'] as num).toInt());
}

class VaccinationEstimate {
  const VaccinationEstimate({required this.vaccine, required this.title, this.titleKk, required this.year, required this.coveragePct, required this.source, this.note});
  final String vaccine;
  final String title;
  final String? titleKk;
  final int year;
  final double coveragePct;
  final String source;
  final String? note;

  /// Казахская подпись, если API её отдаёт; иначе русская.
  String titleFor(String locale) => locale == 'kk' && titleKk != null && titleKk!.isNotEmpty ? titleKk! : title;
  factory VaccinationEstimate.fromJson(Map<String, dynamic> json) => VaccinationEstimate(
        vaccine: json['vaccine'] as String,
        title: json['titleRu'] as String? ?? json['vaccine'] as String,
        titleKk: json['titleKk'] as String?,
        year: (json['year'] as num).toInt(),
        coveragePct: (json['coveragePct'] as num).toDouble(),
        source: json['source'] as String? ?? '',
        note: json['note'] as String?,
      );
}
