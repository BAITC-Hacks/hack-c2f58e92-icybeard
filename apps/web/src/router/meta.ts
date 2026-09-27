import type { PermissionCode } from '@/lib/permissions'

/** Группы навигации: сайдбар персонала (patients · hospital · ministry · admin · data · account) и верхняя полоса
 * гражданина (citizen). Порядок SIDEBAR_GROUPS в lib/nav.ts — порядок групп в сайдбаре. */
export type NavGroup = 'patients' | 'hospital' | 'ministry' | 'admin' | 'data' | 'account' | 'citizen'

declare module 'vue-router' {
  interface RouteMeta {
    /** Разрешение маршрута (docs/rbac.md); массив — любое из списка. Без поля — любому вошедшему. */
    permission?: PermissionCode | PermissionCode[]
    /** Страница без сессии: регистрация организации, приглашение (свой минимальный каркас). */
    public?: boolean
    /** Страница без навигации приложения и без сессии (памятка пациенту по QR). */
    bare?: boolean
    /** Ключ i18n заголовка страницы (вкладка браузера и заголовок). */
    title?: string
    /** Позиция в меню; без поля маршрут в меню не попадает. */
    nav?: number
    /** Группа навигации пункта. */
    group?: NavGroup
    /** Другая группа (и подпись), если есть любое из разрешений: журнал решений у врача — «Пациенты», консоль стюарда
     * у администратора — «Данные» в «Администрировании». */
    groupWhen?: { any: PermissionCode[]; group: NavGroup; navTitle?: string }
    /** Разрешение, при котором маршрут виден в меню, если оно уже, чем доступ к нему (качество моделей открыто и
     * ассистенту направления, но в меню — только у gov.map). */
    navPermission?: PermissionCode
    /** Ключ i18n короткой подписи пункта меню; без него — title. */
    navTitle?: string
    /** Иконка PrimeIcons пункта меню (свёрнутый сайдбар показывает только её). */
    icon?: string
  }
}
