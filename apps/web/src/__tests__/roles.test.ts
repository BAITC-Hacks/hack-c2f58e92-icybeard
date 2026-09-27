import { describe, expect, it } from 'vitest'
import { ROLES, isRole, roleHome } from '@/router/roles'

describe('roles', () => {
  it('recognises only realm roles', () => {
    expect(ROLES).toHaveLength(6)
    expect(isRole('doctor')).toBe(true)
    expect(isRole('offline_access')).toBe(false)
    expect(isRole(null)).toBe(false)
  })

  it('sends each role to its home and no role to the login page', () => {
    expect(roleHome('citizen')).toBe('/me/route')
    expect(roleHome('doctor')).toBe('/doctor/worklist')
    expect(roleHome('chief', '75')).toBe('/gov/regions/75')
    expect(roleHome('chief', '75', '028B')).toBe('/gov/organizations/028B')
    expect(roleHome('chief')).toBe('/gov')
    expect(roleHome('regulator')).toBe('/gov')
    expect(roleHome('admin')).toBe('/gov')
    expect(roleHome('steward')).toBe('/steward')
    expect(roleHome(null)).toBe('/')
  })
})
