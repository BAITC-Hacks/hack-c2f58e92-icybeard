import 'models.dart';

// Маршрут пациента (docs/api.md, раздел Route) — вынесен из models.dart, чтобы файлы оставались < 800 строк;
// models.dart реэкспортирует этот файл, импорты экранов не меняются.

/// Коды стадий и статусов маршрута — те же, что в API (RouteStages, RouteChecklistStatus, RouteOutcomes,
/// RouteProgress, RouteJournal, Worklist). Группы ниже совпадают с разделами контракта; значение-строка может
/// совпадать у разных групп (kind=redirect и action=redirect — буквально один и тот же код сервера), но названы
/// раздельно ради понятного места использования на вызывающей стороне.
abstract final class RouteCodes {
  static const referralIssued = 'referral_issued';
  static const examination = 'examination';
  static const waitlisted = 'waitlisted';
  static const dateAssigned = 'date_assigned';
  static const hospitalized = 'hospitalized';
  static const refused = 'refused';

  /// Новая стадия timeline: вставляется после waitlisted, пока перевод ожидает согласия/подтверждения (§3.3).
  static const transferStage = 'transfer';

  static const done = 'done';
  static const current = 'current';
  static const upcoming = 'upcoming';

  static const valid = 'valid';
  static const expiring = 'expiring';
  static const expired = 'expired';

  // decisions[].kind и действия врача — те же строки, что и progress.allowed ниже
  static const redirect = 'redirect';
  static const keep = 'keep';

  // сигналы гражданина по маршруту (RouteSignals в API) и флаг открытого сигнала в рабочем списке
  static const stillWaiting = 'still_waiting';
  static const treatedElsewhere = 'treated_elsewhere';
  static const withdraw = 'withdraw';
  static const requestRedirect = 'request_redirect';
  static const preferCurrent = 'prefer_current';
  static const patientSignalFlag = 'patient_signal';

  // progress.status — состояние маршрута как явной машины состояний (§3.1)
  static const statusWaiting = 'waiting';
  static const statusKept = 'kept';
  static const statusTransferPendingConsent = 'transfer_pending_consent';
  static const statusTransferPendingConfirmation = 'transfer_pending_confirmation';
  static const statusTransferred = 'transferred';
  static const statusAdmitted = 'admitted';
  static const statusWithdrawalRequested = 'withdrawal_requested';
  static const statusClosed = 'closed';

  // progress.allowed — что эта сторона может сделать прямо сейчас (16 кодов, §3.1)
  static const actionRequestTransfer = 'request_transfer';
  static const actionPreferCurrent = 'prefer_current';
  static const actionStillWaiting = 'still_waiting';
  static const actionWithdraw = 'withdraw';
  static const actionAcceptTransfer = 'accept_transfer';
  static const actionDeclineTransfer = 'decline_transfer';
  static const actionKeep = 'keep';
  static const actionRedirect = 'redirect';
  static const actionCancelTransfer = 'cancel_transfer';
  static const actionClose = 'close';
  static const actionConfirm = 'confirm';
  static const actionReject = 'reject';
  static const actionReschedule = 'reschedule';
  static const actionAdmit = 'admit';
  static const actionNoShow = 'no_show';
  static const actionDischarge = 'discharge';

  // progress.side — кто сейчас действует по этому маршруту
  static const sideNone = 'none';
  static const sideCitizen = 'citizen';
  static const sideOrigin = 'origin';
  static const sideReceiving = 'receiving';

  // progress.closedReason
  static const closedDischarged = 'discharged';
  static const closedNoShow = 'no_show';
  static const closedWithdrawn = 'withdrawn';
  static const closedTreatedElsewhere = 'treated_elsewhere';

  // progress.lastAttempt.outcome (docs/web также упоминают no_show — сервер его не шлёт, см. §6)
  static const attemptDeclined = 'declined';
  static const attemptConsentWithdrawn = 'consent_withdrawn';
  static const attemptCancelled = 'cancelled';
  static const attemptRejected = 'rejected';
  static const attemptPatientWithdrew = 'patient_withdrew';

  // decisions[].patientConsent (только для kind == redirect)
  static const consentPending = 'pending';
  static const consentAccepted = 'accepted';
  static const consentDeclined = 'declined';

