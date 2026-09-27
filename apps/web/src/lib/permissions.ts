/**
 * Роли и разрешения — единственная на клиенте копия матрицы docs/rbac.md. Источник истины — бэкенд (`GET /api/v1/me`
 * отдаёт набор разрешений пользователя); матрица ниже — фолбэк, пока `/me` не ответил, и основа тестов меню и
 * защиты маршрутов. Клиент не держит списков «роль → экран»: экраны и пункты меню спрашивают разрешения.
 */

/** Роли realm `darumen` в порядке колонок матрицы. */
export const ROLE_KEYS = ['citizen', 'doctor', 'org_admin', 'regulator', 'steward', 'auditor', 'admin'] as const
export type RoleKey = (typeof ROLE_KEYS)[number]

/** Прежняя роль главврача: в токене трактуется как администратор организации (docs/rbac.md). */
export const LEGACY_ROLE_ALIASES: Readonly<Record<string, RoleKey>> = { chief: 'org_admin' }

/** Роль для подписей («пользователь · роль»), когда ролей несколько: самая широкая. */
const ROLE_PRIORITY: readonly RoleKey[] = ['admin', 'regulator', 'org_admin', 'auditor', 'steward', 'doctor', 'citizen']

/** 14 разрешений матрицы (редактируются на странице «Роли и доступ»), в порядке строк доски W-Admin-Roles. */
export const MATRIX_PERMISSIONS = [
  'route.own', 'wait.public', 'medicines.check', 'worklist.view', 'referral.assist', 'referral.confirm', 'scribe.use',
  'decisions.own', 'decisions.all', 'gov.map', 'gov.simulator', 'insight.ask', 'org.cabinet', 'admin.users',
] as const
/** Системные разрешения: не показываются в матрице и не редактируются. */
export const SYSTEM_PERMISSIONS = ['data.steward', 'admin.orgs', 'admin.roles'] as const
export type MatrixPermission = (typeof MATRIX_PERMISSIONS)[number]
export type SystemPermission = (typeof SYSTEM_PERMISSIONS)[number]
export type PermissionCode = MatrixPermission | SystemPermission
export const PERMISSION_CODES: readonly PermissionCode[] = [...MATRIX_PERMISSIONS, ...SYSTEM_PERMISSIONS]

/** `all` — без ограничений; `own` — только своя организация (клейм mo_code). */
export type Scope = 'all' | 'own'
export interface Permission { code: string; scope: Scope }

/** Разрешения гражданина: только их набор даёт верхнюю полосу вместо бокового каркаса персонала. */
export const CITIZEN_PERMISSIONS: readonly PermissionCode[] = ['route.own', 'wait.public', 'medicines.check']

const A: Scope = 'all'
const O: Scope = 'own'
const everything = Object.fromEntries(PERMISSION_CODES.map((code) => [code, A])) as Record<PermissionCode, Scope>

/** Матрица docs/rbac.md: роль → разрешение → scope (нет ключа — нет доступа). */
export const ROLE_PERMISSIONS: Readonly<Record<RoleKey, Readonly<Partial<Record<PermissionCode, Scope>>>>> = {
  citizen: { 'route.own': A, 'wait.public': A, 'medicines.check': A },
  doctor: {
    'route.own': A, 'wait.public': A, 'medicines.check': A, 'worklist.view': A, 'referral.assist': A, 'referral.confirm': A,
    'scribe.use': A, 'decisions.own': A,
  },
  org_admin: {
    'route.own': O, 'wait.public': A, 'worklist.view': O, 'referral.confirm': O, 'decisions.own': O, 'decisions.all': O,
    'org.cabinet': O, 'admin.users': O,
  },
  regulator: {
    'wait.public': A, 'decisions.all': A, 'gov.map': A, 'gov.simulator': A, 'insight.ask': A, 'org.cabinet': A, 'admin.orgs': A,
  },
  steward: { 'wait.public': A, 'gov.map': A, 'insight.ask': A, 'data.steward': A },
  auditor: { 'wait.public': A, 'decisions.own': A, 'decisions.all': A, 'gov.map': A, 'admin.users': A },
  admin: everything,
}

