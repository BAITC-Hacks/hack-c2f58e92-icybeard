import { ApiError } from '@/api/client'

/** Текст обращения в поддержку по ошибке: код, заголовок, адрес страницы и время — без персональных данных. */
export function supportReport(error: unknown, path: string, at = new Date()): string {
  const status = error instanceof ApiError ? `HTTP ${error.status}` : 'client'
  const title = error instanceof ApiError ? [error.title, error.detail].filter(Boolean).join(' — ') : error instanceof Error ? error.message : String(error)
  return [`Darumen Health · ${status}`, title, `page: ${path}`, `at: ${at.toISOString()}`].join('\n')
}

/** Адрес поддержки стенда (VITE_SUPPORT_EMAIL); без него обращение копируется в буфер обмена. */
export function supportMailto(report: string): string | null {
  const email = import.meta.env.VITE_SUPPORT_EMAIL as string | undefined
  if (!email) return null
  return `mailto:${email}?subject=${encodeURIComponent('Darumen Health: ошибка')}&body=${encodeURIComponent(report)}`
}

/** Короткий код ошибки для подписи состояния («Код 504»); сетевые ошибки — без кода. */
export function errorCode(error: unknown): number | null {
  return error instanceof ApiError ? error.status : null
}

/** 403 от API — состояние «Нет доступа к разделу», а не ошибка загрузки. */
export function isForbidden(error: unknown): error is ApiError {
  return error instanceof ApiError && error.status === 403
}
