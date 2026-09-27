import { api, apiDownload, apiUpload } from './client'
import type {
  AlternativesResponse, Anomaly, AskResponse, AuditEntry, Batch, InsightStatus, CheckResponse, Decision, DecisionCreated, DecisionRequest, EquipmentOrganization, EquipmentResponse, ForecastResponse, IndexResponse,
  IntakeApproveResult, IntakeDraft, IntakeDraftSummary, IntakeQuarantineResponse, IntakeUploadResult,
  DailyResponse, LosResponse, Mnn, Nosology, OrganizationItem, OrganizationSeries, OverloadedOrganization, Paged, PatientRoute, PredictRequest, QualityReport, RouteStandard, ScribeDraft, ScribeHealth, ScribeTranscriptResponse, PredictResponse, Profile, RedistributeResponse, Region, Seasonality,
  SimulateResponse, StaffingResponse, Stream, VaccinationBenchmark, VaccinationRefusalsResponse, OncologyLateStageResponse, WorklistResponse, SignalKind,
  AccessLogEntry, AdminDoctor, ApplicationDecision, CodeResent, InviteAccepted, AdminOrg, AdminOrgDetailResponse, AdminUserDetail, AdminUsersResponse, AdminUserUpdate, ApplicationStatus, ConsentsResponse, InviteInfo,
  InviteRequest, InviteResponse, LoginExamples, MeResponse, NotificationSettings, OrgApplication, OrgApplicationCreated, OrgApplicationRequest,
  OrgApplicationStatus, PagedList, ProfileResponse, ProfileUpdate, RoleChange, RoleCreate, RolePermissionsUpdate, RolesResponse, SecurityResponse, Verification,
} from './types'

export const queue = {
  predict: (body: PredictRequest) => api<PredictResponse>('/api/v1/queue/predict', { body }),
  alternatives: (body: PredictRequest & { limit?: number; maxDistanceKm?: number; includeNeighbors?: boolean }) =>
    api<AlternativesResponse>('/api/v1/queue/alternatives', { body }),
  organization: (moCode: string, profileCode: string, days = 90) =>
    api<OrganizationSeries>(`/api/v1/queue/organizations/${encodeURIComponent(moCode)}`, { query: { profileCode, days } }),
  overloaded: (regionKato?: string, profileCode?: string, limit = 20) =>
    api<{ items: OverloadedOrganization[] }>('/api/v1/queue/overloaded', { query: { regionKato, profileCode, limit } }),
}

export const analytics = {
  streams: () => api<{ items: Stream[] }>('/api/v1/streams'),
  forecast: (streamId: string, entity: Record<string, string>, horizon?: number) => {
    const query: Record<string, string | number | undefined> = { horizon }
    for (const [key, value] of Object.entries(entity)) query[`entity[${key}]`] = value
    return api<ForecastResponse>(`/api/v1/forecast/${encodeURIComponent(streamId)}`, { query })
  },
  anomalies: (filter: { regionKato?: string; streamId?: string; severity?: string; status?: string; moCode?: string; page?: number; size?: number }) =>
    api<Paged<Anomaly>>('/api/v1/anomalies', { query: filter }),
  ack: (id: string, comment: string, status = 'acknowledged') =>
    api<void>(`/api/v1/anomalies/${encodeURIComponent(id)}/ack`, { body: { comment, status } }),
  index: (month?: string, profileCode?: string) => api<IndexResponse>('/api/v1/index', { query: { month, profileCode } }),
  quality: () => api<QualityReport>('/api/v1/quality'),
  los: (regionKato?: string, profileCode?: string) => api<LosResponse>('/api/v1/los', { query: { regionKato, profileCode } }),
  staffing: () => api<StaffingResponse>('/api/v1/staffing'),
  vaccinationRefusals: () => api<VaccinationRefusalsResponse>('/api/v1/vaccination-refusals'),
  oncologyLateStage: () => api<OncologyLateStageResponse>('/api/v1/oncology-late-stage'),
  equipment: () => api<EquipmentResponse>('/api/v1/equipment'),
  equipmentForOrganization: (moCode: string) => api<EquipmentOrganization>(`/api/v1/equipment/organizations/${encodeURIComponent(moCode)}`),
}

