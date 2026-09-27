import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { ApiError, api, buildUrl } from '@/api/client'
import { useAuthStore } from '@/stores/auth'

describe('api client', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
  })
  afterEach(() => {
    vi.restoreAllMocks()
  })

  it('builds urls with query and skips empty values', () => {
    const url = buildUrl('api/v1/index', { month: '2025-03', profileCode: '', horizon: 3, none: null })
    expect(url.pathname).toBe('/api/v1/index')
    expect(url.searchParams.get('month')).toBe('2025-03')
    expect(url.searchParams.has('profileCode')).toBe(false)
    expect(url.searchParams.get('horizon')).toBe('3')
  })

  it('sends the bearer token from the auth store and parses json', async () => {
    vi.spyOn(useAuthStore(), 'authHeaders').mockResolvedValue({ Authorization: 'Bearer test-token' })
    const fetchMock = vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(JSON.stringify({ ok: 1 }), { status: 200, headers: { 'Content-Type': 'application/json' } }))
    const body = await api<{ ok: number }>('/api/v1/streams')
    expect(body.ok).toBe(1)
    const headers = fetchMock.mock.calls[0]![1]!.headers as Headers
    expect(headers.get('Authorization')).toBe('Bearer test-token')
    expect(headers.get('X-Actor')).toBeNull()
    expect(headers.get('Accept-Language')).toBe('ru')
  })

  it('turns problem+json into ApiError with field errors', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      new Response(JSON.stringify({ title: 'Ошибка валидации', status: 422, errors: { profileCode: ['обязательное поле'] } }), { status: 422 }),
    )
    const error = (await api('/api/v1/queue/predict', { body: {} }).catch((e: unknown) => e)) as ApiError
    expect(error).toBeInstanceOf(ApiError)
    expect(error.status).toBe(422)
    expect(error.field('profileCode')).toBe('обязательное поле')
    expect(error.field('ProfileCode')).toBe('обязательное поле')
  })

  it('keeps the missing permissions of a 403 permission_required problem', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      new Response(JSON.stringify({ title: 'Нет доступа', status: 403, detail: 'permission_required', permissions: ['gov.map'] }), { status: 403 }),
    )
    const error = (await api('/api/v1/index').catch((e: unknown) => e)) as ApiError
    expect(error.status).toBe(403)
    expect(error.detail).toBe('permission_required')
    expect(error.permissions).toEqual(['gov.map'])
  })
})
