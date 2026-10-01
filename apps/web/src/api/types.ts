export interface ModelInfo { name: string; version: string; trainedThrough: string }
export interface Factor { name: string; contribution: number; text: string }
export interface Explanation { summary: string; factors: Factor[] }
export interface Paged<T> { items: T[]; page: number; size: number; total: number }

export interface PredictRequest {
  regionKato?: string | null
  moCode?: string | null
  profileCode: string
  icd10?: string | null
  referralPurpose?: string | null
  territorialType?: string | null
  financeSource?: string | null
  registrationDate?: string | null
  /** необязательно: направляющая организация — модель получит признак same_mo */
  referringMoCode?: string | null
}
export interface QueueSnapshot { len: number; ageP50: number | null; throughputPerDay: number }
export interface PredictResponse {
  p50Days: number; p90Days: number; pWithin30Days: number; pRefusal: number
  /** false — организация не была в обучении, риск отказа показываем словами, не процентом */
  refusalOrgInTraining?: boolean
  queue: QueueSnapshot | null; explanation: Explanation; model: ModelInfo
}
export interface Organization { moCode: string; name: string; regionKato: string }
export interface Alternative { mo: Organization; p50Days: number; p90Days: number; pRefusal: number; distanceKm: number; isNeighborRegion: boolean }
export interface AlternativesResponse { items: Alternative[]; model: ModelInfo }
export interface QueueDay { day: string; registered: number; hospitalized: number; refused: number; queueLen: number; queueAgeP50: number | null }
export interface Throughput { day: string; throughputPerDay: number; refusalRate4w: number | null; waitP50Days: number | null; waitP90Days: number | null }
export interface OrganizationSeries { moCode: string; profileCode: string; days: QueueDay[]; throughput: Throughput | null }

export interface Stream { streamId: string; title: string; grain: string; entityKeys: string[]; horizons: number[] }
export interface ForecastPoint { period: string; yhat: number; lo: number; hi: number }
export interface HistoryPoint { period: string; y: number }
export interface ForecastResponse {
  streamId: string; entity: Record<string, string>; points: ForecastPoint[]; history: HistoryPoint[]
  backtest: { smape: number; mase: number; baselineSmape: number }; model: ModelInfo
  /** Прогноз повторяет один уровень («уровень последнего месяца») — для планирования малоинформативен. */
  flat?: boolean
}
export interface Anomaly {
  id: string; streamId: string; entity: Record<string, string>; period: string; observed: number; expected: number
  score: number; peerScore: number; severity: string; kind: string; status: string; regionKato: string | null; comment: string | null
  /** не у всех потоков сигнал привязан к организации (например, у помесячных региональных) */
  moCode: string | null
  /** только у kind === 'shared': сколько сущностей (например, организаций) затронула волна — differentiating-ключи в entity для неё пусты */
  affected: number | null
}
/** Внешняя сезонная форма (NHS): множитель месяца при среднегодовом = 1. */
export interface Seasonality { seriesId: string; month: number; multiplier: number; title: string; source: string; sourceYear: number; windowLabel: string }
/** Оценка охвата вакцинацией WUENIC (ВОЗ/ЮНИСЕФ) — внешний ориентир, не факт. */
export interface VaccinationBenchmark { vaccine: string; titleRu: string; year: number; coveragePct: number; source: string; note: string }

export interface IndexItem { regionKato: string; name: string; shareOver30: number; p90Days: number; indexValue: number; rank: number; n: number }
export interface IndexResponse { month: string; profileCode: string; items: IndexItem[]; months: string[]; method: string }

/** Ячейка длительности лечения регион×профиль из gold.los_by_profile. */
export interface LosItem { regionKato: string; profileName: string; profileCode: string | null; n: number; losMedianFact: number; losP50Model: number | null }
export interface LosResponse { items: LosItem[]; method: string }

/** 5.2: ставки на 10 тыс. населения и на 1 000 госпитализаций (12 мес.) по региону, из gold.staffing_by_region. */
export interface StaffingRegion {
  regionKato: string
  regionName: string
  ratePer10kPopulation: number
  ratePer1000Admissions: number | null
  snapshotDate: string
}
export interface StaffingResponse { items: StaffingRegion[]; method: string }

