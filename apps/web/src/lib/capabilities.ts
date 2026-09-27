import type { PermissionCode } from './permissions'

/** «Что умеет кабинет» (W-Onboarding): возможности по разрешениям, в порядке важности; иконка и ключи i18n
 * welcome.can.<key>.title / .text. Показываются только те, на которые у пользователя есть разрешение. */
export interface Capability { key: string; permission: PermissionCode; icon: string; to: string }

export const CAPABILITIES: readonly Capability[] = [
  { key: 'worklist', permission: 'worklist.view', icon: 'pi pi-list', to: '/doctor/worklist' },
  { key: 'referral', permission: 'referral.assist', icon: 'pi pi-compass', to: '/doctor/referral' },
  { key: 'scribe', permission: 'scribe.use', icon: 'pi pi-microphone', to: '/doctor/scribe' },
  { key: 'decisions', permission: 'decisions.own', icon: 'pi pi-file', to: '/doctor/decisions' },
  { key: 'decisionsAll', permission: 'decisions.all', icon: 'pi pi-file', to: '/doctor/decisions' },
  { key: 'cabinet', permission: 'org.cabinet', icon: 'pi pi-building', to: '' },
  { key: 'map', permission: 'gov.map', icon: 'pi pi-map', to: '/gov' },
  { key: 'simulator', permission: 'gov.simulator', icon: 'pi pi-sliders-h', to: '/gov/simulator' },
  { key: 'insight', permission: 'insight.ask', icon: 'pi pi-comments', to: '/gov/insight' },
  { key: 'steward', permission: 'data.steward', icon: 'pi pi-database', to: '/steward' },
  { key: 'users', permission: 'admin.users', icon: 'pi pi-users', to: '/admin/users' },
  { key: 'roles', permission: 'admin.roles', icon: 'pi pi-shield', to: '/admin/roles' },
  { key: 'orgs', permission: 'admin.orgs', icon: 'pi pi-building', to: '/admin/orgs' },
  { key: 'route', permission: 'route.own', icon: 'pi pi-map-marker', to: '/me/route' },
  { key: 'medicines', permission: 'medicines.check', icon: 'pi pi-check-circle', to: '/medicines' },
  { key: 'wait', permission: 'wait.public', icon: 'pi pi-clock', to: '/wait' },
]

/** Возможности пользователя: без повторов журнала решений (свои/все), не больше `limit`. */
export function capabilitiesFor(can: (code: string) => boolean, limit = 4): Capability[] {
  const allowed = CAPABILITIES.filter((c) => can(c.permission))
  const withoutDuplicate = allowed.some((c) => c.key === 'decisions') ? allowed.filter((c) => c.key !== 'decisionsAll') : allowed
  return withoutDuplicate.slice(0, limit)
}
