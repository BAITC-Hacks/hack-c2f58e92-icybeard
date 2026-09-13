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
}
export interface QueueSnapshot { len: number; ageP50: number | null; throughputPerDay: number }
export interface PredictResponse {
  p50Days: number; p90Days: number; pWithin30Days: number; pRefusal: number
  /** false — организация не была в обучении, риск отказа показываем словами, не процентом */
  refusalOrgInTraining?: boolean
  queue: QueueSnapshot | null; explanation: Explanation; model: ModelInfo
}
export interface Organization { moCode: string; name: string; regionKato: string }
export interface Alternative { mo: Organization; p50Days: number; p90Days: number; pRefusal: number; distanceKm: number }
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
}
/** Внешняя сезонная форма (NHS): множитель месяца при среднегодовом = 1. */
export interface Seasonality { seriesId: string; month: number; multiplier: number; title: string; source: string; sourceYear: number; windowLabel: string }

export interface IndexItem { regionKato: string; name: string; shareOver30: number; p90Days: number; indexValue: number; rank: number; n: number }
export interface IndexResponse { month: string; profileCode: string; items: IndexItem[]; months: string[]; method: string }

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
  /** Разметка сигналов людьми (журнал подтверждений): статус → число. */
  anomalyLabels?: Record<string, number>
}

export interface SimulateResponse {
  organisations: number; baseline: { meanWaitDays: number }; scenario: { meanWaitDays: number }
  deltaDays: number; ci: number[]; assumptions: string[]; model: ModelInfo
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
export interface WorklistItem {
  patientRef: string; synthetic: boolean; stage: string; expectedDate: string | null; riskFlags: string[]
  priority: number; nextAction: string; explanation: string; moCode: string; profileCode: string; regionKato: string; daysWaiting: number
}

export interface Region { regionKato: string; name: string; capital: string; lat: number | null; lon: number | null; populationThousands: number | null }
export interface OrganizationItem { moCode: string; name: string; regionKato: string; moType: string | null; sizeBucket: string | null }
export interface Profile { profileCode: string; name: string; isDayHospital: boolean; referrals: number }

export interface Shortage { flag: boolean; score: number; basis: string }
export interface AlternativeMnn { mnnId: string; name: string; issued12m: number }
export interface CheckResponse {
  covered: boolean; program: string | null; category: string | null; fillDaysP50: number | null; fillDaysP90: number | null
  pFilled14d: number | null; shortage: Shortage; pharmacies: unknown[]; alternatives: AlternativeMnn[]; basis: string; model: ModelInfo
}
export interface Nosology { nosologyId: string; categoryId: string; issued12m: number; fulfilled12m: number; mnnCount: number }
export interface Mnn { mnnId: string; nosologyId: string; categoryId: string; issued12m: number; fulfilled12m: number; fillDaysP50: number | null }

export interface ChartSeries { name: string; data: (number | null)[] }
export interface Chart { type: 'line' | 'bar'; title: string; x: string[]; series: ChartSeries[] }
export interface AskResponse { answer: string; value: number | null; unit: string | null; chart: Chart | null; toolsUsed: string[]; sources: string[]; model: string }

export interface ScribeHealth { status: string; transcriber: string; drafter: string }
export interface ScribeSection { name: string; text: string; spans?: { t0: number; t1: number }[] }
export interface ScribeDraft { sections: ScribeSection[]; leaflet: string; model: string; patientLeaflet: { text: string } }

export interface Batch {
  batchId: string; dataset: string; status: string; rowsLoaded: number; rowsQuarantined: number
  partitions: string[]; occurredAt: string | null; receivedAt: string
}
