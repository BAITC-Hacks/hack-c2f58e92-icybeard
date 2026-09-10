import { i18n } from '@/i18n'
import { useAuthStore } from '@/stores/auth'

export class ApiError extends Error {
  readonly status: number
  readonly title: string
  readonly detail?: string
  readonly errors?: Record<string, string[]>

  constructor(status: number, title: string, detail?: string, errors?: Record<string, string[]>) {
    super(detail ? `${title}: ${detail}` : title)
    this.name = 'ApiError'
    this.status = status
    this.title = title
    this.detail = detail
    this.errors = errors
  }

  /** Сообщение для поля формы из problem+json (422). */
  field(name: string): string | undefined {
    return this.errors?.[name]?.[0]
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
  const text = await response.text()
  const body = text ? safeJson(text) : null
  if (!response.ok) {
    const problem = (typeof body === 'object' && body !== null ? body : {}) as { title?: string; detail?: string; errors?: Record<string, string[]> }
    throw new ApiError(response.status, problem.title ?? (response.statusText || `HTTP ${response.status}`), problem.detail, problem.errors)
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
