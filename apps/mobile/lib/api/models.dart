/// Модели ответов REST API Darumen (docs/api.md). Только то, что нужно мобильным экранам.
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
  });
  final String moCode;
  final String name;
  final double p50Days;
  final double p90Days;
  final double pRefusal;
  final double distanceKm;
  final bool isNeighborRegion;
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
  });
  final String patientRef;

  /// Русская подпись стадии от API (старый контракт); для локализации используется [stageCode].
  final String stage;

  /// registered | waiting | called — см. WorklistBuilder.Stage* в API.
  final String stageCode;
  final String? expectedDate;
  final List<String> riskFlags;
  final int priority;

  /// Русская подпись следующего шага от API; для локализации — [nextActionCode] (redirect_faster | review_before_call | clarify_date | wait_for_call).
  final String nextAction;
  final String nextActionCode;
  final String explanation;
  final String moCode;
  final String moName;
  final String profileCode;
  final String regionKato;
  final int daysWaiting;
  final bool synthetic;
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

class DecisionRecord {
  const DecisionRecord({required this.decisionId, required this.subject, this.subjectId, this.recommendedMoCode, this.chosenMoCode, this.reason, required this.recordedAt});
  final String decisionId;
  final String subject;
  final String? subjectId;
  final String? recommendedMoCode;
  final String? chosenMoCode;
  final String? reason;
  final String recordedAt;
  factory DecisionRecord.fromJson(Map<String, dynamic> json) => DecisionRecord(
        decisionId: json['decisionId'] as String,
        subject: json['subject'] as String? ?? '',
        subjectId: json['subjectId'] as String?,
        recommendedMoCode: (json['recommended'] as Map<String, dynamic>?)?['moCode'] as String?,
        chosenMoCode: (json['chosen'] as Map<String, dynamic>?)?['moCode'] as String?,
        reason: json['reason'] as String?,
        recordedAt: json['recordedAt'] as String? ?? '',
      );
}

class ScribeSession {
  const ScribeSession({required this.sessionId});
  final String sessionId;
  factory ScribeSession.fromJson(Map<String, dynamic> json) => ScribeSession(sessionId: json['sessionId'] as String);
}

class TranscriptSegment {
  const TranscriptSegment({required this.t0, required this.t1, required this.text});
  final double t0;
  final double t1;
  final String text;
  factory TranscriptSegment.fromJson(Map<String, dynamic> json) =>
      TranscriptSegment(t0: (json['t0'] as num).toDouble(), t1: (json['t1'] as num).toDouble(), text: json['text'] as String);
}

class DraftSection {
  const DraftSection({required this.name, required this.text});
  final String name;
  final String text;
  factory DraftSection.fromJson(Map<String, dynamic> json) => DraftSection(name: json['name'] as String, text: json['text'] as String? ?? '');
}

class ScribeDraft {
  const ScribeDraft({required this.sections, required this.leaflet});
  final List<DraftSection> sections;
  final String leaflet;
  factory ScribeDraft.fromJson(Map<String, dynamic> json) => ScribeDraft(
        sections: (json['sections'] as List<dynamic>? ?? []).map((s) => DraftSection.fromJson(s as Map<String, dynamic>)).toList(),
        leaflet: json['leaflet'] as String? ?? '',
      );
}

class ApproveResult {
  const ApproveResult({required this.leafletToken, required this.leafletUrl});
  final String leafletToken;
  final String leafletUrl;
  factory ApproveResult.fromJson(Map<String, dynamic> json) =>
      ApproveResult(leafletToken: json['leafletToken'] as String, leafletUrl: json['leafletUrl'] as String);
}

// ---------- маршрут пациента (docs/api.md, раздел Route) ----------

/// Коды стадий и статусов маршрута — те же, что в API (RouteStages, RouteChecklistStatus, RouteOutcomes).
abstract final class RouteCodes {
  static const referralIssued = 'referral_issued';
  static const examination = 'examination';
  static const waitlisted = 'waitlisted';
  static const dateAssigned = 'date_assigned';
  static const hospitalized = 'hospitalized';
  static const refused = 'refused';

  static const done = 'done';
  static const current = 'current';
  static const upcoming = 'upcoming';

  static const valid = 'valid';
  static const expiring = 'expiring';
  static const expired = 'expired';

  static const redirect = 'redirect';
  static const keep = 'keep';
}

