import { i18n } from '@/i18n'
import { LEGACY_ROLE_ALIASES } from './permissions'

/** Подписи ролей и разрешений на языке интерфейса: из справочника API (`/admin/roles`: titleRu/titleKk), иначе из
 * словаря (roles.* и permissions.* — названия строк и колонок матрицы docs/rbac.md), иначе ключ как есть. */
export interface Titled { titleRu: string; titleKk: string }

function pick(entry: Titled | undefined): string | null {
  if (!entry) return null
  return i18n.global.locale.value === 'kk' ? entry.titleKk || entry.titleRu : entry.titleRu
}

export function roleTitle(role: string, catalog?: Record<string, Titled>): string {
  const key = LEGACY_ROLE_ALIASES[role] ?? role
  const fromApi = pick(catalog?.[key])
  if (fromApi) return fromApi
  const path = `roles.${key}`
  return i18n.global.te(path) ? i18n.global.t(path) : role
}

/** Короткая подпись роли для чипов таблиц («Админ. организации»). */
export function roleShort(role: string): string {
  const key = LEGACY_ROLE_ALIASES[role] ?? role
  const path = `roles.short.${key}`
  return i18n.global.te(path) ? i18n.global.t(path) : roleTitle(role)
}

export function permissionTitle(code: string, catalog?: Record<string, Titled>): string {
  const fromApi = pick(catalog?.[code])
  if (fromApi) return fromApi
  const path = `permissions.${code.replace('.', '_')}`
  return i18n.global.te(path) ? i18n.global.t(path) : code
}

/** Инициалы для аватара: «А. Сейткали» → «АС», «a.seitkali» → «AS». */
export function initials(name: string | null | undefined): string {
  const parts = (name ?? '').replace(/[._@-]+/g, ' ').trim().split(/\s+/).filter(Boolean)
  if (parts.length === 0) return '·'
  const letters = parts.length === 1 ? parts[0]!.slice(0, 2) : parts[0]![0]! + parts[parts.length - 1]![0]!
  return letters.toUpperCase()
}
