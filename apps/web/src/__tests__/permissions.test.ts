import { describe, expect, it } from 'vitest'
import {
  homePath, MATRIX_PERMISSIONS, nextScope, normalizeRoles, permissionsForRoles, primaryRole, ROLE_KEYS, ROLE_PERMISSIONS, scopeIn, SYSTEM_PERMISSIONS,
} from '@/lib/permissions'

describe('permission matrix (docs/rbac.md)', () => {
  it('has 7 roles, 14 matrix permissions and 3 system permissions', () => {
    expect(ROLE_KEYS).toHaveLength(7)
    expect(MATRIX_PERMISSIONS).toHaveLength(14)
    expect(SYSTEM_PERMISSIONS).toEqual(['data.steward', 'admin.orgs', 'admin.roles'])
  })

  it('never removes public waiting times from any role', () => {
    for (const role of ROLE_KEYS) expect(ROLE_PERMISSIONS[role]['wait.public'], role).toBe('all')
  })

  it('gives admin every permission', () => {
    expect(permissionsForRoles(['admin']).map((p) => p.code)).toEqual([...MATRIX_PERMISSIONS, ...SYSTEM_PERMISSIONS])
  })

  it('treats the legacy chief role as org_admin and drops realm service roles', () => {
    expect(normalizeRoles(['chief', 'offline_access', 'default-roles-darumen'])).toEqual(['org_admin'])
    expect(permissionsForRoles(['chief'])).toEqual(permissionsForRoles(['org_admin']))
  })

  it('merges roles with the widest scope', () => {
    const merged = permissionsForRoles(['org_admin', 'regulator'])
    expect(merged.find((p) => p.code === 'org.cabinet')?.scope).toBe('all')
    expect(merged.find((p) => p.code === 'admin.users')?.scope).toBe('own')
  })

  it('scope own is empty without an organization', () => {
    const permissions = permissionsForRoles(['org_admin'])
    expect(scopeIn(permissions, 'worklist.view', null)).toBeNull()
    expect(scopeIn(permissions, 'worklist.view', '028B')).toBe('own')
    expect(scopeIn(permissions, 'wait.public', null)).toBe('all')
    expect(scopeIn(permissions, 'gov.map', '028B')).toBeNull()
  })

  it('picks the widest role for captions', () => {
    expect(primaryRole(['doctor', 'admin'])).toBe('admin')
    expect(primaryRole([])).toBeNull()
  })

  it('home: the first available screen', () => {
    const only = (...codes: string[]) => ({ can: (c: string) => codes.includes(c), moCode: '028B' })
    expect(homePath(only('org.cabinet', 'gov.map'))).toBe('/gov/organizations/028B')
    expect(homePath({ can: (c) => c === 'org.cabinet', moCode: null })).toBe('/account/profile')
    expect(homePath(only('data.steward'))).toBe('/steward')
    expect(homePath(only('admin.users', 'route.own'))).toBe('/gov/audit')
    expect(homePath(only('admin.roles', 'worklist.view', 'org.cabinet'))).toBe('/admin/users')
    expect(homePath(only('worklist.view', 'org.cabinet'))).toBe('/gov/organizations/028B')
    expect(homePath(only('gov.map', 'data.steward'))).toBe('/steward')
    expect(homePath(only('route.own'))).toBe('/me/route')
  })

  it('matrix cell cycles none → own → all → none, or none ⇄ all for roles without mo_code', () => {
    expect(nextScope(null, true)).toBe('own')
    expect(nextScope('own', true)).toBe('all')
    expect(nextScope('all', true)).toBeNull()
    expect(nextScope(null, false)).toBe('all')
    expect(nextScope('all', false)).toBeNull()
  })
})