/** Роли, у которых есть клейм mo_code: для остальных «своя организация» в матрице не предлагается. */
export const ROLES_WITH_ORGANIZATION: readonly RoleKey[] = ['doctor', 'org_admin']
/** Роли, которые администратор организации может назначать в своей организации (scope own у admin.users). */
export const ORG_ASSIGNABLE_ROLES: readonly RoleKey[] = ['doctor', 'org_admin']

export function isRoleKey(value: unknown): value is RoleKey {
  return typeof value === 'string' && (ROLE_KEYS as readonly string[]).includes(value)
}

/** Роли токена или `/me` → роли матрицы: legacy-алиасы (chief → org_admin), без служебных ролей realm, без повторов. */
export function normalizeRoles(raw: readonly string[] | null | undefined): RoleKey[] {
  const mapped = new Set((raw ?? []).map((role) => LEGACY_ROLE_ALIASES[role] ?? role))
  return ROLE_KEYS.filter((role) => mapped.has(role))
}

export function primaryRole(roles: readonly RoleKey[]): RoleKey | null {
  return ROLE_PRIORITY.find((role) => roles.includes(role)) ?? null
}

/** Объединение разрешений ролей с максимальным scope (all шире own). */
export function permissionsForRoles(roles: readonly string[]): Permission[] {
  const merged = new Map<string, Scope>()
  for (const role of normalizeRoles(roles)) {
    for (const [code, scope] of Object.entries(ROLE_PERMISSIONS[role])) {
      if (merged.get(code) !== A) merged.set(code, scope as Scope)
    }
  }
  return PERMISSION_CODES.filter((code) => merged.has(code)).map((code) => ({ code, scope: merged.get(code)! }))
}

/** Действующий scope: `own` без организации пуст (API отвечает 403 `no_organization`), поэтому и на клиенте — нет. */
export function scopeIn(permissions: readonly Permission[], code: string, moCode: string | null): Scope | null {
  const scope = permissions.find((p) => p.code === code)?.scope ?? null
  return scope === O && !moCode ? null : scope
}

export interface Access {
  can: (code: string) => boolean
  moCode: string | null
}

/** Разрешение маршрута: одно или любое из списка. */
export function requiredPermissions(value: string | readonly string[] | undefined): string[] {
  if (!value) return []
  return typeof value === 'string' ? [value] : [...value]
}

export function canAny(access: Pick<Access, 'can'>, codes: readonly string[]): boolean {
  return codes.length === 0 || codes.some((code) => access.can(code))
}

/** Домашний экран — первый доступный по правилу docs/rbac.md: администратор системы — пользователи, администратор
 * организации — кабинет своей организации, врач — рабочий список, стюард — консоль, аудитор — журнал аудита,
 * регулятор — карта, гражданин — «Мой путь»; без разрешений — профиль аккаунта. */
export function homePath(access: Access): string {
  if (access.can('admin.roles')) return '/admin/users'
  if (access.can('org.cabinet') && access.moCode) return `/gov/organizations/${access.moCode}`
  if (access.can('worklist.view')) return '/doctor/worklist'
  if (access.can('data.steward')) return '/steward'
  if (access.can('admin.users')) return '/gov/audit'
  if (access.can('gov.map')) return '/gov'
  if (access.can('route.own')) return '/me/route'
  return '/account/profile'
}

/** Каркас персонала (боковая навигация) — у всех, у кого есть что-то кроме разрешений гражданина. */
export function usesSidebar(permissions: readonly Permission[]): boolean {
  return permissions.some((p) => !(CITIZEN_PERMISSIONS as readonly string[]).includes(p.code))
}

/** Роли, для которых в матрице доступен scope `own`. */
export function supportsOwnScope(role: string): boolean {
  return (ROLES_WITH_ORGANIZATION as readonly string[]).includes(role)
}

/** Следующее состояние ячейки матрицы по клику: нет → своя орг. → разрешено → нет; без mo_code — нет ⇄ разрешено. */
export function nextScope(current: Scope | null, withOwn: boolean): Scope | null {
  if (current === null) return withOwn ? O : A
  if (current === O) return A
  return null
}
