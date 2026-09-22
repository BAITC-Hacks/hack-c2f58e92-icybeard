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
}))

vi.mock('keycloak-js', () => ({
  default: class {
    token?: string
    tokenParsed?: Record<string, unknown>
    login = kc.login
    logout = kc.logout
    updateToken = kc.updateToken
    async init() {
      if (kc.fail) throw new Error('Keycloak down')
      this.token = kc.token
      this.tokenParsed = kc.tokenParsed
      return kc.authenticated
    }
  },
}))

function signedIn(roles: string[], claims: Record<string, unknown> = {}) {
  kc.authenticated = true
  kc.token = 'jwt'
  kc.tokenParsed = { preferred_username: `${roles[0]}1`, realm_access: { roles }, ...claims }
}

describe('auth store (Keycloak)', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    Object.assign(kc, { authenticated: false, fail: false, token: undefined, tokenParsed: undefined })
    vi.clearAllMocks()
    window.history.replaceState(null, '', '/')
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

  it('marks Keycloak unavailable when init fails and stays usable as a guest', async () => {
    kc.fail = true
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {})
    const auth = useAuthStore()
    await auth.init()
    expect(auth.isAuthenticated).toBe(false)
    expect(auth.keycloakUnavailable).toBe(true)
    expect(await auth.authHeaders()).toEqual({})
    warn.mockRestore()
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
