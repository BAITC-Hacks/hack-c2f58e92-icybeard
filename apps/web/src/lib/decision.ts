/**
 * Подписи записей журнала решений. Предмет решения задаёт форму полей:
 * направление — `recommended`/`chosen` вида `{ moCode }`, subjectId `регион.организация.профиль.дата`;
 * сигнал аномалии — `{ status }`, subjectId = id сигнала.
 */
import { i18n } from '@/i18n'
import { statusLabel } from '@/lib/anomaly'

const t = i18n.global.t

export const SUBJECT_REFERRAL = 'referral'
export const SUBJECT_ANOMALY = 'anomaly'
/** Решения по маршруту пациента (redirect / keep) пишутся с предметом route. */
export const SUBJECT_ROUTE = 'route'

const ROLE_IDS = ['doctor', 'chief', 'org_admin', 'regulator', 'steward', 'auditor', 'admin', 'citizen']

export interface DecisionNames {
  region: (kato: string) => string
  profile: (code: string) => string
  organization: (moCode: string) => string
}

export function subjectLabel(subject: string): string {
  if (subject === SUBJECT_REFERRAL) return t('decision.subjectReferral')
  if (subject === SUBJECT_ANOMALY) return t('decision.subjectAnomaly')
  if (subject === SUBJECT_ROUTE) return t('decision.subjectRoute')
  return subject
}

export function roleLabel(role: string): string {
  return ROLE_IDS.includes(role) ? t(`decision.role.${role}`) : role
}

/** Идентификатор направления, из которого строится subjectId (см. ReferralView). */
export function referralSubjectId(regionKato: string, moCode: string, profileCode: string, registrationDate: string): string {
  return [regionKato, moCode, profileCode, registrationDate].join('.')
}

function field(value: unknown, key: string): string | null {
  if (value === null || typeof value !== 'object') return null
  const found = (value as Record<string, unknown>)[key]
  return typeof found === 'string' && found ? found : null
}

/** Код организации из `recommended`/`chosen`, если решение про организацию. */
export function organizationOf(value: unknown): string | null {
  return field(value, 'moCode')
}

/** Рекомендация или выбор человека словами. */
export function describeChoice(value: unknown, names: DecisionNames): string {
  if (value === null || value === undefined) return '—'
  const moCode = organizationOf(value)
  if (moCode) return `${names.organization(moCode)} (${moCode})`
  const status = field(value, 'status')
  if (status) return statusLabel(status)
  return typeof value === 'string' ? value : JSON.stringify(value)
}

/** Объект решения словами: для направления регион, профиль и дата; для сигнала короткий id. */
export function describeSubject(subject: string, subjectId: string, names: DecisionNames): string {
  if (subject === SUBJECT_REFERRAL) {
    const [region, , profile, date] = subjectId.split('.')
    if (region && profile && date) return `${names.region(region)} · ${names.profile(profile)} · ${date}`
  }
  if (subject === SUBJECT_ANOMALY) return t('decision.anomalyShort', { id: subjectId.slice(0, 8) })
  return subjectId
}
