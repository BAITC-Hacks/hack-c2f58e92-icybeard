/**
 * Подписи сигналов аномалий для людей: название потока, уровень, статус и описание сущности.
 * Сущность сигнала приходит как словарь ключей потока (streams/*.yaml), поэтому описание
 * собирается по известным ключам, а неизвестные показываются как есть.
 */

export const STREAM_TITLES: Record<string, string> = {
  admissions_monthly: 'Госпитализации',
  er_visits_daily: 'Приёмный покой',
  vac_monthly: 'Вакцинация',
  rx_weekly: 'Обеспеченные рецепты',
  onco_monthly: 'Онкология, впервые выявленные',
  queue_daily: 'Очередь на госпитализацию',
}

const SEVERITY_LABELS: Record<string, string> = { critical: 'критический', warning: 'предупреждение' }

const STATUS_LABELS: Record<string, string> = { open: 'открыт', acknowledged: 'подтверждён', dismissed: 'ложный сигнал' }

const LOCALIZATION_LABELS: Record<string, string> = { ALL: 'все локализации', OTH: 'прочие локализации' }

export const UNKNOWN_REGION = 'unknown'

export function streamTitle(streamId: string): string {
  return STREAM_TITLES[streamId] ?? streamId
}

export function severityLabel(severity: string): string {
  return SEVERITY_LABELS[severity] ?? severity
}

export function statusLabel(status: string): string {
  return STATUS_LABELS[status] ?? status
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
  if (region) parts.push(region === UNKNOWN_REGION ? 'регион не определён' : names.region(region))
  if (entity.mo_code) parts.push(names.organization(entity.mo_code))
  else if (entity.mo_key) parts.push(organizationFromKey(entity.mo_key))
  if (entity.profile_code) parts.push(`профиль «${names.profile(entity.profile_code)}»`)
  for (const [key, value] of Object.entries(entity)) {
    switch (key) {
      case 'region_kato':
      case 'mo_code':
      case 'mo_key':
      case 'profile_code':
        break
      case 'vaccination_plan':
        parts.push(`план вакцинации ${value}`)
        break
      case 'drug_mnn_id':
        parts.push(`МНН ${value}`)
        break
      case 'localization':
        parts.push(LOCALIZATION_LABELS[value] ?? `локализация ${value}`)
        break
      default:
        parts.push(`${key}: ${value}`)
    }
  }
  return parts
}

/** Направление отклонения словами: сигнал бывает и на рост, и на провал. */
export function deviationText(observed: number, expected: number): string {
  return observed >= expected ? 'выше ожидания' : 'ниже ожидания'
}
