import type { RouteLocationNormalized } from 'vue-router'
import { roleHome, type Role } from './roles'

export interface GuardAuth {
  isAuthenticated: boolean
  role: Role | null
  region: string | null
  hasRole: (...roles: Role[]) => boolean
}

type Target = Pick<RouteLocationNormalized, 'name' | 'path' | 'meta'> & { query: Record<string, unknown> }
type Denied = { name: 'home'; query: { denied: string } }

/** Правило входа для router.beforeEach. Без сессии открыты только страница входа `/` и страницы с meta.bare
 * (памятка пациенту по QR); любой другой адрес уводит на вход с `?denied=<путь>`, чтобы вернуться туда после
 * входа. Вошедший без нужной роли — тоже на `/` с `?denied=`; вошедший, попавший на `/` без `?denied`, — на
 * домашний экран своей роли. */
export function resolveEntry(to: Target, auth: GuardAuth): true | string | Denied {
  const isHome = to.name === 'home'
  const denied: Denied = { name: 'home', query: { denied: to.path } }
  if (!auth.isAuthenticated) {
    return isHome || to.meta.bare === true ? true : denied
  }
  if (to.meta.roles && !auth.hasRole(...to.meta.roles)) {
    return denied
  }
  if (isHome && !to.query.denied) {
    const home = roleHome(auth.role, auth.region)
    if (home !== '/') return home
  }
  return true
}