  // journal[].kind — полная упорядоченная история маршрута (§3.2); request — не requestRedirect из сигналов
  static const journalRequest = 'request';
  static const journalConsentAccepted = 'consent_accepted';
  static const journalConsentDeclined = 'consent_declined';
  static const journalCancel = 'cancel';
  static const journalClose = 'close';

  // worklist riskFlags — добавлены к уже существующему patientSignalFlag
  static const flagStuckOver30 = 'stuck_over_30';
  static const flagRefusalRisk = 'refusal_risk';
  static const flagFasterAlternative = 'faster_alternative';
  static const flagTransferPending = 'transfer_pending';
  static const flagTransferredIn = 'transferred_in';
  static const flagPrefersCurrent = 'prefers_current';
  static const flagDateOverdue = 'date_overdue';

  // worklist/doctor nextActionCode — 14 кодов (Worklist.cs:84-100)
  static const nextRedirectFaster = 'redirect_faster';
  static const nextReviewBeforeCall = 'review_before_call';
  static const nextClarifyDate = 'clarify_date';
  static const nextWaitForCall = 'wait_for_call';
  static const nextDecisionMade = 'decision_made';
  static const nextAwaitConsent = 'await_consent';
  static const nextAwaitConfirmation = 'await_confirmation';
  static const nextConfirmAdmission = 'confirm_admission';
  static const nextTransferredOut = 'transferred_out';
  static const nextAdmitOnDate = 'admit_on_date';
  static const nextDateOverdue = 'date_overdue';
  static const nextDischargeWhenDone = 'discharge_when_done';
  static const nextConfirmWithdrawal = 'confirm_withdrawal';
  static const nextClosed = 'closed';

  // виды уведомлений гражданина сверх journal[].kind (§3.7)
  static const notificationTestsExpiring = 'tests_expiring';
  static const notificationScribeConsent = 'scribe_consent';
  static const notificationScribeLeaflet = 'scribe_leaflet';

  // "вид" в POST /journal/notifications/bell/{kind}/{id}/read
  static const bellReferralConfirmed = 'referral-confirmed';
  static const bellReferralDischarged = 'referral-discharged';
  static const bellPatientSignal = 'patient-signal';

  // patientSignals[].kind сверх journal[].kind (PatientSignals.cs:12-24)
  static const patientEventScribeGranted = 'scribe_granted';
  static const patientEventScribeDeclined = 'scribe_declined';
  static const patientEventScribeWithdrawn = 'scribe_withdrawn';

  // статус согласия на запись приёма (ScribeConsents.cs:7-36)
  static const scribePending = 'pending';
  static const scribeGranted = 'granted';
  static const scribeDeclined = 'declined';
  static const scribeWithdrawn = 'withdrawn';
  static const scribeCancelled = 'cancelled';
  static const scribeExpired = 'expired';
  static const scribeRecording = 'recording';
  static const scribeDiscarded = 'discarded';
  static const scribeCompleted = 'completed';

  // источник правки фразы стенограммы (§3.10.5)
  static const sourceDoctor = 'doctor';
  static const sourceAi = 'ai';
  static const sourceDictionary = 'dictionary';
}

/// Сигнал гражданина по своему маршруту: подтверждение ожидания, «уже лечился в другом месте», «больше не нужно»
/// или просьба рассмотреть организацию быстрее (toMoCode). open — врач ещё не ответил решением.
class RouteSignal {
  const RouteSignal({required this.decisionId, required this.recordedAt, required this.kind, this.toMoCode, this.toMoName, this.comment, required this.open});
  final String decisionId;
  final String recordedAt;
  final String kind;
  final String? toMoCode;
  final String? toMoName;
  final String? comment;
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

  /// redirect | keep
  final String kind;

  /// pending | accepted | declined — только для kind == redirect; null для keep (теперь это предложение, а не
  /// свершившийся факт, см. §2.8, §3.3).
  final String? patientConsent;

  /// Клиническая отметка врача; видна только принимающей организации, для гражданина всегда false (§3.1).
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
    this.signals = const [],
    this.validationDue = false,
    this.progress,
    this.journal = const [],
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

  /// Сигналы гражданина, свежие первыми; validationDue — нет подтверждения ожидания за 30 дней, показать «Вы ещё ждёте?».
  final List<RouteSignal> signals;
  final bool validationDue;

  /// Машина состояний маршрута (§3.1): кто сейчас сторона, что ей можно и каков открытый перевод. Объявлено
  /// опциональным в API, но реально всегда заполнено; null — старый сервер без этого поля, разбор не должен падать.
  final RouteProgress? progress;