class RouteOrganization {
  const RouteOrganization({required this.moCode, required this.moName, required this.profileCode, required this.profileName});
  final String moCode;
  final String moName;
  final String profileCode;
  final String profileName;
  factory RouteOrganization.fromJson(Map<String, dynamic> json) => RouteOrganization(
        moCode: json['moCode'] as String,
        moName: json['moName'] as String? ?? json['moCode'] as String,
        profileCode: json['profileCode'] as String,
        profileName: json['profileName'] as String? ?? json['profileCode'] as String,
      );
}

class RouteStage {
  const RouteStage({required this.code, required this.order, required this.title, this.date, required this.status, this.norm});
  final String code;
  final int order;
  final String title;
  final String? date;

  /// done | current | upcoming
  final String status;
  final String? norm;
  factory RouteStage.fromJson(Map<String, dynamic> json) => RouteStage(
        code: json['code'] as String,
        order: (json['order'] as num).toInt(),
        title: json['title'] as String? ?? json['code'] as String,
        date: json['date'] as String?,
        status: json['status'] as String? ?? RouteCodes.upcoming,
        norm: json['norm'] as String?,
      );
}

class RouteDates {
  const RouteDates({required this.issuedAt, required this.registeredAt, this.plannedAt, required this.expectedAt});
  final String issuedAt;
  final String registeredAt;
  final String? plannedAt;
  final String expectedAt;
  factory RouteDates.fromJson(Map<String, dynamic> json) => RouteDates(
        issuedAt: json['issuedAt'] as String? ?? '',
        registeredAt: json['registeredAt'] as String? ?? '',
        plannedAt: json['plannedAt'] as String?,
        expectedAt: json['expectedAt'] as String? ?? '',
      );
}

/// fromModel = false — сервис моделей был недоступен: p50/p90 из агрегатов витрины, pWithin30Days тогда null.
class RouteForecast {
  const RouteForecast({required this.p50Days, required this.p90Days, this.pWithin30Days, required this.fromModel, this.model});
  final double p50Days;
  final double p90Days;
  final double? pWithin30Days;
  final bool fromModel;
  final ModelInfo? model;
  factory RouteForecast.fromJson(Map<String, dynamic> json) => RouteForecast(
        p50Days: (json['p50Days'] as num).toDouble(),
        p90Days: (json['p90Days'] as num).toDouble(),
        pWithin30Days: (json['pWithin30Days'] as num?)?.toDouble(),
        fromModel: json['fromModel'] as bool? ?? false,
        model: json['model'] == null ? null : ModelInfo.fromJson(json['model'] as Map<String, dynamic>),
      );
}

class RouteBenchmark {
  const RouteBenchmark({required this.code, required this.value, required this.unit, required this.title, required this.source, required this.sourceDate});
  final String code;
  final double value;
  final String unit;
  final String title;
  final String source;
  final String sourceDate;
  factory RouteBenchmark.fromJson(Map<String, dynamic> json) => RouteBenchmark(
        code: json['code'] as String,
        value: (json['value'] as num).toDouble(),
        unit: json['unit'] as String? ?? '',
        title: json['title'] as String? ?? '',
        source: json['source'] as String? ?? '',
        sourceDate: json['sourceDate'] as String? ?? '',
      );
}

/// Пункт чек-листа приложения 5 Стандарта; status — valid | expiring | expired, считается только по датам.
class ChecklistItem {
  const ChecklistItem({
    required this.code,
    required this.title,
    required this.validityDays,
    required this.validityLabel,
    required this.doneAt,
    required this.validUntil,
    required this.status,
  });
  final String code;
  final String title;
  final int validityDays;
  final String validityLabel;
  final String doneAt;
  final String validUntil;
  final String status;
  factory ChecklistItem.fromJson(Map<String, dynamic> json) => ChecklistItem(
        code: json['code'] as String,
        title: json['title'] as String? ?? json['code'] as String,
        validityDays: (json['validityDays'] as num?)?.toInt() ?? 0,
        validityLabel: json['validityLabel'] as String? ?? '',
        doneAt: json['doneAt'] as String? ?? '',
        validUntil: json['validUntil'] as String? ?? '',
        status: json['status'] as String? ?? RouteCodes.valid,
      );
}

class RouteDecision {
  const RouteDecision({
    required this.decisionId,
    required this.role,
    required this.recordedAt,
    this.fromMoCode,
    required this.toMoCode,
    required this.toMoName,
    this.reason,
    required this.kind,
  });
  final String decisionId;
  final String role;
  final String recordedAt;
  final String? fromMoCode;
  final String toMoCode;
  final String toMoName;
  final String? reason;

