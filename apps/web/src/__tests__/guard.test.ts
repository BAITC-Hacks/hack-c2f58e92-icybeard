import { describe, expect, it } from 'vitest'
import { resolveEntry, type GuardAuth } from '@/router/guard'
import type { Role } from '@/router/roles'

const anonymous: GuardAuth = { isAuthenticated: false, role: null, region: null, hasRole: () => false }
const signedIn = (role: Role, region: string | null = null): GuardAuth => ({
  isAuthenticated: true,
  role,
  region,
  hasRole: (...roles) => role === 'admin' || roles.includes(role),
})
const to = (path: string, meta: Record<string, unknown> = {}, name = path === '/' ? 'home' : path.slice(1), query = {}) => ({ name, path, meta, query })

describe('resolveEntry', () => {
  it('without a session opens only the login page and bare pages, everything else goes to login with ?denied', () => {
    expect(resolveEntry(to('/'), anonymous)).toBe(true)
    expect(resolveEntry(to('/leaflet/abc', { bare: true }), anonymous)).toBe(true)
    expect(resolveEntry(to('/wait'), anonymous)).toEqual({ name: 'home', query: { denied: '/wait' } })
    expect(resolveEntry(to('/medicines'), anonymous)).toEqual({ name: 'home', query: { denied: '/medicines' } })
    expect(resolveEntry(to('/gov', { roles: ['regulator'] }), anonymous)).toEqual({ name: 'home', query: { denied: '/gov' } })
  })

  it('sends a signed-in user from the login page to the home of the role', () => {
    expect(resolveEntry(to('/'), signedIn('citizen'))).toBe('/me/route')
    expect(resolveEntry(to('/'), signedIn('chief', '75'))).toBe('/gov/regions/75')
    expect(resolveEntry(to('/', {}, 'home', { denied: '/gov' }), signedIn('citizen'))).toBe(true)
  })

  it('checks roles for signed-in users and leaves pages without roles open to everyone signed in', () => {
    expect(resolveEntry(to('/wait'), signedIn('citizen'))).toBe(true)
    expect(resolveEntry(to('/wait'), signedIn('steward'))).toBe(true)
    expect(resolveEntry(to('/gov', { roles: ['chief', 'regulator'] }), signedIn('regulator'))).toBe(true)
    expect(resolveEntry(to('/gov', { roles: ['chief', 'regulator'] }), signedIn('admin'))).toBe(true)
    expect(resolveEntry(to('/gov', { roles: ['chief', 'regulator'] }), signedIn('citizen'))).toEqual({ name: 'home', query: { denied: '/gov' } })
  })
})