  /// Полная история маршрута, свежие записи первыми (§3.2) — надмножество decisions[]/signals[].
  final List<RouteJournalEntry> journal;

  RouteSignal? get openSignal => signals.where((s) => s.open).firstOrNull;
  RouteSignal? get openRequest => signals.where((s) => s.open && s.kind == RouteCodes.requestRedirect).firstOrNull;
  RouteBenchmark? get targetBenchmark => benchmarks.where((b) => b.code == 'moh_target_wait_days').firstOrNull;
  int get expiredChecklistCount => checklist.where((c) => c.status == RouteCodes.expired).length;
  int get validChecklistCount => checklist.length - expiredChecklistCount;
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

  /// Самое свежее решение врача (ISO-даты сравниваются как строки) — «ответ врача» на главной и в «Что сейчас».
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
        journal: (json['journal'] as List<dynamic>? ?? const []).map((j) => RouteJournalEntry.fromJson(j as Map<String, dynamic>)).toList(),
      );
}

/// Состояние маршрута как машины состояний (§3.1) — что с ним сейчас происходит и что эта сторона может сделать.
class RouteProgress {
  const RouteProgress({
    required this.status,
    required this.originMoCode,
    required this.responsibleMoCode,
    required this.responsibleMoName,
    this.transfer,
    this.lastAttempt,
    this.prefersCurrent = false,
    this.closedReason,
    this.closedAt,
    this.overdue = false,
    this.allowed = const [],
    this.blockedMoCodes = const [],
    this.side = RouteCodes.sideNone,
  });

  /// waiting | kept | transfer_pending_consent | transfer_pending_confirmation | transferred | admitted |
  /// withdrawal_requested | closed (RouteCodes.status*).
  final String status;

  /// Больница, закодированная в patientRef — откуда пациент встал в очередь.
  final String originMoCode;

  /// origin, пока перевод не подтверждён, иначе — принимающая больница (transfer.toMoCode).
  final String responsibleMoCode;
  final String responsibleMoName;

  /// Текущий перевод; null — нет активного перевода, или он уже завершился (отказ/отзыв/отмена/перевод закрыт).
  final RouteTransfer? transfer;

  /// Последний неудавшийся перевод — для подсказки «уже отказали» (null, если такого не было).
  final RouteTransferAttempt? lastAttempt;

  /// Гражданин попросил остаться в своей больнице; сбрасывается следующим request_redirect.
  final bool prefersCurrent;

  /// discharged | no_show | withdrawn | treated_elsewhere — только когда status == closed.
  final String? closedReason;
  final String? closedAt;

  /// true — маршрут в статусе transferred и сегодня позже plannedAt + 3 дня (Asia/Almaty).
  final bool overdue;

  /// Что может сделать именно этот вызывающий прямо сейчас — единственный источник для показа действий (§4.11).
  final List<String> allowed;

  /// Больницы, которые нельзя предложить этому маршруту (отказали или их отклонил пациент).
  final List<String> blockedMoCodes;

  /// none | citizen | origin | receiving.
  final String side;

  factory RouteProgress.fromJson(Map<String, dynamic> json) => RouteProgress(
        status: json['status'] as String? ?? RouteCodes.statusWaiting,
        originMoCode: json['originMoCode'] as String? ?? '',
        responsibleMoCode: json['responsibleMoCode'] as String? ?? '',
        responsibleMoName: json['responsibleMoName'] as String? ?? json['responsibleMoCode'] as String? ?? '',
        transfer: json['transfer'] == null ? null : RouteTransfer.fromJson(json['transfer'] as Map<String, dynamic>),
        lastAttempt: json['lastAttempt'] == null ? null : RouteTransferAttempt.fromJson(json['lastAttempt'] as Map<String, dynamic>),
        prefersCurrent: json['prefersCurrent'] as bool? ?? false,
        closedReason: json['closedReason'] as String?,
        closedAt: json['closedAt'] as String?,
        overdue: json['overdue'] as bool? ?? false,
        allowed: (json['allowed'] as List<dynamic>? ?? const []).cast<String>(),
        blockedMoCodes: (json['blockedMoCodes'] as List<dynamic>? ?? const []).cast<String>(),
        side: json['side'] as String? ?? RouteCodes.sideNone,
      );
}

