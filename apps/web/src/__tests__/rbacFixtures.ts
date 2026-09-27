import type { GuardAuth } from '@/router/guard'
import { homePath, permissionsForRoles, scopeIn, type RoleKey } from '@/lib/permissions'

/** Доступ пользователя одной роли по матрице docs/rbac.md (тот же фолбэк, что у стора до ответа /me). */
export function accessFor(role: RoleKey, moCode: string | null = null) {
  const permissions = permissionsForRoles([role])
  const can = (code: string) => role === 'admin' || scopeIn(permissions, code, moCode) !== null
  return { can, moCode, permissions }
}

export function signedIn(role: RoleKey, moCode: string | null = null, welcomed = true): GuardAuth {
  const { can } = accessFor(role, moCode)
  return { isAuthenticated: true, can, landing: () => (welcomed ? homePath({ can, moCode }) : '/welcome') }
}

export const anonymous: GuardAuth = { isAuthenticated: false, can: () => false, landing: () => '/' }
