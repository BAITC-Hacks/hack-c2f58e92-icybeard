import type { RouteLocationNormalized } from 'vue-router'
import { requiredPermissions } from '@/lib/permissions'

export interface GuardAuth {
  isAuthenticated: boolean
  can: (code: string) => boolean
  /** Куда вести вошедшего с `/`: «Первый вход» при первом входе, иначе домашний экран по разрешениям. */
  landing: () => string
}

type Target = Pick<RouteLocationNormalized, 'name' | 'path' | 'meta'> & { query: Record<string, unknown>; fullPath?: string }
type Redirect = { name: 'home'; query: { denied: string } } | { name: 'forbidden'; query: { from: string; permission: string } }

/** Правило входа для router.beforeEach. Без сессии открыты только страница входа `/`, публичные страницы
 * (meta.public: регистрация организации, приглашение) и meta.bare (памятка по QR); любой другой адрес уводит на
 * вход с `?denied=<путь>`, чтобы вернуться туда после входа. Вошедший с `/` уходит на свой экран; вошедший без
 * разрешения маршрута (meta.permission, любое из списка) — на состояние «Нет доступа к разделу» с адресом и кодом
 * разрешения для запроса доступа. */
export function resolveEntry(to: Target, auth: GuardAuth): true | string | Redirect {
  if (to.meta.public === true || to.meta.bare === true) return true
  const isHome = to.name === 'home'
  if (!auth.isAuthenticated) {
    if (isHome) return true
    // «нет доступа» без сессии (сессия истекла на этой странице) — вход с возвратом на исходный раздел
    const denied = to.name === 'forbidden' ? String(to.query.from ?? '/') : to.path
    return { name: 'home', query: { denied } }
  }
  if (isHome) {
    const landing = auth.landing()
    return landing !== '/' ? landing : true
  }
  const required = requiredPermissions(to.meta.permission)
  if (required.length > 0 && !required.some((code) => auth.can(code))) {
    return { name: 'forbidden', query: { from: to.fullPath ?? to.path, permission: required[0]! } }
  }
  return true
}
