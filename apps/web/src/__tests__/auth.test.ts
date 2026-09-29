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
    expect(kc.initOptions).not.toHaveProperty('onLoad') // первый заход без сессии: без перехода в Keycloak и второй загрузки
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

  it('stays signed out without a session and sends no auth headers', async () => {
    const auth = useAuthStore()
    await auth.init()
    expect(auth.isAuthenticated).toBe(false)
    expect(auth.keycloakUnavailable).toBe(false)
    expect(auth.roleHome()).toBe('/')
    expect(await auth.authHeaders()).toEqual({})
  })

  it('derives actor, roles and region from token claims; chief is the legacy org_admin', async () => {
    signedIn(['chief', 'offline_access'], { region_kato: '75' })
    const auth = useAuthStore()
    await auth.init()
    expect(auth.actor).toBe('chief1')
    expect(auth.roles).toEqual(['org_admin'])
    expect(auth.region).toBe('75')
    expect(auth.moCode).toBeNull()
    expect(auth.permissionSource).toBe('token')
    // scope own без mo_code пуст: остаются только общие разрешения
    expect(auth.can('worklist.view')).toBe(false)
    expect(auth.can('wait.public')).toBe(true)
    expect(auth.roleHome()).toBe('/account/profile')
    expect(await auth.authHeaders()).toEqual({ Authorization: 'Bearer jwt' })
    expect(kc.updateToken).toHaveBeenCalledWith(30)
  })

  it('an org_admin with mo_code gets scope own and lands in the cabinet of the organization', async () => {
    signedIn(['org_admin'], { region_kato: '75', mo_code: '028B' })
    const auth = useAuthStore()
    await auth.init()
    expect(auth.moCode).toBe('028B')
    expect(auth.scopeOf('admin.users')).toBe('own')
    expect(auth.scopeOf('gov.map')).toBeNull()
    expect(auth.roleHome()).toBe('/gov/organizations/028B')
    expect(auth.sidebar).toBe(true)
  })

  it('admin passes every permission check', async () => {
    signedIn(['admin'])
    const auth = useAuthStore()
    await auth.init()
    expect(auth.can('admin.roles')).toBe(true)
    expect(auth.can('worklist.view')).toBe(true)
    expect(auth.canAny(['gov.map', 'nothing'])).toBe(true)
    expect(auth.roleHome()).toBe('/admin/users')
  })

  it('citizen keeps the top bar', async () => {
    signedIn(['citizen'])
    const auth = useAuthStore()
    await auth.init()
    expect(auth.sidebar).toBe(false)
    expect(auth.roleHome()).toBe('/me/route')
  })

  it('shows «Первый вход» once per user', async () => {
    // worklist.view — own (задача 1.2): врачу нужна организация, иначе после «Первого входа» ему попадать некуда
    signedIn(['doctor'], { mo_code: '028B' })
    const auth = useAuthStore()
    await auth.init()
    expect(auth.landing()).toBe('/welcome')
    auth.markWelcomeSeen()
    expect(auth.landing()).toBe('/doctor/worklist')
  })

  it('takes permissions, roles and organization from GET /me when it answers', async () => {
    signedIn(['doctor'])
    const me = {
      actor: 'doctor1', userId: 'u1', displayName: 'А. Сейткали', email: 'a@x.kz', emailVerified: true, roles: ['doctor'],
      permissions: [{ code: 'worklist.view', scope: 'all' }, { code: 'gov.map', scope: 'all' }], moCode: '08IV', moName: 'Онкоцентр',
      regionKato: '75', iinMasked: null, onboarding: { emailVerified: true, otpConfigured: false, profileChecked: false, colleaguesInvited: false },
    }
    vi.stubGlobal('fetch', vi.fn(async () => ({ ok: true, status: 200, statusText: 'OK', text: async () => JSON.stringify(me) })))
    const auth = useAuthStore()
    await auth.init()
    expect(await auth.loadMe()).toBe(true)
    expect(auth.permissionSource).toBe('api')
    expect(auth.can('gov.map')).toBe(true) // из /me, хотя в матрице у врача его нет
    expect(auth.can('scribe.use')).toBe(false)
    expect(auth.moCode).toBe('08IV')
    expect(auth.displayName).toBe('А. Сейткали')
    vi.unstubAllGlobals()
  })

  it('keeps the token fallback when GET /me is not there yet (404)', async () => {
    signedIn(['regulator'])
    vi.stubGlobal('fetch', vi.fn(async () => ({ ok: false, status: 404, statusText: 'Not Found', text: async () => '' })))
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {})
    const auth = useAuthStore()
    await auth.init()
    expect(await auth.loadMe()).toBe(false)
    expect(auth.permissionSource).toBe('token')
    expect(auth.can('gov.simulator')).toBe(true)
    expect(auth.can('worklist.view')).toBe(false)
    warn.mockRestore()
    vi.unstubAllGlobals()
  })

  it('marks Keycloak unavailable when init fails and the realm does not answer, keeping the login page usable', async () => {
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
    expect(kc.login).toHaveBeenLastCalledWith({ redirectUri: `${window.location.origin}/gov/regions/19`, locale: 'ru' })
    window.history.replaceState(null, '', '/?denied=//evil.example')
    await auth.login()
    expect(kc.login).toHaveBeenLastCalledWith({ redirectUri: `${window.location.origin}/`, locale: 'ru' })
    await auth.login({ idpHint: 'egov' })
    expect(kc.login).toHaveBeenLastCalledWith({ redirectUri: `${window.location.origin}/`, locale: 'ru', idpHint: 'egov' })
  })

  it('a failed token refresh sends no headers instead of a stale token', async () => {
    signedIn(['doctor'])
    const auth = useAuthStore()
    await auth.init()
    kc.updateToken.mockRejectedValueOnce(new Error('expired'))
    expect(await auth.authHeaders()).toEqual({})
    expect(await auth.authHeaders()).toEqual({ Authorization: 'Bearer jwt' })
  })

  it('silently restarts the login when the Keycloak form expired (authentication_expired)', async () => {
    window.history.replaceState(null, '', '/gov/regions/19#error=temporarily_unavailable&error_description=authentication_expired&state=s1')
    const auth = useAuthStore()
    await auth.init()
    expect(auth.isAuthenticated).toBe(false)
    expect(window.location.hash).toBe('')
    expect(kc.login).toHaveBeenCalledWith({ redirectUri: `${window.location.origin}/gov/regions/19`, locale: 'ru' })
  })

  it('does not restart the login for other callback errors', async () => {
    window.history.replaceState(null, '', '/#error=login_required&state=s2')
    await useAuthStore().init()
    expect(kc.login).not.toHaveBeenCalled()
  })

  it('logout goes back to the origin', async () => {
    signedIn(['steward'])
    const auth = useAuthStore()
    await auth.init()
    await auth.logout()
    expect(kc.logout).toHaveBeenCalledWith({ redirectUri: window.location.origin })
  })
})
