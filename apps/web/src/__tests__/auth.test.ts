import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { useAuthStore } from '@/stores/auth'

/** Node 25 отдаёт неработающий localStorage; тесту нужна память в духе Storage. */
function memoryStorage(): Storage {
  const data = new Map<string, string>()
  return {
    get length() { return data.size },
    clear: () => data.clear(),
    getItem: (key: string) => data.get(key) ?? null,
    key: (index: number) => [...data.keys()][index] ?? null,
    removeItem: (key: string) => { data.delete(key) },
    setItem: (key: string, value: string) => { data.set(key, value) },
  }
}

describe('auth store in headers mode', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    vi.stubGlobal('localStorage', memoryStorage())
  })

  it('switches demo roles, admin passes every check', () => {
    const auth = useAuthStore()
    expect(auth.isAuthenticated).toBe(false)
    auth.setDemoRole('chief')
    expect(auth.hasRole('chief', 'regulator')).toBe(true)
    expect(auth.hasRole('doctor')).toBe(false)
    expect(auth.region).toBe('75')
    auth.setDemoRole('admin')
    expect(auth.hasRole('doctor')).toBe(true)
    auth.setDemoRole(null)
    expect(auth.actor).toBeNull()
  })

  it('restores the saved role on init', async () => {
    localStorage.setItem('darumen.role', 'steward')
    const auth = useAuthStore()
    await auth.init()
    expect(auth.role).toBe('steward')
    expect(await auth.authHeaders()).toEqual({ 'X-Actor': 'steward1', 'X-Role': 'steward' })
  })
})