/// Перевод, который сейчас определяет маршрут — предложен, ждёт согласия/подтверждения или уже подтверждён (§3.1).
class RouteTransfer {
  const RouteTransfer({
    required this.decisionId,
    required this.toMoCode,
    required this.toMoName,
    this.severe = false,
    this.reason,
    required this.proposedAt,
    this.consentAt,
    this.confirmedAt,
    this.plannedAt,
    this.admittedAt,
  });

  /// Id решения-redirect — ключ для `POST /route/me/consent` и для `/journal/referrals/{id}/…`.
  final String decisionId;
  final String toMoCode;
  final String toMoName;

  /// Клиническая отметка врача; для гражданина всегда false.
  final bool severe;
  final String? reason;
  final String proposedAt;
  final String? consentAt;
  final String? confirmedAt;

  /// `yyyy-MM-dd`; появляется при confirm, меняется при reschedule.
  final String? plannedAt;
  final String? admittedAt;

  factory RouteTransfer.fromJson(Map<String, dynamic> json) => RouteTransfer(
        decisionId: json['decisionId'] as String? ?? '',
        toMoCode: json['toMoCode'] as String? ?? '',
        toMoName: json['toMoName'] as String? ?? json['toMoCode'] as String? ?? '',
        severe: json['severe'] as bool? ?? false,
        reason: json['reason'] as String?,
        proposedAt: json['proposedAt'] as String? ?? '',
        consentAt: json['consentAt'] as String?,
        confirmedAt: json['confirmedAt'] as String?,
        plannedAt: json['plannedAt'] as String?,
        admittedAt: json['admittedAt'] as String?,
      );
}

/// Последняя неудавшаяся попытка перевода — подсказка «эта больница уже отказала» (§3.1).
class RouteTransferAttempt {
  const RouteTransferAttempt({required this.outcome, required this.toMoCode, required this.toMoName, required this.at, this.reason});

  /// declined | consent_withdrawn | cancelled | rejected | patient_withdrew (RouteCodes.attempt*).
  final String outcome;
  final String toMoCode;
  final String toMoName;
  final String at;
  final String? reason;

  factory RouteTransferAttempt.fromJson(Map<String, dynamic> json) => RouteTransferAttempt(
        outcome: json['outcome'] as String? ?? '',
        toMoCode: json['toMoCode'] as String? ?? '',
        toMoName: json['toMoName'] as String? ?? json['toMoCode'] as String? ?? '',
        at: json['at'] as String? ?? '',
        reason: json['reason'] as String?,
      );
}

/// Одна строка полной истории маршрута (§3.2) — надмножество decisions[]/signals[], самые новые первыми.
class RouteJournalEntry {
  const RouteJournalEntry({
    required this.id,
    required this.at,
    required this.kind,
    required this.role,
    this.moCode,
    this.moName,
    this.reason,
    this.plannedAt,
    this.severe = false,
  });

  /// Id записи журнала; для kind == redirect равен progress.transfer.decisionId, пока этот перевод актуален.
  final String id;
  final String at;

  /// request | prefer_current | still_waiting | withdraw | treated_elsewhere | keep | redirect | consent_accepted |
  /// consent_declined | confirm | reject | reschedule | admit | no_show | discharge | cancel | close.
  final String kind;

  /// Роль автора записи: citizen | doctor | org_admin | …
  final String role;

  /// Целевая/своя больница — смысл зависит от kind (§3.2); null для close, still_waiting, prefer_current, withdraw,
  /// treated_elsewhere.
  final String? moCode;
  final String? moName;

  /// Причина врача / комментарий гражданина; для discharge — эпикриз персоналу и null гражданину.
  final String? reason;

  /// Только для confirm и reschedule, `yyyy-MM-dd`.
  final String? plannedAt;

  /// Только для redirect; для гражданина всегда false.
  final bool severe;

  factory RouteJournalEntry.fromJson(Map<String, dynamic> json) => RouteJournalEntry(
        id: json['id'] as String? ?? '',
        at: json['at'] as String? ?? '',
        kind: json['kind'] as String? ?? '',
        role: json['role'] as String? ?? '',
        moCode: json['moCode'] as String?,
        moName: json['moName'] as String?,
        reason: json['reason'] as String?,
        plannedAt: json['plannedAt'] as String?,
        severe: json['severe'] as bool? ?? false,
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