/** 5.8: отказ от вакцинации по причине/противопоказанию, только общенационально — в vac_refusals нет региона. */
export interface VacRefusalReason { reason: string; n: number }
export interface VacRefusalContraindication { contraindication: string; n: number }
export interface VaccinationRefusalsResponse {
  byReason: VacRefusalReason[]
  byContraindication: VacRefusalContraindication[]
  method: string
}

/** 5.8: доля запущенных случаев (III/IV стадии) по локализации, только общенационально из gold.onco_late. */
export interface OncoLateItem {
  localizationId: string
  localizationName: string
  icdCode: string | null
  totalPatients: number
  advancedStage3Count: number
  advancedStage3Pct: number | null
  advancedStage4Count: number
  advancedStage4Pct: number | null
  advancedTotalCount: number
  advancedShare: number | null
  snapshotDate: string
}
export interface OncologyLateStageResponse { items: OncoLateItem[]; method: string }

/** 5.10: число единиц активной медтехники по региону из gold.equipment_by_region, для сравнения на /gov. */
export interface EquipmentRegion { regionKato: string; regionName: string; units: number }
export interface EquipmentResponse { items: EquipmentRegion[]; method: string }

/** 5.10: число единиц активной медтехники организации, для кабинета организации. */
export interface EquipmentOrganization { moCode: string; units: number }

/** Срез ошибки wait-модели по региону или профилю из отчёта обучения. */
export interface QualityBreakdownRow {
  region_kato?: string; profile_code?: string; n: number
  pinball_p50: number; pinball_p50_baseline: number; mae_p50: number; mae_p50_baseline: number
}
export interface QualitySplit {
  n: number; n_admitted: number
  pinball_p50: number; pinball_p50_baseline: number; pinball_p90: number; pinball_p90_baseline: number
  mae_p50: number; mae_p50_baseline: number; coverage_p90: number; coverage_p90_baseline: number
  auc_within30: number; auc_refusal: number; auc_refusal_baseline: number
}
export interface QualityForecast {
  series?: number; chosen?: string; baseline?: string; flat_share?: number; skipped?: string
  per_series_choice?: Record<string, number>
  models?: Record<string, { mase: number; smape: number }>
}
export interface QualityReport {
  wait: {
    trainedThrough?: string; trainRows?: number
    test_time?: QualitySplit; test_mo?: QualitySplit
    by_region?: QualityBreakdownRow[]; by_profile?: QualityBreakdownRow[]
  } | null
  forecasts: Record<string, QualityForecast>
  anomalies: Record<string, { alerts?: number; precision_at_k?: number; recall_at_threshold?: number }>
  simulate: { saved_share?: number; saved_share_band?: number[]; consistency_spearman?: number; horizon_days?: number } | null
  /** Отчёт LOS-модели (LightGBM-квантиль p50 длительности лечения). */
  los?: {
    train_rows?: number; test_rows?: number; test_window?: string
    pinball_p50?: number; pinball_p50_baseline?: number; mae?: number; mae_baseline?: number
    median_los_days?: number; cells?: number
  } | null
  /** Отчёт survival-модели (лог-логистическое AFT, вероятность госпитализации к дате). */
  survival?: {
    train_rows?: number; censored_share?: number; note?: string
    splits?: Record<string, {
      n: number; c_index: number; c_index_baseline: number; auc30: number; auc30_baseline: number
      p_admit_mean?: Record<string, number>; observed_share?: Record<string, number>
    }>
  } | null
  /** Отчёт дообучения детектора на разметке (или причина пропуска). */
  anomalyLabelsModel?: { labels?: number; positives?: number; negatives?: number; skipped?: string; auc_cv?: number; auc_baseline_abs_score?: number } | null
  /** Разметка сигналов людьми (журнал подтверждений): статус → число. */
  anomalyLabels?: Record<string, number>
}

