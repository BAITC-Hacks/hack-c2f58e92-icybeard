/**
 * Подписи сигналов аномалий для людей: название потока, уровень, статус и описание сущности.
 * Сущность сигнала приходит как словарь ключей потока (streams/*.yaml), поэтому описание
 * собирается по известным ключам, а неизвестные показываются как есть.
 */

import { i18n } from '@/i18n'

const t = i18n.global.t

const STREAM_IDS = ['admissions_monthly', 'er_visits_daily', 'vac_monthly', 'rx_weekly', 'onco_monthly', 'queue_daily']
const SEVERITY_IDS = ['critical', 'warning']
const STATUS_IDS = ['open', 'acknowledged', 'dismissed']
const LOCALIZATION_IDS = ['ALL', 'OTH']

export const UNKNOWN_REGION = 'unknown'

export function streamTitle(streamId: string): string {
  return STREAM_IDS.includes(streamId) ? t(`anomaly.stream.${streamId}`) : streamId
}

export function severityLabel(severity: string): string {
  return SEVERITY_IDS.includes(severity) ? t(`anomaly.severity.${severity}`) : severity
}

export function statusLabel(status: string): string {
  return STATUS_IDS.includes(status) ? t(`anomaly.status.${status}`) : status
}

function localizationLabel(value: string): string {
  return LOCALIZATION_IDS.includes(value) ? t(`anomaly.localization.${value}`) : t('anomaly.localizationOther', { value })
}

/** Справочники, через которые коды превращаются в названия. */
export interface EntityNames {
  region: (kato: string) => string
  profile: (code: string) => string
  organization: (moCode: string) => string
}

/** Ключ организации в потоках по названию (mo_key) — нормализованное имя в нижнем регистре. */
function organizationFromKey(key: string): string {
  return key.charAt(0).toUpperCase() + key.slice(1)
}

/**
 * Части описания сигнала: регион, организация, профиль, остальные ключи.
 * Регион берётся из сущности, а если его там нет — из поля сигнала.
 */
export function describeEntity(entity: Record<string, string>, regionKato: string | null, names: EntityNames): string[] {
  const parts: string[] = []
  const region = entity.region_kato ?? regionKato
  if (region) parts.push(region === UNKNOWN_REGION ? t('anomaly.regionUnknown') : names.region(region))
  if (entity.mo_code) parts.push(names.organization(entity.mo_code))
  else if (entity.mo_key) parts.push(organizationFromKey(entity.mo_key))
  if (entity.profile_code) parts.push(t('anomaly.profileLabel', { profile: names.profile(entity.profile_code) }))
  for (const [key, value] of Object.entries(entity)) {
    switch (key) {
      case 'region_kato':
      case 'mo_code':
      case 'mo_key':
      case 'profile_code':
        break
      case 'vaccination_plan':
        parts.push(t('anomaly.vaccinationPlan', { value }))
        break
      case 'drug_mnn_id':
        parts.push(t('anomaly.drugMnn', { value }))
        break
      case 'localization':
        parts.push(localizationLabel(value))
        break
      default:
        parts.push(`${key}: ${value}`)
    }
  }
  return parts
}

/** Направление отклонения словами: сигнал бывает и на рост, и на провал. */
export function deviationText(observed: number, expected: number): string {
  return observed >= expected ? t('anomaly.aboveExpected') : t('anomaly.belowExpected')
}

/** Период сигнала для людей: «2025-04-03» → «03.04.2025», «2025-03» → «март 2025». */
export function periodText(period: string): string {
  const day = /^(\d{4})-(\d{2})-(\d{2})/.exec(period)
  if (day) return `${day[3]}.${day[2]}.${day[1]}`
  const month = /^(\d{4})-(\d{2})$/.exec(period)
  if (month) return new Date(Number(month[1]), Number(month[2]) - 1, 1).toLocaleDateString((i18n.global.locale as unknown as { value: string }).value === 'kk' ? 'kk-KZ' : 'ru-RU', { month: 'long', year: 'numeric' })
  return period
}

/** Сигнал одной фразой: «03.04.2025: 0 пациентов в очереди, обычно около 332 — меньше обычного». */
export function anomalySentence(a: { streamId: string; period: string; observed: number; expected: number }, fmt: (n: number) => string): string {
  const unit = STREAM_IDS.includes(a.streamId) ? t(`anomaly.unit.${a.streamId}`) : ''
  return t('anomalyFeed.sentence', { date: periodText(a.period), observed: fmt(a.observed), unit, expected: fmt(a.expected), deviation: deviationText(a.observed, a.expected) })
}