export const simulation = {
  simulate: (regionKato: string, profileCode: string, scenario: { capacityDeltaPct?: number; redistributeSharePct?: number; horizonDays?: number; bedsDelta?: number }) =>
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
    api<WorklistResponse>('/api/v1/journal/worklist', { query: filter }),
  audit: (filter: { actor?: string; page?: number; size?: number } = {}) =>
    api<Paged<AuditEntry>>('/api/v1/journal/audit', { query: filter }),
}

/** Маршрут пациента: гражданин — свой (/route/me), врач — любой из рабочего списка своего региона, с перенаправлением. */
export const route = {
  me: (regionKato?: string) => api<PatientRoute>('/api/v1/route/me', { query: { regionKato } }),
  patient: (patientRef: string) => api<PatientRoute>(`/api/v1/route/${encodeURIComponent(patientRef)}`),
  redirect: (patientRef: string, body: { toMoCode: string; reason: string }, idempotencyKey: string) =>
    api<DecisionCreated>(`/api/v1/route/${encodeURIComponent(patientRef)}/redirect`, { body, headers: { 'Idempotency-Key': idempotencyKey } }),
  /** «Оставить в текущей организации» с причиной — ответ врача на сигнал гражданина (Kind = keep). */
  keep: (patientRef: string, body: { reason: string }, idempotencyKey: string) =>
    api<DecisionCreated>(`/api/v1/route/${encodeURIComponent(patientRef)}/keep`, { body, headers: { 'Idempotency-Key': idempotencyKey } }),
  /** Сигнал гражданина: still_waiting | treated_elsewhere | withdraw | request_redirect (с toMoCode). */
  signal: (body: { kind: SignalKind; toMoCode?: string; comment?: string }, idempotencyKey: string) =>
    api<DecisionCreated>('/api/v1/route/me/signals', { body, headers: { 'Idempotency-Key': idempotencyKey } }),
}

export const refdata = {
  regions: () => api<{ items: Region[] }>('/api/v1/refdata/regions'),
  seasonality: () => api<{ items: Seasonality[] }>('/api/v1/refdata/seasonality'),
  vaccination: () => api<{ items: VaccinationBenchmark[] }>('/api/v1/refdata/vaccination'),
  organizations: (regionKato?: string, q?: string, profileCode?: string, limit = 200) =>
    api<{ items: OrganizationItem[] }>('/api/v1/refdata/organizations', { query: { regionKato, q, profileCode, limit } }),
  profiles: () => api<{ items: Profile[] }>('/api/v1/refdata/profiles'),
  vaccinationPlans: (regionKato?: string) => api<{ items: string[] }>('/api/v1/refdata/vaccination-plans', { query: { regionKato } }),
  routeStandard: () => api<RouteStandard>('/api/v1/refdata/route-standard'),
}

export const medicines = {
  check: (body: { mnnId?: string | null; nosologyId?: string | null; regionKato?: string | null }) => api<CheckResponse>('/api/v1/medicines/check', { body }),
  nosologies: (limit = 50) => api<{ items: Nosology[] }>('/api/v1/medicines/nosologies', { query: { limit } }),
  mnn: (nosologyId: string, limit = 50) => api<{ items: Mnn[] }>('/api/v1/medicines/mnn', { query: { nosologyId, limit } }),
  topMnn: (limit = 50) => api<{ items: Mnn[] }>('/api/v1/medicines/mnn/top', { query: { limit } }),
}

export const insight = {
  ask: (question: string, regionKato?: string) => api<AskResponse>('/api/v1/insight/ask', { body: { question, regionKato } }),
  status: () => api<InsightStatus>('/api/v1/insight/status'),
  report: (format: 'pdf' | 'xlsx', month?: string, profileCode?: string) =>
    apiDownload('/api/v1/insight/reports', { format, month, profileCode }),
}