export interface SimulateResponse {
  organisations: number; baseline: { meanWaitDays: number }; scenario: { meanWaitDays: number }
  deltaDays: number; ci: number[]; assumptions: string[]; model: ModelInfo
  /** 3.4: пропускная способность сценария (госпитализации в день), с учётом «+N коек»; null, если сервис старый. */
  admissionsPerDay: number | null
}
export interface OrganizationRef { moCode: string; name: string; regionKato: string }
export interface Move {
  fromMo: OrganizationRef; toMo: OrganizationRef; sharePct: number; arrivalsPerDay: number
  waitFromBefore: number; waitFromAfter: number; waitToBefore: number; waitToAfter: number
}
export interface RedistributeResponse { moves: Move[]; totalWaitDaysBefore: number; totalWaitDaysAfter: number; totalDeltaDays: number; horizonDays: number; model: ModelInfo }

export interface DecisionRequest { subject: string; subjectId: string; recommended?: unknown; chosen?: unknown; reason?: string }
export interface Decision {
  decisionId: string; actor: string; role: string; subject: string; subjectId: string
  recommended: unknown; chosen: unknown; reason: string | null; recordedAt: string
}
export interface DecisionCreated { decisionId: string; recordedAt: string }
export interface AuditEntry {
  id: number; at: string; actor: string; role: string; method: string; path: string; query: string | null; status: number; durationMs: number; traceId: string
}
export interface WorklistItem {
  patientRef: string; synthetic: boolean; stage: string; stageCode: string; expectedDate: string | null; riskFlags: string[]
  priority: number; nextAction: string; nextActionCode: string; explanation: string; moCode: string; moName: string; profileCode: string; regionKato: string; daysWaiting: number
  /** Открытый сигнал гражданина (в riskFlags при этом есть patient_signal); null — сигнала нет. */
  patientSignal: PatientSignal | null
}
export interface PatientSignal { kind: SignalKind; toMoCode: string | null; toMoName: string | null; comment: string | null; recordedAt: string }
export type SignalKind = 'still_waiting' | 'treated_elsewhere' | 'withdraw' | 'request_redirect' | 'prefer_current'
/** Конверт /journal/worklist: modelBacked=false — прогнозы посчитаны по агрегатам витрины, а не моделью. */
export interface WorklistResponse { items: WorklistItem[]; synthetic: boolean; asOf: string; regionKato: string; modelBacked: boolean }

/** Маршрут пациента (docs/api.md, раздел Route): один контракт для гражданина (/route/me) и врача (/route/{ref}). */
export interface RouteOrganization { moCode: string; moName: string; profileCode: string; profileName: string }
export interface RouteStage { code: string; order: number; title: string; date: string | null; status: 'done' | 'current' | 'upcoming'; norm: string | null }
export interface RouteDates { issuedAt: string; registeredAt: string; plannedAt: string | null; expectedAt: string }
export interface RouteForecast { p50Days: number; p90Days: number; pWithin30Days: number | null; fromModel: boolean; model: ModelInfo | null }
export interface RouteBenchmark { code: string; value: number; unit: string; title: string; source: string; sourceDate: string }
export interface RouteChecklistItem {
  code: string; title: string; validityDays: number; validityLabel: string; doneAt: string; validUntil: string; status: 'valid' | 'expiring' | 'expired'
}
/** patientConsent — только для kind = redirect: pending, пока пациент не ответил, иначе accepted | declined; для keep всегда null.
 * severe — клинический флаг тяжести (задача 3): видно только врачу, гражданину в интерфейсе не показывается. */
