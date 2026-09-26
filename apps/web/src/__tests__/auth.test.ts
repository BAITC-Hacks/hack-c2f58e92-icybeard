import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { useAuthStore } from '@/stores/auth'

/** Состояние заглушки keycloak-js: что вернёт init и какие клеймы окажутся в токене. */
const kc = vi.hoisted(() => ({
  authenticated: false,
  fail: false,
  token: undefined as string | undefined,
  tokenParsed: undefined as Record<string, unknown> | undefined,
  login: vi.fn(async () => {}),
  logout: vi.fn(async () => {}),
  updateToken: vi.fn(async () => false),
  initOptions: undefined as Record<string, unknown> | undefined,
}))

vi.mock('keycloak-js', () => ({
  default: class {
    token?: string
    tokenParsed?: Record<string, unknown>
    login = kc.login
    logout = kc.logout
    updateToken = kc.updateToken
    async init(options: Record<string, unknown>) {
      kc.initOptions = options
      if (kc.fail) throw new Error('Keycloak down')
      this.token = kc.token
      this.tokenParsed = kc.tokenParsed
      return kc.authenticated
    }
  },
}))

/** В jsdom под Node 25 глобальные localStorage/sessionStorage — нодовские заглушки без clear(): подставляем свои. */
function memoryStorage(): Storage {
  const map = new Map<string, string>()
  return {
    get length() { return map.size },
    clear: () => map.clear(),
    getItem: (k: string) => map.get(k) ?? null,
    key: (i: number) => [...map.keys()][i] ?? null,
    removeItem: (k: string) => { map.delete(k) },
    setItem: (k: string, v: string) => { map.set(k, String(v)) },
  } as Storage
}

function signedIn(roles: string[], claims: Record<string, unknown> = {}) {
  kc.authenticated = true
  kc.token = 'jwt'
  kc.tokenParsed = { preferred_username: `${roles[0]}1`, realm_access: { roles }, ...claims }
}

describe('auth store (Keycloak)', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    Object.assign(kc, { authenticated: false, fail: false, token: undefined, tokenParsed: undefined, initOptions: undefined })
    vi.clearAllMocks()
    Object.defineProperty(window, 'localStorage', { value: memoryStorage(), configurable: true })
    Object.defineProperty(window, 'sessionStorage', { value: memoryStorage(), configurable: true })
    window.history.replaceState(null, '', '/')
  })

  it('checks the session by redirect only after a previous login in this browser', async () => {
    await useAuthStore().init()
    expect(kc.initOptions).not.toHaveProperty('onLoad') // гость первый раз: без перехода в Keycloak и второй загрузки
    expect(window.sessionStorage.getItem('darumen.boot.skip')).toBeNull()

    setActivePinia(createPinia())
    signedIn(['citizen'])
    await useAuthStore().init()
    expect(window.localStorage.getItem('darumen.session')).toBe('1')

    setActivePinia(createPinia())
    await useAuthStore().init()
    expect(kc.initOptions).toMatchObject({ onLoad: 'check-sso' })
    expect(window.sessionStorage.getItem('darumen.boot.skip')).toBe('1') // заставка после возврата не повторится

    await useAuthStore().logout()
    expect(window.localStorage.getItem('darumen.session')).toBeNull()
  })

  it('stays a guest without a session and sends no auth headers', async () => {
    const auth = useAuthStore()
    await auth.init()
    expect(auth.isAuthenticated).toBe(false)
    expect(auth.keycloakUnavailable).toBe(false)
    expect(auth.roleHome()).toBe('/')
    expect(await auth.authHeaders()).toEqual({})
  })

  it('derives actor, roles and region from token claims', async () => {
    signedIn(['chief', 'offline_access'], { region_kato: '75' })
    const auth = useAuthStore()
    await auth.init()
    expect(auth.actor).toBe('chief1')
    expect(auth.roles).toEqual(['chief'])
    expect(auth.region).toBe('75')
    expect(auth.hasRole('chief', 'regulator')).toBe(true)
    expect(auth.hasRole('doctor')).toBe(false)
    expect(auth.roleHome()).toBe('/gov/regions/75')
    expect(await auth.authHeaders()).toEqual({ Authorization: 'Bearer jwt' })
    expect(kc.updateToken).toHaveBeenCalledWith(30)
  })

  it('admin passes every role check', async () => {
    signedIn(['admin'])
    const auth = useAuthStore()
    await auth.init()
    expect(auth.hasRole('doctor')).toBe(true)
    expect(auth.hasRole('steward')).toBe(true)
    expect(auth.roleHome()).toBe('/gov')
  })

  it('marks Keycloak unavailable when init fails and the realm does not answer, staying usable as a guest', async () => {
    kc.fail = true
    vi.stubGlobal('fetch', vi.fn(async () => { throw new Error('ECONNREFUSED') }))
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {})
    const auth = useAuthStore()
    await auth.init()
    expect(auth.isAuthenticated).toBe(false)
    expect(auth.keycloakUnavailable).toBe(true)
    expect(await auth.authHeaders()).toEqual({})
    warn.mockRestore()
    vi.unstubAllGlobals()
  })

  it('keeps the login button when the realm answers but the silent SSO check fails (iframe blocked by a proxy header)', async () => {
    kc.fail = true
    const fetchMock = vi.fn(async () => ({ ok: true }))
    vi.stubGlobal('fetch', fetchMock)
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {})
    const auth = useAuthStore()
    await auth.init()
    expect(auth.isAuthenticated).toBe(false)
    expect(auth.keycloakUnavailable).toBe(false)
    expect(fetchMock).toHaveBeenCalledWith(expect.stringMatching(/\/realms\/darumen$/), expect.anything())
    warn.mockRestore()
    vi.unstubAllGlobals()
  })

  it('login returns to the denied page, never to a protocol-relative url, and passes the idp hint', async () => {
    const auth = useAuthStore()
    await auth.init()
    window.history.replaceState(null, '', '/?denied=/gov/regions/19')
    await auth.login()
    expect(kc.login).toHaveBeenLastCalledWith({ redirectUri: `${window.location.origin}/gov/regions/19` })
    window.history.replaceState(null, '', '/?denied=//evil.example')
    await auth.login()
    expect(kc.login).toHaveBeenLastCalledWith({ redirectUri: `${window.location.origin}/` })
    await auth.login({ idpHint: 'egov' })
    expect(kc.login).toHaveBeenLastCalledWith({ redirectUri: `${window.location.origin}/`, idpHint: 'egov' })
  })

  it('a failed token refresh sends no headers instead of a stale token', async () => {
    signedIn(['doctor'])
    const auth = useAuthStore()
    await auth.init()
    kc.updateToken.mockRejectedValueOnce(new Error('expired'))
    expect(await auth.authHeaders()).toEqual({})
    expect(await auth.authHeaders()).toEqual({ Authorization: 'Bearer jwt' })
  })

  it('logout goes back to the origin', async () => {
    signedIn(['steward'])
    const auth = useAuthStore()
    await auth.init()
    await auth.logout()
    expect(kc.logout).toHaveBeenCalledWith({ redirectUri: window.location.origin })
  })
})
