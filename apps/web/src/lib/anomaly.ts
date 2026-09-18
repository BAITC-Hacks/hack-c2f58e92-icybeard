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