  /// redirect | keep
  final String kind;
  factory RouteDecision.fromJson(Map<String, dynamic> json) => RouteDecision(
        decisionId: json['decisionId'] as String,
        role: json['role'] as String? ?? '',
        recordedAt: json['recordedAt'] as String? ?? '',
        fromMoCode: json['fromMoCode'] as String?,
        toMoCode: json['toMoCode'] as String,
        toMoName: json['toMoName'] as String? ?? json['toMoCode'] as String,
        reason: json['reason'] as String?,
        kind: json['kind'] as String? ?? RouteCodes.keep,
      );
}

class RouteHistoryItem {
  const RouteHistoryItem({
    required this.moCode,
    required this.moName,
    required this.profileCode,
    required this.profileName,
    required this.registeredAt,
    required this.outcome,
    required this.outcomeAt,
    required this.waitDays,
  });
  final String moCode;
  final String moName;
  final String profileCode;
  final String profileName;
  final String registeredAt;

  /// hospitalized | refused
  final String outcome;
  final String outcomeAt;
  final int waitDays;
  factory RouteHistoryItem.fromJson(Map<String, dynamic> json) => RouteHistoryItem(
        moCode: json['moCode'] as String,
        moName: json['moName'] as String? ?? json['moCode'] as String,
        profileCode: json['profileCode'] as String? ?? '',
        profileName: json['profileName'] as String? ?? json['profileCode'] as String? ?? '',
        registeredAt: json['registeredAt'] as String? ?? '',
        outcome: json['outcome'] as String? ?? RouteCodes.hospitalized,
        outcomeAt: json['outcomeAt'] as String? ?? '',
        waitDays: (json['waitDays'] as num?)?.toInt() ?? 0,
      );
}

/// Служебная панель врача; у гражданина всегда null.
class RouteDoctorPanel {
  const RouteDoctorPanel({
    required this.priority,
    required this.riskFlags,
    required this.nextAction,
    required this.explanation,
    required this.pRefusal,
    required this.refusalOrgInTraining,
    this.nextActionCode = '',
    this.shap,
  });
  final int priority;
  final List<String> riskFlags;
  final String nextAction;
  final String nextActionCode;
  final String explanation;
  final double pRefusal;
  final bool refusalOrgInTraining;
  final Explanation? shap;
  factory RouteDoctorPanel.fromJson(Map<String, dynamic> json) => RouteDoctorPanel(
        priority: (json['priority'] as num?)?.toInt() ?? 0,
        riskFlags: (json['riskFlags'] as List<dynamic>? ?? []).cast<String>(),
        nextAction: json['nextAction'] as String? ?? '',
        nextActionCode: json['nextActionCode'] as String? ?? '',
        explanation: json['explanation'] as String? ?? '',
        pRefusal: (json['pRefusal'] as num?)?.toDouble() ?? 0,
        refusalOrgInTraining: json['refusalOrgInTraining'] as bool? ?? false,
        shap: json['shap'] == null ? null : Explanation.fromJson(json['shap'] as Map<String, dynamic>),
      );
}

class RouteStandardRef {
  const RouteStandardRef({required this.source, required this.sourceUrl, required this.sourceDate, required this.available});
  final String source;
  final String sourceUrl;
  final String sourceDate;
  final bool available;
  factory RouteStandardRef.fromJson(Map<String, dynamic> json) => RouteStandardRef(
        source: json['source'] as String? ?? '',
        sourceUrl: json['sourceUrl'] as String? ?? '',
        sourceDate: json['sourceDate'] as String? ?? '',
        available: json['available'] as bool? ?? false,
      );
}

/// Маршрут пациента — один контракт для гражданина (`/route/me`) и врача (`/route/{patientRef}`).
class PatientRoute {
  const PatientRoute({
    required this.patientRef,
    required this.synthetic,
    required this.audience,
    required this.asOf,
    required this.regionKato,
    required this.organization,
    required this.stage,
    required this.stageTitle,
    required this.timeline,
    required this.dates,
    required this.daysWaiting,
    required this.forecast,
    required this.benchmarks,
    required this.checklist,
    required this.alternatives,
    this.alternativesModel,
    required this.decisions,
    required this.history,
    this.doctor,
    required this.basis,
    required this.standard,
  });
  final String patientRef;
  final bool synthetic;
  final String audience;
  final String asOf;
  final String regionKato;
  final RouteOrganization organization;
  final String stage;
  final String stageTitle;
  final List<RouteStage> timeline;
  final RouteDates dates;
  final int daysWaiting;
  final RouteForecast forecast;
  final List<RouteBenchmark> benchmarks;
  final List<ChecklistItem> checklist;
  final List<Alternative> alternatives;
  final ModelInfo? alternativesModel;
  final List<RouteDecision> decisions;
  final List<RouteHistoryItem> history;
  final RouteDoctorPanel? doctor;
  final String basis;
  final RouteStandardRef standard;