export const scribe = {
  health: () => api<ScribeHealth>('/api/v1/scribe/health'),
  createSession: (consent: boolean, language: string) => api<{ sessionId: string }>('/api/v1/scribe/sessions', { body: { consent, language } }),
  uploadAudio: (sessionId: string, file: Blob, filename: string) =>
    apiUpload<ScribeTranscriptResponse>(`/api/v1/scribe/sessions/${sessionId}/audio`, file, filename),
  setTranscript: (sessionId: string, text: string) =>
    api<ScribeTranscriptResponse>(`/api/v1/scribe/sessions/${sessionId}/transcript`, { body: { text } }),
  draft: (sessionId: string) => api<ScribeDraft>(`/api/v1/scribe/sessions/${sessionId}/draft`, { method: 'POST', body: {} }),
  approve: (sessionId: string, sections: { name: string; text: string }[], patientLeaflet: string) =>
    api<{ leafletToken: string }>(`/api/v1/scribe/sessions/${sessionId}/approve`, { body: { sections, patientLeaflet } }),
  leaflet: (token: string) => api<{ text: string; language: string; approvedAt: string }>(`/api/v1/scribe/leaflets/${encodeURIComponent(token)}`),
}

export const intake = {
  batches: (filter: { status?: string; dataset?: string; page?: number; size?: number } = {}) =>
    api<Paged<Batch>>('/api/v1/intake/batches', { query: filter }),
  upload: (file: Blob, filename: string) => apiUpload<IntakeUploadResult>('/api/v1/intake/files', file, filename),
  drafts: () => api<{ items: IntakeDraftSummary[] }>('/api/v1/intake/drafts'),
  draft: (dataset: string) => api<IntakeDraft>(`/api/v1/intake/drafts/${encodeURIComponent(dataset)}`),
  approveDraft: (dataset: string, body: { dataset?: string; title?: string; columnSemantics?: Record<string, string> } = {}) =>
    api<IntakeApproveResult>(`/api/v1/intake/drafts/${encodeURIComponent(dataset)}/approve`, { body }),
  quarantine: (dataset: string, batchId?: string) =>
    api<IntakeQuarantineResponse>('/api/v1/intake/quarantine', { query: { dataset, batchId } }),
}

export const pub = {
  daily: (regionKato?: string) => api<DailyResponse>('/api/v1/public/daily', { query: { regionKato } }),
  /** Пример-карточки страницы входа (анонимно, кэш 1 ч). */
  loginExamples: () => api<LoginExamples>('/api/v1/public/login-examples'),
  /** Заявка на регистрацию организации: код подтверждения уходит на почту, statusToken — ключ к статусу без входа. */
  apply: (body: OrgApplicationRequest) => api<OrgApplicationCreated>('/api/v1/public/org-applications', { body }),
  application: (id: string, statusToken: string) =>
    api<OrgApplicationStatus>(`/api/v1/public/org-applications/${encodeURIComponent(id)}`, { query: { statusToken } }),
  verifyEmail: (id: string, code: string, statusToken: string) =>
    api<void>(`/api/v1/public/org-applications/${encodeURIComponent(id)}/verify-email`, { body: { code, statusToken } }),
  resendCode: (id: string, statusToken: string) =>
    api<CodeResent>(`/api/v1/public/org-applications/${encodeURIComponent(id)}/resend-code`, { body: { statusToken } }),
  invite: (token: string) => api<InviteInfo>(`/api/v1/public/invites/${encodeURIComponent(token)}`),
  acceptInvite: (token: string, password: string) =>
    api<InviteAccepted>(`/api/v1/public/invites/${encodeURIComponent(token)}/accept`, { body: { password, acceptedRules: true } }),
  declineInvite: (token: string) => api<void>(`/api/v1/public/invites/${encodeURIComponent(token)}/decline`, { method: 'POST', body: {} }),
}

