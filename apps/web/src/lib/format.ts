import { i18n } from '@/i18n'

/** BCP-47 тег текущего языка интерфейса: числа и даты форматируются по нему, а не по настройкам браузера. */
export function localeTag(): string {
  return i18n.global.locale.value === 'kk' ? 'kk-KZ' : 'ru-RU'
}

export function days(value: number | null | undefined, digits = 0): string {
  if (value === null || value === undefined || Number.isNaN(value)) return '—'
  return value.toFixed(digits)
}

export function pct(value: number | null | undefined, digits = 0): string {
  if (value === null || value === undefined || Number.isNaN(value)) return '—'
  return `${(value * 100).toFixed(digits)} %`
}

export function num(value: number | null | undefined, digits = 0, locale = localeTag()): string {
  if (value === null || value === undefined || Number.isNaN(value)) return '—'
  return new Intl.NumberFormat(locale, { minimumFractionDigits: digits, maximumFractionDigits: digits }).format(value)
}

export function signed(value: number, digits = 1): string {
  const sign = value > 0 ? '+' : value < 0 ? '−' : ''
  return `${sign}${Math.abs(value).toFixed(digits)}`
}

/** `YYYY-MM-DD` — как локальная дата (без сдвига часовым поясом), ISO 8601 со временем — как момент. */
function parse(iso: string): Date {
  const dateOnly = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso)
  return dateOnly ? new Date(Number(dateOnly[1]), Number(dateOnly[2]) - 1, Number(dateOnly[3])) : new Date(iso)
}

export function date(iso: string | null | undefined, locale = localeTag()): string {
  if (!iso) return '—'
  const parsed = parse(iso)
  return Number.isNaN(parsed.getTime()) ? iso : new Intl.DateTimeFormat(locale, { day: '2-digit', month: '2-digit', year: 'numeric' }).format(parsed)
}

export function dateTime(iso: string | null | undefined, locale = localeTag()): string {
  if (!iso) return '—'
  const parsed = parse(iso)
  return Number.isNaN(parsed.getTime())
    ? iso
    : new Intl.DateTimeFormat(locale, { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' }).format(parsed)
}

/** Цвет индекса доступности: 0 (красный) → 100 (зелёный); в тёмной теме светлее, чтобы читаться на тёмной карте. */
export function indexColor(value: number, dark = false): string {
  const clamped = Math.max(0, Math.min(100, value))
  const hue = (clamped / 100) * 120
  return `hsl(${hue.toFixed(0)} 55% ${dark ? 58 : 42}%)`
}

/** Риск отказа словами относительно среднего по стране (11 % направлений заканчиваются отказом), на языке интерфейса. */
export function refusalWords(p: number | null | undefined): string {
  if (p === null || p === undefined || Number.isNaN(p)) return '—'
  const key = p >= 0.165 ? 'above' : p <= 0.055 ? 'below' : 'average'
  return i18n.global.t(`format.refusal.${key}`)
}

export function severityTone(severity: string): 'danger' | 'warn' | 'info' {
  if (severity === 'critical') return 'danger'
  if (severity === 'warning') return 'warn'
  return 'info'
}
