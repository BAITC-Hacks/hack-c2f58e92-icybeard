import { describe, expect, it } from 'vitest'
import { accountNav, sidebarNav, topbarNav } from '@/lib/nav'
import { usesSidebar, type RoleKey } from '@/lib/permissions'
import { router } from '@/router'
import { accessFor } from './rbacFixtures'

const routes = router.getRoutes()
const ACCOUNT = ['/welcome', '/account/profile', '/account/security', '/account/notifications', '/account/consents']
const MO = '028B'

function menu(role: RoleKey, moCode: string | null = null, region: string | null = null): Record<string, string[]> {
  const access = accessFor(role, moCode)
  return Object.fromEntries(sidebarNav(routes, { can: access.can, moCode, region }).map((s) => [s.group, s.items.map((i) => i.to)]))
}

describe('menu from permissions', () => {
  it('citizen gets the top bar with its three screens and no sidebar', () => {
    const access = accessFor('citizen')
    expect(usesSidebar(access.permissions)).toBe(false)
    expect(topbarNav(routes, access).map((i) => i.to)).toEqual(['/me/route', '/wait', '/medicines'])
  })

  it('doctor: patients and account', () => {
    // worklist.view (и вместе с ней — входящие направления, задача 4) — own: без организации у врача их не будет
    expect(menu('doctor', MO)).toEqual({
      patients: ['/doctor/worklist', '/doctor/referrals/incoming', '/doctor/referral', '/doctor/scribe', '/doctor/decisions'], account: ACCOUNT,
    })
  })

  it('org_admin (own organization): its worklist, cabinet, users and audit', () => {
    expect(menu('org_admin', '028B')).toEqual({
      patients: ['/doctor/worklist', '/doctor/referrals/incoming', '/doctor/decisions'],
      hospital: ['/gov/organizations/028B', '/gov/organizations/028B/referrals'],
      admin: ['/admin/users', '/admin/doctors', '/gov/audit'],
      account: ACCOUNT,
    })
  })

  it('org_admin without mo_code sees only the account', () => {
    expect(menu('org_admin')).toEqual({ account: ACCOUNT })
  })

  it('regulator: ministry with the region, organizations and the decisions journal', () => {
    expect(menu('regulator', null, '75')).toEqual({
      ministry: ['/gov', '/gov/regions/75', '/gov/simulator', '/gov/insight', '/quality'],
      admin: ['/admin/orgs'],
      data: ['/doctor/decisions'],
      account: ACCOUNT,
    })
  })

  it('steward: map, questions and the steward console under «Данные»', () => {
    expect(menu('steward')).toEqual({ ministry: ['/gov', '/gov/insight', '/quality'], data: ['/steward'], account: ACCOUNT })
  })

  it('auditor: map, users, audit and all decisions', () => {
    expect(menu('auditor')).toEqual({ ministry: ['/gov', '/quality'], admin: ['/admin/users', '/admin/doctors', '/gov/audit'], data: ['/doctor/decisions'], account: ACCOUNT })
  })

  it('admin: everything, the steward console as «Данные» inside administration', () => {
    const sections = menu('admin')
    expect(sections.admin).toEqual(['/admin/users', '/admin/doctors', '/admin/roles', '/admin/orgs', '/steward', '/gov/audit'])
    expect(sections.patients).toEqual(['/doctor/worklist', '/doctor/referrals/incoming', '/doctor/referral', '/doctor/scribe', '/doctor/decisions'])
    expect(sections.ministry).toEqual(['/gov', '/gov/simulator', '/gov/insight', '/quality'])
    const access = accessFor('admin')
    const steward = sidebarNav(routes, { can: access.can, moCode: null, region: null }).find((s) => s.group === 'admin')!.items.find((i) => i.to === '/steward')!
    expect(steward.labelKey).toBe('nav.short.data')
  })

  it('every signed-in role except the citizen uses the sidebar', () => {
    for (const role of ['doctor', 'org_admin', 'regulator', 'steward', 'auditor', 'admin'] as const) {
      expect(usesSidebar(accessFor(role, '028B').permissions), role).toBe(true)
    }
  })

  it('the account menu of the top bar lists the account pages', () => {
    expect(accountNav(routes).map((i) => i.to)).toEqual(ACCOUNT)
  })
})