export interface RouteDecision {
  decisionId: string; role: string; recordedAt: string; fromMoCode: string | null; toMoCode: string; toMoName: string; reason: string | null; kind: 'redirect' | 'keep'
  patientConsent: 'pending' | 'accepted' | 'declined' | null; severe: boolean
}
export interface RouteHistoryItem {
  moCode: string; moName: string; profileCode: string; profileName: string; registeredAt: string; outcome: 'hospitalized' | 'refused'; outcomeAt: string; waitDays: number
}
/** Сигнал гражданина по своему маршруту (POST /route/me/signals): валидация листа ожидания или просьба рассмотреть организацию; open — врач ещё не ответил. */
export interface RouteSignal {
  decisionId: string; recordedAt: string; kind: SignalKind; toMoCode: string | null; toMoName: string | null; comment: string | null; open: boolean
}
/** Только для врача: гражданину API отдаёт doctor = null (риск отказа и приоритет — служебная информация). */
export interface RouteDoctorPanel {
  priority: number; riskFlags: string[]; nextAction: string; nextActionCode: string; explanation: string; pRefusal: number; refusalOrgInTraining: boolean; shap: Explanation | null
}
export interface RouteStandardRef { source: string; sourceUrl: string; sourceDate: string; available: boolean }
/** Справочник Стандарта стационарной помощи (GET /refdata/route-standard): стадии, причины отказа, обследования, ориентиры МЗ РК. */
export interface RouteStageDef { code: string; order: number; title: string; norm: string; normWorkingDays: number | null; rescheduleMaxDays: number | null; noShowDays: number | null }
export interface RouteChecklistDef { code: string; title: string; validityDays: number; validityLabel: string }
export interface RouteStandard {
  meta: { source: string; sourceUrl: string; sourceDate: string }; available: boolean; stages: RouteStageDef[]
  refusalReasons: { code: string; title: string }[]; checklist: RouteChecklistDef[]; benchmarks: RouteBenchmark[]
}
export interface PatientRoute {
  patientRef: string; synthetic: boolean; audience: 'citizen' | 'doctor'; asOf: string; regionKato: string; organization: RouteOrganization
  stage: string; stageTitle: string; timeline: RouteStage[]; dates: RouteDates; daysWaiting: number; forecast: RouteForecast
  benchmarks: RouteBenchmark[]; checklist: RouteChecklistItem[]; alternatives: Alternative[]; alternativesModel: ModelInfo | null
  decisions: RouteDecision[]; history: RouteHistoryItem[]; doctor: RouteDoctorPanel | null; basis: string; standard: RouteStandardRef
  /** Сигналы гражданина, свежие первыми; validationDue — нет подтверждения ожидания за 30 дней, показать «Вы ещё ждёте?». */
  signals: RouteSignal[]; validationDue: boolean
  /** Состояние маршрута по журналу и что может сделать именно этот пользователь (allowed) — экраны правил не вычисляют. */
  progress: RouteProgress | null
  /** Хроника: всё, что сделали люди, свежие первыми. */
  journal: RouteJournalEntry[] | null
}

export type RouteStatus =
  | 'waiting' | 'kept' | 'transfer_pending_consent' | 'transfer_pending_confirmation' | 'transferred' | 'admitted' | 'withdrawal_requested' | 'closed'
export type RouteAction =
  | 'request_transfer' | 'prefer_current' | 'still_waiting' | 'withdraw' | 'accept_transfer' | 'decline_transfer' | 'keep' | 'redirect'
  | 'cancel_transfer' | 'close' | 'confirm' | 'reject' | 'reschedule' | 'admit' | 'no_show' | 'discharge'
export type RouteSide = 'none' | 'citizen' | 'origin' | 'receiving'
export interface RouteTransfer {
  decisionId: string; toMoCode: string; toMoName: string; severe: boolean; reason: string | null; proposedAt: string; consentAt: string | null
  confirmedAt: string | null; plannedAt: string | null; admittedAt: string | null
}
export type TransferOutcome = 'declined' | 'consent_withdrawn' | 'cancelled' | 'rejected' | 'patient_withdrew' | 'no_show'
export interface RouteTransferAttempt { outcome: TransferOutcome; toMoCode: string; toMoName: string; at: string; reason: string | null }
export interface RouteProgress {
  status: RouteStatus; originMoCode: string; responsibleMoCode: string; responsibleMoName: string; transfer: RouteTransfer | null
  lastAttempt: RouteTransferAttempt | null; prefersCurrent: boolean; closedReason: 'discharged' | 'no_show' | 'withdrawn' | 'treated_elsewhere' | null
  closedAt: string | null; overdue: boolean; allowed: RouteAction[]; blockedMoCodes: string[]; side: RouteSide
}
export type RouteJournalKind =
  | 'request' | 'prefer_current' | 'still_waiting' | 'withdraw' | 'treated_elsewhere' | 'keep' | 'redirect' | 'consent_accepted' | 'consent_declined'
  | 'confirm' | 'reject' | 'reschedule' | 'admit' | 'no_show' | 'discharge' | 'cancel' | 'close'
