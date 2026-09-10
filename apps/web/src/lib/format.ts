export function days(value: number | null | undefined, digits = 0): string {
  if (value === null || value === undefined || Number.isNaN(value)) return '—'
  return value.toFixed(digits)
}

export function pct(value: number | null | undefined, digits = 0): string {
  if (value === null || value === undefined || Number.isNaN(value)) return '—'
  return `${(value * 100).toFixed(digits)} %`
}

export function num(value: number | null | undefined): string {
  if (value === null || value === undefined || Number.isNaN(value)) return '—'
  return new Intl.NumberFormat('ru-RU').format(Math.round(value))
}

export function signed(value: number, digits = 1): string {
  const sign = value > 0 ? '+' : value < 0 ? '−' : ''
  return `${sign}${Math.abs(value).toFixed(digits)}`
}

/** Цвет индекса доступности: 0 (красный) → 100 (зелёный). */
export function indexColor(value: number): string {
  const clamped = Math.max(0, Math.min(100, value))
  const hue = (clamped / 100) * 120
  return `hsl(${hue.toFixed(0)} 70% 42%)`
}

export function severityTone(severity: string): 'danger' | 'warn' | 'info' {
  if (severity === 'critical') return 'danger'
  if (severity === 'warning') return 'warn'
  return 'info'
}
