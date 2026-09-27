import { i18n } from '@/i18n'
import { useAuthStore } from '@/stores/auth'

export class ApiError extends Error {
  readonly status: number
  readonly title: string
  readonly detail?: string
  readonly errors?: Record<string, string[]>
  /** Коды разрешений из 403 `permission_required` (docs/rbac.md): каких разрешений не хватило. */
  readonly permissions?: string[]

  constructor(status: number, title: string, detail?: string, errors?: Record<string, string[]>, permissions?: string[]) {
    super(detail ? `${title}: ${detail}` : title)
    this.name = 'ApiError'
    this.status = status
    this.title = title
    this.detail = detail
    this.errors = errors
    this.permissions = permissions
  }

  /** Сообщение для поля формы из problem+json (422): имя без учёта регистра и префикса JSON-пути (`$.bin`, `Bin`). */
  field(name: string): string | undefined {
    if (!this.errors) return undefined
    const wanted = name.toLowerCase()
    const key = Object.keys(this.errors).find((k) => k.replace(/^\$\./, '').toLowerCase() === wanted)
    return key ? this.errors[key]?.[0] : undefined
  }
}

export type Query = Record<string, string | number | boolean | null | undefined>

export interface RequestOptions {
  method?: 'GET' | 'POST' | 'PUT' | 'DELETE'
  body?: unknown
  query?: Query
  headers?: Record<string, string>
}

export function buildUrl(path: string, query?: Query): URL {
  const base = import.meta.env.VITE_API_BASE || window.location.origin
  const url = new URL(path, base.endsWith('/') ? base : `${base}/`)
  for (const [key, value] of Object.entries(query ?? {})) {
    if (value !== null && value !== undefined && value !== '') url.searchParams.set(key, String(value))
  }
  return url
}

export async function api<T>(path: string, options: RequestOptions = {}): Promise<T> {
  const auth = useAuthStore()
  const headers = new Headers({ Accept: 'application/json', 'Accept-Language': i18n.global.locale.value, ...options.headers })
  if (options.body !== undefined) headers.set('Content-Type', 'application/json')
  for (const [key, value] of Object.entries(await auth.authHeaders())) headers.set(key, value)
  const response = await fetch(buildUrl(path.replace(/^\//, ''), options.query), {
    method: options.method ?? (options.body !== undefined ? 'POST' : 'GET'),
    headers,
    body: options.body !== undefined ? JSON.stringify(options.body) : undefined,
  })
  return handle<T>(response)
}

/** Загрузка файла (multipart) с теми же заголовками входа. */
export async function apiUpload<T>(path: string, file: Blob, filename: string): Promise<T> {
  const auth = useAuthStore()
  const form = new FormData()
  form.append('file', file, filename)
  const headers = new Headers({ Accept: 'application/json', ...(await auth.authHeaders()) })
  const response = await fetch(buildUrl(path.replace(/^\//, '')), { method: 'POST', headers, body: form })
  return handle<T>(response)
}

/** Скачивание файла с заголовками входа: fetch → blob → сохранение под именем из Content-Disposition. */
export async function apiDownload(path: string, query?: Query): Promise<void> {
  const auth = useAuthStore()
  const headers = new Headers({ 'Accept-Language': i18n.global.locale.value, ...(await auth.authHeaders()) })
  const response = await fetch(buildUrl(path.replace(/^\//, ''), query), { headers })
  if (!response.ok) {
    const body = safeJson(await response.text()) as { title?: string; detail?: string }
    throw new ApiError(response.status, body?.title ?? `HTTP ${response.status}`, body?.detail)
  }
  const name = /filename\*?=(?:UTF-8'')?"?([^";]+)/i.exec(response.headers.get('Content-Disposition') ?? '')?.[1] ?? 'report'
  const link = document.createElement('a')
  link.href = URL.createObjectURL(await response.blob())
  link.download = decodeURIComponent(name)
  link.click()
  URL.revokeObjectURL(link.href)
}

async function handle<T>(response: Response): Promise<T> {
  const text = await response.text()
  const body = text ? safeJson(text) : null
  if (!response.ok) {
    const problem = (typeof body === 'object' && body !== null ? body : {}) as { title?: string; detail?: string; errors?: Record<string, string[]>; permissions?: unknown }
    const permissions = Array.isArray(problem.permissions) ? problem.permissions.filter((p): p is string => typeof p === 'string') : undefined
    throw new ApiError(response.status, problem.title ?? (response.statusText || `HTTP ${response.status}`), problem.detail, problem.errors, permissions)
  }
  return body as T
}

function safeJson(text: string): unknown {
  try {
    return JSON.parse(text)
  } catch {
    return text
  }
}