export interface RouteJournalEntry {
  id: string; at: string; kind: RouteJournalKind; role: string; moCode: string | null; moName: string | null; reason: string | null
  plannedAt: string | null; severe: boolean
}
/** Колокольчик гражданина (GET /route/me/notifications): needsAction — нужен его ответ на перевод. */
export interface CitizenNotification {
  id: string; kind: RouteJournalKind | 'tests_expiring' | 'scribe_consent' | 'scribe_leaflet'; at: string; moName: string | null; plannedAt: string | null; reason: string | null
  needsAction: boolean; read: boolean; count: number | null
}
export interface CitizenNotifications { unread: number; items: CitizenNotification[] }

/** Входящее направление в организацию (задача 4): GET /journal/referrals/incoming, POST /journal/referrals/{id}/confirm.
 * Confirmed/confirmedAt — уже подтверждено принимающей организацией; подтвердить можно только когда patientConsent === 'accepted'. */
export interface IncomingReferral {
  decisionId: string; patientRef: string; fromMoCode: string; fromMoName: string; profileCode: string; reason: string | null
  recordedAt: string; severe: boolean; patientConsent: 'pending' | 'accepted' | 'declined'; confirmed: boolean; confirmedAt: string | null
  /** Эпикриз выписки (задача 11): появляется только после confirmed - принимающая сторона закрывает лечение. */
  discharged: boolean; dischargedAt: string | null
  /** Состояние маршрута и что может сделать эта больница сейчас (allowed); plannedAt — назначенная ею дата. */
  status: RouteStatus | null; plannedAt: string | null; admitted: boolean; overdue: boolean; allowed: RouteAction[]; closedReason: string | null
}

/** Колокольчик (задача 13, упрощена до внутрисистемных уведомлений): GET /journal/notifications/bell, опрашивается
 * поллингом - см. useNotificationBell. unreadConfirmations/unreadDischarges - kind различает их отметки прочтения,
 * так что пометка одного прочитанным не закрывает другое по тому же decisionId направления. */
export interface NotificationBell {
  pendingIncomingCount: number
  unreadConfirmations: SentReferralConfirmation[]
  unreadDischarges: DischargeReady[]
  /** Что сделали пациенты моей больницы (просьба о переводе, «остаюсь», «не нужно», ответы на перевод и запись приёма). */
  patientSignals?: PatientEvent[]
}

export interface PatientEvent { id: string; patientRef: string; kind: string; moCode: string | null; moName: string | null; comment: string | null; at: string }

export interface SentReferralConfirmation { decisionId: string; patientRef: string; toMoCode: string; toMoName: string; confirmedAt: string; read: boolean }

export interface DischargeReady { decisionId: string; patientRef: string; fromMoCode: string; fromMoName: string; summary: string; dischargedAt: string; read: boolean }

export type NotificationKind = 'referral-confirmed' | 'referral-discharged' | 'patient-signal'


export interface Region { regionKato: string; name: string; capital: string; lat: number | null; lon: number | null; populationThousands: number | null }
export interface OrganizationItem { moCode: string; name: string; regionKato: string; moType: string | null; sizeBucket: string | null; moKey: string | null }

/** 3.2: нагрузка = поток / госпитализации; load === null значит throughput_per_day = 0 при живом потоке (нет госпитализаций вообще). */
export interface OverloadedOrganization {
  moCode: string; name: string; regionKato: string; profileCode: string; load: number | null
  queueLen: number; queueAgeP90: number | null; refusalRate4w: number | null
}
export interface Profile { profileCode: string; name: string; isDayHospital: boolean; referrals: number }

export interface Shortage { flag: boolean; score: number; basis: string; peerRatio: number | null; peerBasis: string | null }
export interface AlternativeMnn { mnnId: string; name: string; issued12m: number }
export interface CheckResponse {
  covered: boolean; program: string | null; category: string | null; fillDaysP50: number | null; fillDaysP90: number | null
  fillDaysP50Model: number | null
  pFilled14d: number | null; shortage: Shortage; pharmacies: unknown[]; alternatives: AlternativeMnn[]; basis: string; model: ModelInfo
}
export interface Nosology { nosologyId: string; categoryId: string; issued12m: number; fulfilled12m: number; mnnCount: number }
export interface Mnn { mnnId: string; nosologyId: string; categoryId: string; issued12m: number; fulfilled12m: number; fillDaysP50: number | null }

