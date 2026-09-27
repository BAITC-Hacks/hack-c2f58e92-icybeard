import type { AdminOrg, AdminUser, MatrixCell, OrgStatus, PermissionScope, UserStatus, Verification } from '@/api/types'
import type { StatusTone } from '@/components/ui/tones'
import { MATRIX_PERMISSIONS, normalizeRoles, ORG_ASSIGNABLE_ROLES, ROLE_KEYS, ROLE_PERMISSIONS, type RoleKey, type Scope } from './permissions'

/** Тона статусов администрирования по доскам: активен — good, приглашён / ожидает / настройка — info, заблокирован /
 * нет данных — нейтральный, отклонён — attention. */
export const USER_STATUS_TONE: Record<UserStatus, StatusTone> = { active: 'ok', invited: 'info', blocked: 'neutral' }
export const VERIFICATION_TONE: Record<Verification, StatusTone> = { verified: 'ok', pending: 'info', rejected: 'warn' }
export const ORG_STATUS_TONE: Record<OrgStatus, StatusTone> = { connected: 'ok', setup: 'info', no_data: 'neutral' }

/** Задержка загрузки набора дольше этого числа дней — чип «задержка N дн.» вместо «в норме». */
export const FRESH_DAYS = 3

/** Последняя загрузка организации: поле API или самая свежая партия по наборам. */
export function lastLoad(org: Pick<AdminOrg, 'lastLoadAt' | 'freshness'>): string | null {
  if (org.lastLoadAt) return org.lastLoadAt
  const dates = (org.freshness ?? []).map((f) => f.lastLoadedAt).filter((d): d is string => !!d).sort()
  return dates.at(-1) ?? null
}

/** Основная роль строки пользователя (для выбора в панели): первая роль матрицы. */
export function mainRole(user: Pick<AdminUser, 'roles'>): RoleKey | null {
  return normalizeRoles(user.roles)[0] ?? null
}

/** Роли, которые можно назначить: при scope own у admin.users — только врач и администратор организации. */
export function assignableRoles(scope: Scope | null): readonly RoleKey[] {
  return scope === 'own' ? ORG_ASSIGNABLE_ROLES : ROLE_KEYS
}

/** Разрешения матрицы у роли: из ответа /admin/roles, а без него — по матрице docs/rbac.md. */
export function rolePermissions(role: string, matrix?: readonly MatrixCell[] | null): { code: string; scope: PermissionScope }[] {
  if (matrix) {
    return MATRIX_PERMISSIONS.flatMap((code) => {
      const cell = matrix.find((c) => c.role === role && c.permission === code)
      return cell ? [{ code, scope: cell.scope }] : []
    })
  }
  const own = ROLE_PERMISSIONS[role as RoleKey] ?? {}
  return MATRIX_PERMISSIONS.flatMap((code) => (own[code] ? [{ code, scope: own[code]! }] : []))
}

/** Дней с момента `iso` (для «задержка N дн.» и «изменён N дней назад»). */
export function daysSince(iso: string | null | undefined, now = Date.now()): number | null {
  if (!iso) return null
  const at = new Date(iso).getTime()
  return Number.isNaN(at) ? null : Math.max(0, Math.floor((now - at) / 86_400_000))
}
