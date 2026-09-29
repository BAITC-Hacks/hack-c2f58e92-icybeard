import { describe, expect, it } from 'vitest'
import type { RouteMeta } from 'vue-router'
import { ROLE_KEYS, type RoleKey } from '@/lib/permissions'
import { router } from '@/router'
import { resolveEntry } from '@/router/guard'
import { anonymous, signedIn } from './rbacFixtures'

const MO = '028B'
const to = (path: string, meta: RouteMeta = {}, name?: string, query: Record<string, unknown> = {}) => ({ name: name ?? (path === '/' ? 'home' : path.slice(1)), path, fullPath: path, meta, query })
/** Маршрут приложения с его настоящей meta (разрешение из router/index.ts). */
function real(path: string) {
  const resolved = router.resolve(path)
  return { name: resolved.name as string, path: resolved.path, fullPath: resolved.fullPath, meta: resolved.meta, query: {} }
}

/** Кому открыт маршрут по матрице docs/rbac.md (org_admin — с клеймом mo_code). */
const ACCESS: Record<string, RoleKey[]> = {
  '/me/route': ['citizen', 'doctor', 'org_admin', 'admin'],
  '/wait': [...ROLE_KEYS],
  '/medicines': ['citizen', 'doctor', 'admin'],
  '/doctor/worklist': ['doctor', 'org_admin', 'admin'],
  '/doctor/referrals/incoming': ['doctor', 'org_admin', 'admin'],
  '/doctor/patients/SYN-75-028B-381-01': ['doctor', 'org_admin', 'admin'],
  '/doctor/referral': ['doctor', 'admin'],
  '/doctor/scribe': ['doctor', 'admin'],
  '/doctor/decisions': ['doctor', 'org_admin', 'regulator', 'auditor', 'admin'],
  '/gov': ['regulator', 'steward', 'auditor', 'admin'],
  '/gov/regions/75': ['regulator', 'steward', 'auditor', 'admin'],
  '/quality': ['doctor', 'regulator', 'steward', 'auditor', 'admin'],
  '/gov/simulator': ['regulator', 'admin'],
  '/gov/insight': ['regulator', 'steward', 'admin'],
  '/gov/organizations/028B': ['org_admin', 'regulator', 'admin'],
  '/gov/organizations/028B/referrals': ['org_admin', 'regulator', 'admin'],
  '/admin/users': ['org_admin', 'auditor', 'admin'],
  '/admin/doctors': ['org_admin', 'auditor', 'admin'],
  '/gov/audit': ['org_admin', 'auditor', 'admin'],
  '/admin/roles': ['admin'],
  '/admin/orgs': ['regulator', 'admin'],
  '/steward': ['steward', 'admin'],
  '/account/profile': [...ROLE_KEYS],
  '/account/security': [...ROLE_KEYS],
  '/welcome': [...ROLE_KEYS],
}

describe('resolveEntry', () => {
  it('without a session opens only the login page, public and bare pages; everything else goes to login with ?denied', () => {
    expect(resolveEntry(to('/'), anonymous)).toBe(true)
    expect(resolveEntry(real('/leaflet/abc'), anonymous)).toBe(true)
    expect(resolveEntry(real('/signup'), anonymous)).toBe(true)
    expect(resolveEntry(real('/signup/42'), anonymous)).toBe(true)
    expect(resolveEntry(real('/invite/token-1'), anonymous)).toBe(true)
    expect(resolveEntry(real('/wait'), anonymous)).toEqual({ name: 'home', query: { denied: '/wait' } })
    expect(resolveEntry(real('/admin/users'), anonymous)).toEqual({ name: 'home', query: { denied: '/admin/users' } })
    expect(resolveEntry(real('/account/profile'), anonymous)).toEqual({ name: 'home', query: { denied: '/account/profile' } })
    expect(resolveEntry(to('/no-access', {}, 'forbidden', { from: '/gov' }), anonymous)).toEqual({ name: 'home', query: { denied: '/gov' } })
  })

  it('sends a signed-in user from the login page to the first available screen (docs/rbac.md)', () => {
    expect(resolveEntry(to('/'), signedIn('citizen'))).toBe('/me/route')
    // после задачи 1.2 (worklist.view у врача — own, не all) врачу без организации попадать некуда, кроме своего маршрута
    expect(resolveEntry(to('/'), signedIn('doctor', MO))).toBe('/doctor/worklist')
    expect(resolveEntry(to('/'), signedIn('org_admin', MO))).toBe(`/gov/organizations/${MO}`)
    expect(resolveEntry(to('/'), signedIn('org_admin'))).toBe('/account/profile')
    expect(resolveEntry(to('/'), signedIn('regulator'))).toBe('/gov')
    expect(resolveEntry(to('/'), signedIn('steward'))).toBe('/steward')
    expect(resolveEntry(to('/'), signedIn('auditor'))).toBe('/gov/audit')
    expect(resolveEntry(to('/'), signedIn('admin'))).toBe('/admin/users')
    expect(resolveEntry(to('/', {}, 'home', { denied: '/gov' }), signedIn('citizen'))).toBe('/me/route')
  })

  it('shows «Первый вход» after the first login', () => {
    expect(resolveEntry(to('/'), signedIn('doctor', null, false))).toBe('/welcome')
  })

  it.each(ROLE_KEYS)('checks the permission of every route for %s', (role) => {
    const auth = signedIn(role, MO)
    for (const [path, allowed] of Object.entries(ACCESS)) {
      const result = resolveEntry(real(path), auth)
      if (allowed.includes(role)) expect(result, `${role} ${path}`).toBe(true)
      else expect(result, `${role} ${path}`).toMatchObject({ name: 'forbidden', query: { from: path } })
    }
  })

  it('names the missing permission for the access request', () => {
    expect(resolveEntry(real('/gov'), signedIn('doctor'))).toEqual({ name: 'forbidden', query: { from: '/gov', permission: 'gov.map' } })
    expect(resolveEntry(real('/doctor/decisions'), signedIn('citizen'))).toEqual({ name: 'forbidden', query: { from: '/doctor/decisions', permission: 'decisions.own' } })
  })

  it('scope own needs an organization: org_admin without mo_code sees none of its organization pages', () => {
    const noOrg = signedIn('org_admin')
    for (const path of ['/doctor/worklist', '/admin/users', '/gov/organizations/028B', '/doctor/decisions']) {
      expect(resolveEntry(real(path), noOrg), path).toMatchObject({ name: 'forbidden' })
    }
    expect(resolveEntry(real('/wait'), noOrg)).toBe(true)
  })
})
