/** Роли realm Keycloak `darumen` — единственный источник для защиты маршрутов, меню и домашних экранов. */
export type Role = 'citizen' | 'doctor' | 'chief' | 'regulator' | 'steward' | 'admin'
export const ROLES: readonly Role[] = ['citizen', 'doctor', 'chief', 'regulator', 'steward', 'admin']

export function isRole(value: unknown): value is Role {
  return typeof value === 'string' && (ROLES as readonly string[]).includes(value)
}

/** Домашний экран роли: гражданин → свой маршрут, врач → рабочий список, главврач → кабинет своей организации
 * (клейм mo_code), без него — свой регион, регулятор → карта, стюард → консоль; без роли — страница входа. */
export function roleHome(role: Role | null, region: string | null = null, moCode: string | null = null): string {
  switch (role) {
    case 'citizen':
      return '/me/route'
    case 'doctor':
      return '/doctor/worklist'
    case 'chief':
      if (moCode) return `/gov/organizations/${moCode}`
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

/** Группы боковой навигации персонала: врач — «Пациенты»; главврач — «Больница» · «Общее»; регулятор —
 * «Министерство» · «Данные» (стюард — только «Данные»); «Регион» — запасная группа главврача без mo_code;
 * citizen — верхняя полоса гражданина. Порядок массива — порядок групп в сайдбаре. */
export type NavGroup = 'patients' | 'hospital' | 'ministry' | 'region' | 'common' | 'data' | 'citizen'
export const NAV_GROUPS: readonly NavGroup[] = ['patients', 'hospital', 'ministry', 'region', 'common', 'data']

/** Роли, которым показывается боковой каркас; гражданин (и страница входа) видят верхнюю полосу. */
export function usesSidebar(role: Role | null): boolean {
  return role !== null && role !== 'citizen'
}

declare module 'vue-router' {
  interface RouteMeta {
    /** Роли, которым открыт маршрут; без поля — любому вошедшему (без сессии открыты только `/` и bare). */
    roles?: Role[]
    /** Ключ i18n заголовка страницы (вкладка браузера и заголовок). */
    title?: string
    /** Позиция в меню; без поля маршрут в меню не попадает. */
    nav?: number
    /** Группа навигации: сайдбар персонала (patients/hospital/ministry/common/data) или верхняя полоса гражданина (citizen). */
    group?: NavGroup
    /** Группа для отдельных ролей, если отличается от group (журнал решений: врачу — «Пациенты», главврачу — «Общее»). */
    groupByRole?: Partial<Record<Role, NavGroup>>
    /** Кому показывать пункт в меню; без поля — всем, кому открыт маршрут (roles). */
    navRoles?: Role[]
    /** Ключ i18n короткой подписи пункта меню (в сайдбаре — «Карта», «Ассистент»); без него — title. */
    navTitle?: string
    /** Иконка PrimeIcons пункта меню (свёрнутый сайдбар показывает только её). */
    icon?: string
    /** Страница без навигации приложения (памятка пациенту). */
    bare?: boolean
  }
}
