import 'models.dart';

// Маршрут пациента (docs/api.md, раздел Route) — вынесен из models.dart, чтобы файлы оставались < 600 строк; коды —
// в route_codes.dart, машина состояний и журнал — в route_progress_models.dart. models.dart реэкспортирует все три,
// импорты экранов не меняются.

/// Сигнал гражданина по своему маршруту: подтверждение ожидания, «уже лечился в другом месте», «больше не нужно»,
/// «хочу остаться в своей больнице» или просьба рассмотреть организацию быстрее (toMoCode). Полная история —
/// в [PatientRoute.journal]; signals[] остаётся для «Вы ещё ждёте?» и открытой просьбы.
class RouteSignal {
  const RouteSignal({required this.decisionId, required this.recordedAt, required this.kind, this.toMoCode, this.toMoName, this.comment, required this.open});
  final String decisionId;
  final String recordedAt;

  /// still_waiting | treated_elsewhere | withdraw | request_redirect | prefer_current ([RouteCodes.signalKinds]).
  final String kind;
  final String? toMoCode;
  final String? toMoName;
  final String? comment;

  /// true — маршрут ещё ждёт ответа на этот сигнал; бывает только у request_redirect, withdraw и treated_elsewhere
  /// (still_waiting и prefer_current открытыми не бывают).
  final bool open;
  factory RouteSignal.fromJson(Map<String, dynamic> json) => RouteSignal(
        decisionId: json['decisionId'] as String,
        recordedAt: json['recordedAt'] as String? ?? '',
        kind: json['kind'] as String,
        toMoCode: json['toMoCode'] as String?,
        toMoName: json['toMoName'] as String?,
        comment: json['comment'] as String?,
        open: json['open'] as bool? ?? false,
      );
}

/// Больница и профиль маршрута; после подтверждённого перевода — принимающая больница, а не больница из рефа.
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

/// Этап timeline: 5 или 6 штук, этап «Перевод» вставляется после waitlisted, пока перевод ждёт согласия или
/// подтверждения либо уже подтверждён.
class RouteStage {
  const RouteStage({required this.code, required this.order, required this.title, this.date, required this.status, this.norm});

  /// Один из [RouteCodes.stages] (в том числе transfer); title — локализованная подпись сервера.
  final String code;

  /// Позиционный номер 1…N — не идентификатор этапа: date_assigned бывает и 4-м, и 5-м.
  final int order;
  final String title;

  /// Дата этапа; у transfer — дата подтверждения, иначе предложения; у hospitalized — дата госпитализации.
  final String? date;

  /// done | current | upcoming ([RouteCodes.stageStatuses]); у маршрута, закрытого выпиской, все этапы done.
  final String status;

  /// Норматив Стандарта словами; у transfer — null.
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

