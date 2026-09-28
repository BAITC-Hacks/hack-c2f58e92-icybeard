import { flushPromises } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { EMAIL_BANNER_KEY, emailReasonKey, parseServiceStatus, SERVICE_STATUS_REFRESH_MS } from '@/lib/serviceStatus'
import { useServiceStatusStore } from '@/stores/serviceStatus'
import { jsonResponse, memoryStorage, statusBody, UP } from './serviceFixtures'

function useSession(storage: Storage = memoryStorage()) {
  Object.defineProperty(window, 'sessionStorage', { value: storage, configurable: true })
  return storage
}

describe('parseServiceStatus', () => {
  it('accepts the API contract and normalises reasons', () => {
    expect(parseServiceStatus(statusBody())).toEqual(statusBody())
    const parsed = parseServiceStatus({ ...statusBody(), email: { available: true, reason: 'smtp_unreachable' } })
    expect(parsed?.email).toEqual({ available: true, reason: null })
  })

  it('treats a foreign or broken body as no answer', () => {
    expect(parseServiceStatus(null)).toBeNull()
    expect(parseServiceStatus('down')).toBeNull()
    expect(parseServiceStatus({ ...statusBody(), egov: undefined })).toBeNull()
    expect(parseServiceStatus({ ...statusBody(), sms: { available: 'no' } })).toBeNull()
  })

  it('maps unknown email reasons to the generic label', () => {
    expect(emailReasonKey('smtp_not_configured')).toBe('smtp_not_configured')
    expect(emailReasonKey('smtp_unreachable')).toBe('smtp_unreachable')
    expect(emailReasonKey('tls_failed')).toBe('other')
    expect(emailReasonKey(null)).toBe('other')
  })
})

describe('service status store', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    useSession()
  })
  afterEach(() => {
    vi.restoreAllMocks()
    vi.useRealTimers()
  })

  it('asks the public endpoint on start and every 5 minutes until stopped', async () => {
    vi.useFakeTimers({ toFake: ['setInterval', 'clearInterval'] })
    const fetchMock = vi.spyOn(globalThis, 'fetch').mockImplementation(async () => jsonResponse(statusBody()))
    const store = useServiceStatusStore()

    store.start()
    store.start() // повторный старт не заводит второй опрос
    await flushPromises()
    expect(fetchMock).toHaveBeenCalledTimes(1)
    expect(new URL(String(fetchMock.mock.calls[0]![0])).pathname).toBe('/api/v1/public/service-status')
    expect(store.emailUnavailable).toBe(true)

    vi.advanceTimersByTime(SERVICE_STATUS_REFRESH_MS)
    await flushPromises()
    expect(fetchMock).toHaveBeenCalledTimes(2)

    store.stop()
    vi.advanceTimersByTime(3 * SERVICE_STATUS_REFRESH_MS)
    await flushPromises()
    expect(fetchMock).toHaveBeenCalledTimes(2)
  })

  it('reports each channel from the answer', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(jsonResponse(statusBody({ email: UP, egov: UP })))
    const store = useServiceStatusStore()
    await store.refresh()

    expect(store.emailUnavailable).toBe(false)
    expect(store.emailBannerVisible).toBe(false)
    expect(store.egovAvailable).toBe(true)
    expect(store.pushAvailable).toBe(false)
    expect(store.smsAvailable).toBe(false)
    expect(store.channelOff('inApp')).toBeNull()
    expect(store.channelOff('email')).toBeNull()
    expect(store.channelOff('sms')).toBe('not_ready')
    expect(store.channelOff('push')).toBe('not_ready')
  })

  it.each([
    ['network error', () => Promise.reject(new TypeError('Failed to fetch'))],
    ['server error', async () => jsonResponse({ title: 'Ошибка' }, 500)],
    ['foreign body', async () => jsonResponse({ email: 'down' })],
  ])('after a %s: email is unknown (no banner), push, SMS and eGov are unavailable', async (_, answer) => {
    vi.spyOn(console, 'warn').mockImplementation(() => {})
    const fetchMock = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(jsonResponse(statusBody({ push: UP, sms: UP, egov: UP })))
    const store = useServiceStatusStore()
    await store.refresh()
    expect(store.egovAvailable).toBe(true)

    fetchMock.mockImplementation(answer as () => Promise<Response>)
    await store.refresh()
    expect(store.status).toBeNull()
    expect(store.emailUnavailable).toBe(false)
    expect(store.emailBannerVisible).toBe(false)
    expect(store.channelOff('email')).toBeNull()
    expect(store.egovAvailable).toBe(false)
    expect(store.pushAvailable).toBe(false)
    expect(store.channelOff('sms')).toBe('not_ready')
    expect(store.channelOff('push')).toBe('not_ready')
  })

  it('shares one request between concurrent refreshes', async () => {
    const fetchMock = vi.spyOn(globalThis, 'fetch').mockImplementation(async () => jsonResponse(statusBody()))
    const store = useServiceStatusStore()
    await Promise.all([store.refresh(), store.refresh(), store.refresh()])
    expect(fetchMock).toHaveBeenCalledTimes(1)
  })

  it('hides the email banner for the rest of the browser session and shows it again in a new one', async () => {
    const session = useSession()
    vi.spyOn(globalThis, 'fetch').mockImplementation(async () => jsonResponse(statusBody()))
    const store = useServiceStatusStore()
    await store.refresh()
    expect(store.emailBannerVisible).toBe(true)

    store.dismissEmailBanner()
    expect(store.emailBannerVisible).toBe(false)
    expect(session.getItem(EMAIL_BANNER_KEY)).toBe('smtp_not_configured')

    // перезагрузка страницы в той же сессии: баннер остаётся скрытым
    setActivePinia(createPinia())
    const reloaded = useServiceStatusStore()
    await reloaded.refresh()
    expect(reloaded.emailBannerVisible).toBe(false)

    // другая причина — баннер снова виден
    vi.spyOn(globalThis, 'fetch').mockImplementation(async () => jsonResponse(statusBody({ email: { available: false, reason: 'smtp_unreachable' } })))
    await reloaded.refresh()
    expect(reloaded.emailBannerVisible).toBe(true)

    // новая сессия браузера (пустой sessionStorage)
    useSession()
    setActivePinia(createPinia())
    const next = useServiceStatusStore()
    await next.refresh()
    expect(next.emailBannerVisible).toBe(true)
  })

  it('still dismisses when sessionStorage is blocked', async () => {
    const blocked = {} as Storage
    Object.defineProperty(blocked, 'getItem', { value: () => { throw new DOMException('blocked', 'SecurityError') } })
    Object.defineProperty(blocked, 'setItem', { value: () => { throw new DOMException('blocked', 'SecurityError') } })
    useSession(blocked)
    vi.spyOn(globalThis, 'fetch').mockImplementation(async () => jsonResponse(statusBody()))
    const store = useServiceStatusStore()
    await store.refresh()
    expect(() => store.dismissEmailBanner()).not.toThrow()
    expect(store.emailBannerVisible).toBe(false)
  })
})
