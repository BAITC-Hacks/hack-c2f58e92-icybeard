/**
 * Подписи записей журнала решений. Предмет решения задаёт форму полей:
 * направление — `recommended`/`chosen` вида `{ moCode }`, subjectId `регион.организация.профиль.дата`;
 * сигнал аномалии — `{ status }`, subjectId = id сигнала.
 */
import { statusLabel } from '@/lib/anomaly'

export const SUBJECT_REFERRAL = 'referral'
export const SUBJECT_ANOMALY = 'anomaly'

const SUBJECT_LABELS: Record<string, string> = { [SUBJECT_REFERRAL]: 'направление', [SUBJECT_ANOMALY]: 'сигнал' }

const ROLE_LABELS: Record<string, string> = {
  doctor: 'врач', chief: 'главврач', regulator: 'регулятор', steward: 'стюард', admin: 'администратор', citizen: 'гражданин',
}

export interface DecisionNames {
  region: (kato: string) => string
  profile: (code: string) => string
  organization: (moCode: string) => string
}

export function subjectLabel(subject: string): string {
  return SUBJECT_LABELS[subject] ?? subject
}

export function roleLabel(role: string): string {
  return ROLE_LABELS[role] ?? role
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
  if (subject === SUBJECT_ANOMALY) return `сигнал ${subjectId.slice(0, 8)}`
  return subjectId
}
