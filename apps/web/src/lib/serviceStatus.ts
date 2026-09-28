import type { ServiceAvailability, ServiceReason, ServiceStatus } from '@/api/types'

/** Статус внешних каналов — GET /api/v1/public/service-status (docs/api.md): почта, push, SMS и вход через eGov mobile.
 * Клиент запрашивает его при старте и раз в 5 минут. */
export const SERVICE_STATUS_REFRESH_MS = 5 * 60 * 1000
/** Баннер «Почтовый сервер недоступен» скрыт до конца сессии браузера: в sessionStorage — причина, при которой его скрыли
 * (сменилась причина — баннер показывается снова). */
export const EMAIL_BANNER_KEY = 'darumen.banner.email'

const SERVICES = ['email', 'push', 'sms', 'egov'] as const
/** Причины почты, у которых есть своя подпись; остальные — «почтовый сервер недоступен». */
export const EMAIL_REASONS = ['smtp_not_configured', 'smtp_unreachable'] as const

function availability(value: unknown): ServiceAvailability | null {
  if (typeof value !== 'object' || value === null) return null
  const { available, reason } = value as { available?: unknown; reason?: unknown }
  if (typeof available !== 'boolean') return null
  if (available) return { available, reason: null }
  return { available, reason: typeof reason === 'string' && reason ? (reason as ServiceReason) : null }
}

/** Ответ API проверяется на границе: битая или чужая форма — то же, что неудачный запрос (null). */
export function parseServiceStatus(body: unknown): ServiceStatus | null {
  if (typeof body !== 'object' || body === null) return null
  const record = body as Record<string, unknown>
  const [email, push, sms, egov] = SERVICES.map((name) => availability(record[name]))
  if (!email || !push || !sms || !egov) return null
  return { checkedAt: typeof record.checkedAt === 'string' ? record.checkedAt : '', email, push, sms, egov }
}

/** Ключ подписи причины почты в словаре (serviceStatus.emailReason.*). */
export function emailReasonKey(reason: string | null): string {
  return (EMAIL_REASONS as readonly string[]).includes(reason ?? '') ? reason! : 'other'
}

export function readDismissedEmailReason(): string | null {
  try {
    return window.sessionStorage.getItem(EMAIL_BANNER_KEY)
  } catch {
    return null
  }
}

export function writeDismissedEmailReason(reason: string): void {
  try {
    window.sessionStorage.setItem(EMAIL_BANNER_KEY, reason)
  } catch {
    // без sessionStorage баннер скрыт до перезагрузки страницы
  }
}
