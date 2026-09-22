/** Роли realm Keycloak `darumen` — единственный источник для защиты маршрутов, меню и домашних экранов. */
export type Role = 'citizen' | 'doctor' | 'chief' | 'regulator' | 'steward' | 'admin'
export const ROLES: readonly Role[] = ['citizen', 'doctor', 'chief', 'regulator', 'steward', 'admin']

export function isRole(value: unknown): value is Role {
  return typeof value === 'string' && (ROLES as readonly string[]).includes(value)
}

/** Домашний экран роли: гражданин → свой маршрут, врач → рабочий список, главврач → свой регион, регулятор → карта, стюард → консоль. */
export function roleHome(role: Role | null, region: string | null = null): string {
  switch (role) {
    case 'citizen':
      return '/me/route'
    case 'doctor':
      return '/doctor/worklist'
    case 'chief':
      return region ? `/gov/regions/${region}` : '/gov'
    case 'regulator':
    case 'admin':
      return '/gov'
    case 'steward':
      return '/steward'
    default:
      return '/'
  }
}

declare module 'vue-router' {
  interface RouteMeta {
    /** Роли, которым открыт маршрут; без поля — публичный. */
    roles?: Role[]
    /** Ключ i18n заголовка страницы (вкладка браузера и пункт меню). */
    title?: string
    /** Позиция в меню шапки; без поля маршрут в меню не попадает. */
    nav?: number
  }
}