  /// `yyyy-MM-dd`; после подтверждённого перевода — дата, назначенная принимающей больницей.
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

/// Решение врача по маршруту — только keep и redirect; ответы пациента и принимающей больницы — в
/// [PatientRoute.journal]. redirect — это предложение: состояние перевода берётся из `progress.transfer`/`status`.
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
    this.patientConsent,
    this.severe = false,
  });
  final String decisionId;
  final String role;
  final String recordedAt;
  final String? fromMoCode;
  final String toMoCode;
  final String toMoName;
  final String? reason;

  /// redirect | keep ([RouteCodes.redirect], [RouteCodes.keep]).
  final String kind;

  /// pending | accepted | declined ([RouteCodes.patientConsents]) — только для kind == redirect; null для keep.
  /// redirect — предложение, ждущее согласия пациента, а не свершившийся перевод (§2.8, §3.3).
  final String? patientConsent;

  /// «Тяжёлый случай» — клиническая отметка врача; видна только персоналу, для гражданина всегда false; у keep — false.
  final bool severe;
  factory RouteDecision.fromJson(Map<String, dynamic> json) => RouteDecision(
        decisionId: json['decisionId'] as String,
        role: json['role'] as String? ?? '',
        recordedAt: json['recordedAt'] as String? ?? '',
        fromMoCode: json['fromMoCode'] as String?,
        toMoCode: json['toMoCode'] as String,
        toMoName: json['toMoName'] as String? ?? json['toMoCode'] as String,
        reason: json['reason'] as String?,
        kind: json['kind'] as String? ?? RouteCodes.keep,
        patientConsent: json['patientConsent'] as String?,
        severe: json['severe'] as bool? ?? false,
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

/// Служебная панель врача; у гражданина всегда null. Флаги, код следующего шага и приоритет — те же, что в строке
/// рабочего списка, но с поправкой на сторону вызывающего (origin / receiving).
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

  /// Фиксированная шкала 0…10: 7–10 — высокий, 4–6 — средний, 0–3 — низкий.
  final int priority;

  /// Коды из [RouteCodes.riskFlags] (8 флагов); незнакомый код показывается запасной подписью.
  final List<String> riskFlags;

  /// Русский текст следующего шага от API — только запасная подпись; для локализации — [nextActionCode].
  final String nextAction;

  /// Один из [RouteCodes.nextActions] (14 кодов, включая closed) или '' у старого сервера.
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
    this.signals = const [],
    this.validationDue = false,
    this.progress,
    this.journal = const [],
  });

  /// SYN-{регион}-{больница очереди}-{профиль}-{NN}; больницу пациента брать из [organization] / `progress`, не из рефа.
  final String patientRef;
  final bool synthetic;

  /// citizen | doctor.
  final String audience;
  final String asOf;
  final String regionKato;

  /// После подтверждённого перевода — принимающая больница.
  final RouteOrganization organization;

  /// Код текущего этапа: waitlisted | transfer | date_assigned | hospitalized; stageTitle — его подпись из timeline.
  final String stage;
  final String stageTitle;
  final List<RouteStage> timeline;
  final RouteDates dates;
  final int daysWaiting;
  final RouteForecast forecast;
  final List<RouteBenchmark> benchmarks;
  final List<ChecklistItem> checklist;

  /// Больницы того же профиля, где ждать меньше; пусто после подтверждённого перевода и у закрытого маршрута. Для
  /// показа и выбора — [offeredAlternatives].
  final List<Alternative> alternatives;
  final ModelInfo? alternativesModel;

  /// Решения врача keep/redirect, свежие первыми.
  final List<RouteDecision> decisions;
  final List<RouteHistoryItem> history;

  /// Служебная панель; у гражданина null.
  final RouteDoctorPanel? doctor;
  final String basis;
  final RouteStandardRef standard;

  /// Сигналы гражданина, свежие первыми.
  final List<RouteSignal> signals;

  /// true — нет подтверждения ожидания за 30 дней и маршрут в waiting/kept: показать «Вы ещё ждёте?».
  final bool validationDue;

  /// Машина состояний маршрута (§3.1): кто сейчас сторона, что ей можно и каков открытый перевод. Объявлено
  /// опциональным в API, но реально всегда заполнено; null — старый сервер без этого поля, разбор не должен падать.
  final RouteProgress? progress;

  /// Полная история маршрута, свежие записи первыми (§3.2) — надмножество decisions[]/signals[].
  final List<RouteJournalEntry> journal;

  /// Сигнал, на который маршрут ещё ждёт ответа: request_redirect, withdraw или treated_elsewhere.
  RouteSignal? get openSignal => signals.where((s) => s.open).firstOrNull;

  /// Открытая просьба гражданина рассмотреть другую больницу.
  RouteSignal? get openRequest => signals.where((s) => s.open && s.kind == RouteCodes.requestRedirect).firstOrNull;
  RouteBenchmark? get targetBenchmark => benchmarks.where((b) => b.code == 'moh_target_wait_days').firstOrNull;
  int get expiredChecklistCount => checklist.where((c) => c.status == RouteCodes.expired).length;
  int get validChecklistCount => checklist.length - expiredChecklistCount;

  /// Самое свежее предложение перевода из decisions[] — только история: оно может быть уже отклонено, отменено или
  /// отказано. Идёт ли перевод сейчас и куда — `progress.transfer` и `progress.status`.
  RouteDecision? get latestRedirect => decisions.where((d) => d.kind == RouteCodes.redirect).firstOrNull;

  /// true — [action] сейчас разрешено этой стороне (`progress.allowed`); экраны должны показывать действия
  /// только по этому флагу, а не по одному разрешению RBAC (§4.11, §2.5).
  bool can(String action) => progress?.allowed.contains(action) ?? false;

  /// [alternatives] без больниц, уже заблокированных для этого маршрута (`progress.blockedMoCodes`) — отказавших
  /// или отклонённых пациентом (§3.1).
  List<Alternative> get offeredAlternatives {
    final blocked = progress?.blockedMoCodes ?? const <String>[];
    if (blocked.isEmpty) {
      return alternatives;
    }
    return alternatives.where((a) => !blocked.contains(a.moCode)).toList();
  }

  /// Самое свежее решение врача keep/redirect (ISO-даты сравниваются как строки). Это история, а не состояние:
  /// для карточки «что сейчас» — `progress.status` и `progress.transfer`.
  RouteDecision? get latestDecision =>
      decisions.isEmpty ? null : decisions.reduce((a, b) => a.recordedAt.compareTo(b.recordedAt) >= 0 ? a : b);

  /// Ближайший непройденный этап Стандарта — «следующий этап» в карточке «Что сейчас».
  RouteStage? get nextStage {
    final ordered = [...timeline]..sort((a, b) => a.order.compareTo(b.order));
    return ordered.where((t) => t.status == RouteCodes.upcoming).firstOrNull;
  }

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
        signals: (json['signals'] as List<dynamic>? ?? []).map((x) => RouteSignal.fromJson(x as Map<String, dynamic>)).toList(),
        validationDue: json['validationDue'] as bool? ?? false,
        progress: json['progress'] == null ? null : RouteProgress.fromJson(json['progress'] as Map<String, dynamic>),
        journal: List.unmodifiable((json['journal'] as List<dynamic>? ?? const []).map((j) => RouteJournalEntry.fromJson(j as Map<String, dynamic>))),
      );
}

/// Справочник Стандарта (`/refdata/route-standard`): на главной — ориентир МЗ РК и сроки давности анализов.
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
