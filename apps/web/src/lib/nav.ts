import type { RouteMeta } from 'vue-router'
import type { NavGroup } from '@/router/meta'
import { canAny, requiredPermissions } from './permissions'

/** Порядок групп бокового каркаса персонала. */
export const SIDEBAR_GROUPS: readonly NavGroup[] = ['patients', 'hospital', 'ministry', 'admin', 'data', 'account']

export interface NavRoute { path: string; meta: RouteMeta }
export interface NavAccess {
  can: (code: string) => boolean
  moCode: string | null
  /** Регион пункта «Регион»: последний открытый или свой. */
  region: string | null
}
export interface NavItem { to: string; labelKey: string; icon: string; nav: number }
export interface NavSection { group: NavGroup; items: NavItem[] }

/** Группа пункта с учётом groupWhen (журнал решений, консоль стюарда). */
export function groupOf(meta: RouteMeta, access: Pick<NavAccess, 'can'>): { group?: NavGroup; navTitle?: string } {
  if (meta.groupWhen && meta.groupWhen.any.some((code) => access.can(code))) {
    return { group: meta.groupWhen.group, navTitle: meta.groupWhen.navTitle ?? meta.navTitle }
  }
  return { group: meta.group, navTitle: meta.navTitle }
}

function visible(route: NavRoute, access: Pick<NavAccess, 'can'>): boolean {
  return (
    route.meta.nav !== undefined && !!route.meta.title && !route.path.includes(':') && canAny(access, requiredPermissions(route.meta.permission)) &&
    (!route.meta.navPermission || access.can(route.meta.navPermission))
  )
}

/** Меню сайдбара только из разрешений: пункты маршрутов (meta.nav) плюс маршруты с параметрами — кабинет своей
 * организации (org.cabinet + mo_code) и «Регион» (gov.map + регион). Пустые группы не показываются. */
export function sidebarNav(routes: readonly NavRoute[], access: NavAccess): NavSection[] {
  const byGroup = new Map<NavGroup, NavItem[]>()
  const push = (group: NavGroup, item: NavItem) => byGroup.set(group, [...(byGroup.get(group) ?? []), item])
  for (const route of routes) {
    if (!visible(route, access)) continue
    const { group, navTitle } = groupOf(route.meta, access)
    if (!group || group === 'citizen') continue
    push(group, { to: route.path, labelKey: navTitle ?? route.meta.title!, icon: route.meta.icon ?? 'pi pi-circle', nav: route.meta.nav ?? 0 })
  }
  if (access.can('org.cabinet') && access.moCode) {
    push('hospital', { to: `/gov/organizations/${access.moCode}`, labelKey: 'nav.short.orgOverview', icon: 'pi pi-building', nav: 10 })
    push('hospital', { to: `/gov/organizations/${access.moCode}/referrals`, labelKey: 'nav.short.orgReferrals', icon: 'pi pi-inbox', nav: 20 })
  }
  if (access.can('gov.map') && access.region) {
    push('ministry', { to: `/gov/regions/${access.region}`, labelKey: 'nav.short.region', icon: 'pi pi-building', nav: 20 })
  }
  return SIDEBAR_GROUPS.map((group) => ({ group, items: [...(byGroup.get(group) ?? [])].sort((a, b) => a.nav - b.nav) })).filter((s) => s.items.length > 0)
}

/** Пункты верхней полосы гражданина (группа citizen) — тоже только из разрешений. */
export function topbarNav(routes: readonly NavRoute[], access: Pick<NavAccess, 'can'>): NavItem[] {
  return routes
    .filter((route) => route.meta.group === 'citizen' && visible(route, access))
    .map((route) => ({ to: route.path, labelKey: route.meta.navTitle ?? route.meta.title!, icon: route.meta.icon ?? 'pi pi-circle', nav: route.meta.nav ?? 0 }))
    .sort((a, b) => a.nav - b.nav)
}

/** Пункты группы «Аккаунт» (профиль, безопасность, …) — для меню пользователя в верхней полосе гражданина. */
export function accountNav(routes: readonly NavRoute[]): NavItem[] {
  return routes
    .filter((route) => route.meta.group === 'account' && route.meta.nav !== undefined && route.meta.title)
    .map((route) => ({ to: route.path, labelKey: route.meta.navTitle ?? route.meta.title!, icon: route.meta.icon ?? 'pi pi-circle', nav: route.meta.nav ?? 0 }))
    .sort((a, b) => a.nav - b.nav)
}