  RouteBenchmark? get targetBenchmark => benchmarks.where((b) => b.code == 'moh_target_wait_days').firstOrNull;
  int get expiredChecklistCount => checklist.where((c) => c.status == RouteCodes.expired).length;
  RouteDecision? get latestRedirect => decisions.where((d) => d.kind == RouteCodes.redirect).firstOrNull;

  factory PatientRoute.fromJson(Map<String, dynamic> json) => PatientRoute(
        patientRef: json['patientRef'] as String,
        synthetic: json['synthetic'] as bool? ?? true,
        audience: json['audience'] as String? ?? 'citizen',
        asOf: json['asOf'] as String? ?? '',
        regionKato: json['regionKato'] as String? ?? '',
        organization: RouteOrganization.fromJson(json['organization'] as Map<String, dynamic>),
        stage: json['stage'] as String? ?? RouteCodes.waitlisted,
        stageTitle: json['stageTitle'] as String? ?? '',
        timeline: (json['timeline'] as List<dynamic>? ?? []).map((t) => RouteStage.fromJson(t as Map<String, dynamic>)).toList(),
        dates: RouteDates.fromJson(json['dates'] as Map<String, dynamic>? ?? const {}),
        daysWaiting: (json['daysWaiting'] as num?)?.toInt() ?? 0,
        forecast: RouteForecast.fromJson(json['forecast'] as Map<String, dynamic>),
        benchmarks: (json['benchmarks'] as List<dynamic>? ?? []).map((b) => RouteBenchmark.fromJson(b as Map<String, dynamic>)).toList(),
        checklist: (json['checklist'] as List<dynamic>? ?? []).map((c) => ChecklistItem.fromJson(c as Map<String, dynamic>)).toList(),
        alternatives: (json['alternatives'] as List<dynamic>? ?? []).map((a) => Alternative.fromJson(a as Map<String, dynamic>)).toList(),
        alternativesModel: json['alternativesModel'] == null ? null : ModelInfo.fromJson(json['alternativesModel'] as Map<String, dynamic>),
        decisions: (json['decisions'] as List<dynamic>? ?? []).map((d) => RouteDecision.fromJson(d as Map<String, dynamic>)).toList(),
        history: (json['history'] as List<dynamic>? ?? []).map((h) => RouteHistoryItem.fromJson(h as Map<String, dynamic>)).toList(),
        doctor: json['doctor'] == null ? null : RouteDoctorPanel.fromJson(json['doctor'] as Map<String, dynamic>),
        basis: json['basis'] as String? ?? '',
        standard: RouteStandardRef.fromJson(json['standard'] as Map<String, dynamic>? ?? const {}),
      );
}

/// Справочник Стандарта (`/refdata/route-standard`): для гостя — ориентир МЗ РК и сроки давности анализов.
class RouteStandard {
  const RouteStandard({required this.available, required this.source, required this.sourceDate, required this.checklist, required this.benchmarks});
  final bool available;
  final String source;
  final String sourceDate;
  final List<ChecklistDefinition> checklist;
  final List<RouteBenchmark> benchmarks;
  RouteBenchmark? get target => benchmarks.where((b) => b.code == 'moh_target_wait_days').firstOrNull;
  factory RouteStandard.fromJson(Map<String, dynamic> json) {
    final meta = json['meta'] as Map<String, dynamic>? ?? const {};
    return RouteStandard(
      available: json['available'] as bool? ?? false,
      source: meta['source'] as String? ?? '',
      sourceDate: meta['sourceDate'] as String? ?? '',
      checklist: (json['checklist'] as List<dynamic>? ?? []).map((c) => ChecklistDefinition.fromJson(c as Map<String, dynamic>)).toList(),
      benchmarks: (json['benchmarks'] as List<dynamic>? ?? []).map((b) => RouteBenchmark.fromJson(b as Map<String, dynamic>)).toList(),
    );
  }
}

class ChecklistDefinition {
  const ChecklistDefinition({required this.code, required this.title, required this.validityDays, required this.validityLabel});
  final String code;
  final String title;
  final int validityDays;
  final String validityLabel;
  factory ChecklistDefinition.fromJson(Map<String, dynamic> json) => ChecklistDefinition(
        code: json['code'] as String,
        title: json['title'] as String? ?? json['code'] as String,
        validityDays: (json['validityDays'] as num?)?.toInt() ?? 0,
        validityLabel: json['validityLabel'] as String? ?? '',
      );
}