export interface ChartSeries { name: string; data: (number | null)[] }
export interface Chart { type: 'line' | 'bar'; title: string; x: string[]; series: ChartSeries[] }
/** reachable: отвечает ли локальная модель (Ollama) и скачана ли она; null — облачный провайдер, не проверялось. */
export interface InsightStatus { available: boolean; reachable?: boolean | null; provider: string; model: string }
export interface AskResponse { answer: string; value: number | null; unit: string | null; chart: Chart | null; toolsUsed: string[]; sources: string[]; model: string }

export interface ScribeHealth { status: string; transcriber: string; drafter: string; transcriberState?: 'idle' | 'loading' | 'ready' | 'error'; transcriberError?: string | null; transcriberProgress?: { downloadedMb: number; totalMb: number | null } | null }
/** Запрос согласия пациента на запись приёма (GET /scribe-consents, GET /route/me/scribe): одно согласие — один приём в день запроса. */
export type ScribeConsentStatus = 'pending' | 'granted' | 'declined' | 'withdrawn' | 'cancelled' | 'expired' | 'recording' | 'discarded' | 'completed'
export interface ScribeConsent {
  requestId: string; patientRef: string; moCode: string | null; moName: string | null; requestedRole: string; requestedAt: string; day: string
  comment: string | null; status: ScribeConsentStatus; answeredAt: string | null; sessionId: string | null; leafletToken: string | null; approvedAt: string | null
}
/** original — текст распознавания до правки; source — кто исправил фразу (ИИ по словарю терминов или врач). */
export interface ScribeSegment { t0: number; t1: number; text: string; original?: string; source?: 'ai' | 'dictionary' | 'doctor' }
export interface ScribeVocabulary { words: string[]; builtIn: number; groups?: { name: string; language: 'ru' | 'kk'; terms: string[] }[] }
export interface ScribeSection { name: string; text: string; spans?: { t0: number; t1: number }[] }
export interface ScribeDraft { sections: ScribeSection[]; leaflet: string; model: string; patientLeaflet: { text: string } }
export interface ScribeTranscriptResponse { transcript: ScribeSegment[]; text?: string; transcriber?: string }

export interface Batch {
  batchId: string; dataset: string; status: string; rowsLoaded: number; rowsQuarantined: number
  partitions: string[]; occurredAt: string | null; receivedAt: string
}

// 4.1/4.3: консоль загрузки данных (сервис ml/src/darumen/intake/app.py, проксируется YARP под /api/v1/intake)
export interface IntakeGoldRefresh { rebuilt: { table: string; rows: number }[]; published: boolean; warning: string | null }

export interface IntakeBatchResult {
  batchId: string; dataset: string; status: string; rowsBronze: number; rowsParseRejected: number
  rowsSilver: number; rowsQuarantine: number; warnings: string[]; partitions: string[]; error: string | null
  gold?: IntakeGoldRefresh; eventId?: string; eventWarning?: string
}

export interface IntakeDraftColumn { type: string; nullable?: boolean; semantic?: string }
export interface IntakeDraft {
  dataset: string; title: string; columns: Record<string, IntakeDraftColumn>
  source_file?: string; draft_model?: string
}
export interface IntakeDraftSummary { dataset: string; title: string; columns: string[]; sourceFile: string | null }

export interface IntakeUploadResult {
  status: string; matchKind?: string; matchScore?: number; batch?: IntakeBatchResult
  dataset?: string; draft?: IntakeDraft
}

export interface IntakeApproveResult { contract: string; reprocessed: IntakeUploadResult | null }
export interface IntakeQuarantineResponse { items: Record<string, unknown>[]; total: number }

/** Гостю на главной: погода по столице региона на сегодня и завтра, бытовые советы по погоде и новости о здравоохранении. */
export interface WeatherDay { date: string; tMin: number; tMax: number; precipitationProbability: number; windMax: number; uvIndex: number; code: 'clear' | 'cloudy' | 'fog' | 'rain' | 'snow' | 'thunder' }
export interface WeatherTip { code: string; day: 0 | 1; text: string }
export interface NewsItem { title: string; url: string; publishedAt: string | null; source: string }
export interface DailyResponse {
  regionKato: string; regionName: string; capital: string; asOf: string
  weather: { available: boolean; source: string; days: WeatherDay[] }
  tips: WeatherTip[]
  news: { available: boolean; source: string; items: NewsItem[] }
}

