import { api } from './client'
import type {
  AlternativesResponse, Anomaly, AskResponse, Batch, CheckResponse, Decision, DecisionCreated, DecisionRequest, ForecastResponse, IndexResponse,
  Mnn, Nosology, OrganizationItem, OrganizationSeries, Paged, PredictRequest, PredictResponse, Profile, RedistributeResponse, Region,
  SimulateResponse, Stream, WorklistItem,
} from './types'

export const queue = {
  predict: (body: PredictRequest) => api<PredictResponse>('/api/v1/queue/predict', { body }),
  alternatives: (body: PredictRequest & { limit?: number; maxDistanceKm?: number }) =>
    api<AlternativesResponse>('/api/v1/queue/alternatives', { body }),
  organization: (moCode: string, profileCode: string, days = 90) =>
    api<OrganizationSeries>(`/api/v1/queue/organizations/${encodeURIComponent(moCode)}`, { query: { profileCode, days } }),
}

export const analytics = {
  streams: () => api<{ items: Stream[] }>('/api/v1/streams'),
  forecast: (streamId: string, entity: Record<string, string>, horizon?: number) => {
    const query: Record<string, string | number | undefined> = { horizon }
    for (const [key, value] of Object.entries(entity)) query[`entity[${key}]`] = value
    return api<ForecastResponse>(`/api/v1/forecast/${encodeURIComponent(streamId)}`, { query })
  },
  anomalies: (filter: { regionKato?: string; streamId?: string; severity?: string; status?: string; page?: number; size?: number }) =>
    api<Paged<Anomaly>>('/api/v1/anomalies', { query: filter }),
  ack: (id: string, comment: string, status = 'acknowledged') =>
    api<void>(`/api/v1/anomalies/${encodeURIComponent(id)}/ack`, { body: { comment, status } }),
  index: (month?: string, profileCode?: string) => api<IndexResponse>('/api/v1/index', { query: { month, profileCode } }),
}

export const simulation = {
  simulate: (regionKato: string, profileCode: string, scenario: { capacityDeltaPct?: number; redistributeSharePct?: number; horizonDays?: number }) =>
    api<SimulateResponse>('/api/v1/simulate', { body: { regionKato, profileCode, scenario } }),
  redistribute: (regionKato: string, profileCode: string, constraints: { maxShareMovedPct?: number; maxDistanceKm?: number; horizonDays?: number }) =>
    api<RedistributeResponse>('/api/v1/redistribute', { body: { regionKato, profileCode, constraints } }),
}

export const journal = {
  record: (body: DecisionRequest, idempotencyKey: string) =>
    api<DecisionCreated>('/api/v1/journal/decisions', { body, headers: { 'Idempotency-Key': idempotencyKey } }),
  decisions: (filter: { actor?: string; subject?: string; page?: number; size?: number }) =>
    api<Paged<Decision>>('/api/v1/journal/decisions', { query: filter }),
  worklist: (filter: { regionKato?: string; flag?: string } = {}) =>
    api<{ items: WorklistItem[]; synthetic: boolean }>('/api/v1/journal/worklist', { query: filter }),
}

export const refdata = {
  regions: () => api<{ items: Region[] }>('/api/v1/refdata/regions'),
  organizations: (regionKato?: string, q?: string, profileCode?: string, limit = 200) =>
    api<{ items: OrganizationItem[] }>('/api/v1/refdata/organizations', { query: { regionKato, q, profileCode, limit } }),
  profiles: () => api<{ items: Profile[] }>('/api/v1/refdata/profiles'),
}

export const medicines = {
  check: (body: { mnnId?: string | null; nosologyId?: string | null; regionKato?: string | null }) => api<CheckResponse>('/api/v1/medicines/check', { body }),
  nosologies: (limit = 50) => api<{ items: Nosology[] }>('/api/v1/medicines/nosologies', { query: { limit } }),
  mnn: (nosologyId: string, limit = 50) => api<{ items: Mnn[] }>('/api/v1/medicines/mnn', { query: { nosologyId, limit } }),
}

export const insight = {
  ask: (question: string, regionKato?: string) => api<AskResponse>('/api/v1/insight/ask', { body: { question, regionKato } }),
  status: () => api<{ available: boolean }>('/api/v1/insight/status'),
}

export const intake = {
  batches: (filter: { status?: string; dataset?: string; page?: number; size?: number } = {}) =>
    api<Paged<Batch>>('/api/v1/intake/batches', { query: filter }),
}
