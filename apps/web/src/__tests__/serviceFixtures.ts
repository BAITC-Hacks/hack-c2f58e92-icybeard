import type { Pinia } from 'pinia'
import PrimeVue from 'primevue/config'
import ToastService from 'primevue/toastservice'
import type { Plugin } from 'vue'
import type { ServiceAvailability, ServiceStatus } from '@/api/types'
import { i18n } from '@/i18n'

/** В jsdom под Node 25 глобальные localStorage/sessionStorage — нодовские заглушки без clear(): подставляем свои. */
export function memoryStorage(): Storage {
  const map = new Map<string, string>()
  return {
    get length() { return map.size },
    clear: () => map.clear(),
    getItem: (key: string) => map.get(key) ?? null,
    key: (index: number) => [...map.keys()][index] ?? null,
    removeItem: (key: string) => { map.delete(key) },
    setItem: (key: string, value: string) => { map.set(key, String(value)) },
  } as Storage
}

type Channel = 'email' | 'push' | 'sms' | 'egov'

/** Ответ GET /public/service-status как на стенде 28.09.2026: почта не настроена, push и SMS не подключены, eGov без адреса. */
export function statusBody(overrides: Partial<Record<Channel, ServiceAvailability>> = {}): ServiceStatus {
  return {
    checkedAt: '2026-09-28T10:15:00Z',
    email: { available: false, reason: 'smtp_not_configured' },
    push: { available: false, reason: 'not_ready' },
    sms: { available: false, reason: 'not_ready' },
    egov: { available: false, reason: 'endpoint_not_provided' },
    ...overrides,
  }
}

export const UP: ServiceAvailability = { available: true, reason: null }

export function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })
}

/** Плагины для mount: pinia теста, PrimeVue без темы, тосты и словари. */
export function plugins(pinia: Pinia): (Plugin | [Plugin, ...unknown[]])[] {
  return [pinia, [PrimeVue, { theme: 'none' }], ToastService, i18n]
}