// ── Роли, разрешения, аккаунт и администрирование (docs/rbac.md) ─────────────────────────────────────────────
export type PermissionScope = 'all' | 'own'
export interface PermissionGrant { code: string; scope: PermissionScope }
export interface OnboardingState { emailVerified: boolean; otpConfigured: boolean; profileChecked: boolean; colleaguesInvited: boolean }
/** GET /me — кто вошёл и что ему можно. iinMasked — только маской (ТЗ). */
export interface MeResponse {
  actor: string
  userId: string
  displayName: string | null
  email: string | null
  emailVerified: boolean
  roles: string[]
  permissions: PermissionGrant[]
  moCode: string | null
  moName: string | null
  regionKato: string | null
  iinMasked: string | null
  onboarding: OnboardingState
}
/** Списки администрирования: { items, total, page, size } + сводка там, где она есть. */
export interface PagedList<T> { items: T[]; total: number; page: number; size: number }

export interface ProfileResponse {
  displayName: string | null
  position: string | null
  specialty: string | null
  phone: string | null
  email: string | null
  /** в /me/profile может отсутствовать — тогда берётся из /me */
  emailVerified?: boolean
  language: 'ru' | 'kk'
  timeZone: string
  moCode: string | null
  moName: string | null
  regionKato: string | null
  iinMasked?: string | null
  via?: 'egov' | 'password' | null
  /** поля, которые меняет только администратор */
  readOnlyFields?: string[]
}
export interface ProfileUpdate { phone?: string | null; language: 'ru' | 'kk'; timeZone: string }

export interface LoginRecord { at: string; method: string; success: boolean; ip: string | null }
export interface SessionRecord { id: string; device: string | null; browser: string | null; ip: string | null; start?: string | null; lastAccess: string; current: boolean }
export interface SecurityResponse {
  passwordChangedAt: string | null
  otpConfigured: boolean
  smsAvailable: boolean
  /** резервных кодов в системе входа нет — API отдаёт null */
  recoveryCodes: string[] | null
  recentLogins: LoginRecord[]
  sessions: SessionRecord[]
}

export interface NotificationEvent { code: string; titleRu?: string; titleKk?: string; inApp: boolean; email: boolean; sms: boolean; push: boolean; locked?: boolean }
export interface NotificationSettings { events: NotificationEvent[]; quietFrom: string | null; quietTo: string | null; quietExceptRegulator: boolean; digest: 'off' | 'daily' | 'weekly' }

export interface Consent { code: string; titleRu?: string; titleKk?: string; granted: boolean; required: boolean; updatedAt: string | null }
export interface ConsentsResponse { items: Consent[] }
/** Кто обращался к моим данным — из журнала аудита. */
export interface AccessLogEntry { at: string; actor: string; role: string; method: string; path: string; status: number }

export type UserStatus = 'active' | 'invited' | 'blocked'
export interface AdminUser {
  id: string
  username: string
  displayName: string | null
  email: string | null
  roles: string[]
  moCode: string | null
  moName: string | null
  regionKato: string | null
  lastActivity: string | null
  status: UserStatus
  via: 'egov' | 'password' | null
  createdAt?: string | null
}
/** GET /admin/users/{id}: пользователь и данные карточки. */
export interface AdminUserDetail { user: AdminUser; emailVerified?: boolean; createdAt?: string | null; position?: string | null; specialty?: string | null; invitedAt?: string | null; inviteExpiresAt?: string | null }
export interface AdminUsersSummary { active: number; invited?: number; invitedStale: number; blocked: number }
export interface AdminUsersResponse extends PagedList<AdminUser> { summary?: AdminUsersSummary }
export interface AdminUserUpdate { role: string; moCode?: string | null; regionKato?: string | null }
export interface InviteRequest { email: string; displayName: string; role: string; moCode?: string | null; regionKato?: string | null }
export interface InviteResponse { userId?: string; invitationId?: string; emailSent: boolean; inviteUrl?: string | null; expiresAt?: string | null }
/** Решение по заявке организации: при одобрении создаётся приглашение администратору. */
export interface ApplicationDecision { status: ApplicationStatus; emailSent: boolean; inviteUrl: string | null; invitationId: string | null }