/** Я и мой аккаунт: любой вошедший. */
export const account = {
  me: () => api<MeResponse>('/api/v1/me'),
  requestAccess: (body: { permission: string; path: string; comment?: string }) => api<void>('/api/v1/me/access-requests', { body }),
  profile: () => api<ProfileResponse>('/api/v1/me/profile'),
  saveProfile: (body: ProfileUpdate) => api<ProfileResponse>('/api/v1/me/profile', { method: 'PUT', body }),
  security: () => api<SecurityResponse>('/api/v1/me/security'),
  endSession: (id: string) => api<void>(`/api/v1/me/sessions/${encodeURIComponent(id)}`, { method: 'DELETE' }),
  endOtherSessions: () => api<void>('/api/v1/me/sessions', { method: 'DELETE', query: { keepCurrent: true } }),
  notifications: () => api<NotificationSettings>('/api/v1/me/notifications'),
  saveNotifications: (body: NotificationSettings) => api<NotificationSettings>('/api/v1/me/notifications', { method: 'PUT', body }),
  consents: () => api<ConsentsResponse>('/api/v1/me/consents'),
  setConsent: (code: string, granted: boolean) => api<void>(`/api/v1/me/consents/${encodeURIComponent(code)}`, { method: 'PUT', body: { granted } }),
  accessLog: () => api<{ items: AccessLogEntry[] }>('/api/v1/me/access-log'),
  exportCsv: () => apiDownload('/api/v1/me/export'),
  requestDeletion: () => api<void>('/api/v1/me/deletion-request', { method: 'POST', body: {} }),
}

export interface UserFilter { role?: string; moCode?: string; status?: string; q?: string; page?: number; size?: number }
export interface DoctorFilter { regionKato?: string; moCode?: string; specialty?: string; verification?: string; page?: number; size?: number }
export interface OrgFilter { regionKato?: string; type?: string; status?: string; page?: number; size?: number }

/** Администрирование: пользователи и врачи — admin.users (own — своя организация), роли — admin.roles, организации — admin.orgs. */
export const admin = {
  users: (filter: UserFilter) => api<AdminUsersResponse>('/api/v1/admin/users', { query: { ...filter } }),
  user: (id: string) => api<AdminUserDetail>(`/api/v1/admin/users/${encodeURIComponent(id)}`),
  updateUser: (id: string, body: AdminUserUpdate) => api<unknown>(`/api/v1/admin/users/${encodeURIComponent(id)}`, { method: 'PUT', body }),
  block: (id: string) => api<void>(`/api/v1/admin/users/${encodeURIComponent(id)}/block`, { method: 'POST', body: {} }),
  unblock: (id: string) => api<void>(`/api/v1/admin/users/${encodeURIComponent(id)}/unblock`, { method: 'POST', body: {} }),
  invite: (body: InviteRequest) => api<InviteResponse>('/api/v1/admin/users/invite', { body }),
  doctors: (filter: DoctorFilter) => api<PagedList<AdminDoctor>>('/api/v1/admin/doctors', { query: { ...filter } }),
  verifyDoctor: (id: string, status: Verification, comment?: string) =>
    api<void>(`/api/v1/admin/doctors/${encodeURIComponent(id)}/verification`, { body: { status, comment } }),
  roles: () => api<RolesResponse>('/api/v1/admin/roles'),
  saveRole: (key: string, body: RolePermissionsUpdate) => api<void>(`/api/v1/admin/roles/${encodeURIComponent(key)}/permissions`, { method: 'PUT', body }),
  createRole: (body: RoleCreate) => api<void>('/api/v1/admin/roles', { body }),
  roleHistory: (role?: string) => api<{ items: RoleChange[] }>('/api/v1/admin/roles/history', { query: { role } }),
  orgs: (filter: OrgFilter) => api<PagedList<AdminOrg>>('/api/v1/admin/orgs', { query: { ...filter } }),
  org: (moCode: string) => api<AdminOrgDetailResponse>(`/api/v1/admin/orgs/${encodeURIComponent(moCode)}`),
  applications: (status?: ApplicationStatus) => api<{ items: OrgApplication[] }>('/api/v1/admin/org-applications', { query: { status } }),
  approveApplication: (id: string) => api<ApplicationDecision>(`/api/v1/admin/org-applications/${encodeURIComponent(id)}/approve`, { method: 'POST', body: {} }),
  rejectApplication: (id: string, reason: string) => api<void>(`/api/v1/admin/org-applications/${encodeURIComponent(id)}/reject`, { body: { reason } }),
}
