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
  priority: number; nextAction: string; explanation: string; moCode: string; moName: string; profileCode: string; regionKato: string; daysWaiting: number
}

/** Маршрут пациента (docs/api.md, раздел Route): один контракт для гражданина (/route/me) и врача (/route/{ref}). */
export interface RouteOrganization { moCode: string; moName: string; profileCode: string; profileName: string }
export interface RouteStage { code: string; order: number; title: string; date: string | null; status: 'done' | 'current' | 'upcoming'; norm: string | null }
export interface RouteDates { issuedAt: string; registeredAt: string; plannedAt: string | null; expectedAt: string }
export interface RouteForecast { p50Days: number; p90Days: number; pWithin30Days: number | null; fromModel: boolean; model: ModelInfo | null }
export interface RouteBenchmark { code: string; value: number; unit: string; title: string; source: string; sourceDate: string }
export interface RouteChecklistItem {
  code: string; title: string; validityDays: number; validityLabel: string; doneAt: string; validUntil: string; status: 'valid' | 'expiring' | 'expired'
}
export interface RouteDecision {
  decisionId: string; role: string; recordedAt: string; fromMoCode: string | null; toMoCode: string; toMoName: string; reason: string | null; kind: 'redirect' | 'keep'
}
export interface RouteHistoryItem {
  moCode: string; moName: string; profileCode: string; profileName: string; registeredAt: string; outcome: 'hospitalized' | 'refused'; outcomeAt: string; waitDays: number
}
/** Только для врача: гражданину API отдаёт doctor = null (риск отказа и приоритет — служебная информация). */
export interface RouteDoctorPanel {
  priority: number; riskFlags: string[]; nextAction: string; explanation: string; pRefusal: number; refusalOrgInTraining: boolean; shap: Explanation | null
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
}

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
export interface InsightStatus { available: boolean; provider: string; model: string }
export interface AskResponse { answer: string; value: number | null; unit: string | null; chart: Chart | null; toolsUsed: string[]; sources: string[]; model: string }

export interface ScribeHealth { status: string; transcriber: string; drafter: string }
export interface ScribeSegment { t0: number; t1: number; text: string }
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