export type Verification = 'pending' | 'verified' | 'rejected'
export interface AdminDoctor {
  id: string
  displayName: string | null
  specialty: string | null
  moCode: string | null
  moName: string | null
  regionKato: string | null
  referrals: number | null
  matchRate: number | null
  verification: Verification
  requestedAt?: string | null
}

export interface RoleInfo { key: string; titleRu: string; titleKk: string; descriptionRu: string | null; descriptionKk: string | null; builtin: boolean; editable?: boolean }
export interface PermissionInfo { code: string; titleRu: string; titleKk: string; system?: boolean; editable?: boolean }
export interface MatrixCell { role: string; permission: string; scope: PermissionScope }
export interface RolesResponse { roles: RoleInfo[]; permissions: PermissionInfo[]; matrix: MatrixCell[]; usersByRole: Record<string, number>; identityAvailable?: boolean }
export interface RoleChange { id: string | number; at: string; actor: string; role: string; permission: string; oldScope: PermissionScope | null; newScope: PermissionScope | null; comment: string | null }
export interface RolePermissionsUpdate { changes: { permission: string; scope: PermissionScope | null }[]; comment?: string }
export interface RoleCreate { key: string; titleRu: string; titleKk: string; descriptionRu?: string; copyFrom?: string }

/** Свежесть набора данных организации: последняя загруженная партия стюарда. */
export interface DatasetFreshness { dataset: string; lastLoadedAt: string | null; status: string | null; rowsLoaded: number | null }
export interface OrgAdminRef { id: string; displayName: string | null; email: string | null; status: UserStatus | string }
export type OrgStatus = 'connected' | 'setup' | 'no_data'
export interface AdminOrg {
  moCode: string
  name: string
  regionKato: string | null
  type: string | null
  users: number | null
  status: OrgStatus
  /** число профилей коек с данными — если API его отдаёт */
  profiles?: number | null
  lastLoadAt?: string | null
  admins?: OrgAdminRef[]
  freshness?: DatasetFreshness[]
}
/** GET /admin/orgs/{moCode}: организация и её заявки на регистрацию. */
export interface AdminOrgDetailResponse { organization: AdminOrg; applications: OrgApplication[] }
export type ApplicationStatus = 'pending_email' | 'pending_review' | 'approved' | 'rejected'
export interface OrgApplication {
  id: string
  number: string
  orgName: string
  bin: string
  type: string
  regionKato: string
  moCode: string | null
  adminName: string
  email: string
  phone: string
  status: ApplicationStatus
  submittedAt: string
}

export interface OrgApplicationRequest {
  orgName: string; bin: string; type: string; regionKato: string; moCode?: string | null; adminName: string; email: string; phone: string; consent: boolean
}
export interface OrgApplicationCreated { id: string; number: string; statusToken: string; emailSent?: boolean; resendAfterSeconds?: number }
export interface CodeResent { emailSent: boolean; resendAfterSeconds: number }
export interface OrgApplicationStatus { number: string; orgName: string; email: string; status: ApplicationStatus; submittedAt: string }
export interface InviteInfo { displayName: string; email: string; orgName: string | null; moCode: string | null; role: string; roleTitleRu?: string; roleTitleKk?: string; invitedBy: string; invitedAt: string; expiresAt: string }
export interface InviteAccepted { username: string; accepted: boolean }
export interface LoginExamples {
  wait: { regionName: string; profileName: string; p50Days: number; p90Days: number; within30: number } | null
  rx: { mnn: string; covered: boolean; fillP50: number | null; fillP90: number | null } | null
}

/** Причина недоступности канала (GET /public/service-status, docs/api.md); новые причины приходят строкой как есть. */
export type ServiceReason = 'smtp_not_configured' | 'smtp_unreachable' | 'not_ready' | 'endpoint_not_provided' | (string & {})
export interface ServiceAvailability { available: boolean; reason: ServiceReason | null }
/** Какие внешние каналы сейчас работают: почта, push, SMS и вход через eGov mobile. */
export interface ServiceStatus { checkedAt: string; email: ServiceAvailability; push: ServiceAvailability; sms: ServiceAvailability; egov: ServiceAvailability }
