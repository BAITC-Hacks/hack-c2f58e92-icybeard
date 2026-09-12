import Keycloak from 'keycloak-js'
import { defineStore } from 'pinia'
import { computed, ref } from 'vue'

export type Role = 'citizen' | 'doctor' | 'chief' | 'regulator' | 'steward' | 'admin'
export const ROLES: Role[] = ['citizen', 'doctor', 'chief', 'regulator', 'steward', 'admin']

/** Демо-пользователи режима заголовков; совпадают с пользователями реалма Keycloak. */
export const DEMO_USERS: Record<Role, { actor: string; region?: string }> = {
  citizen: { actor: 'citizen1' },
  doctor: { actor: 'doctor1', region: '75' },
  chief: { actor: 'chief1', region: '75' },
  regulator: { actor: 'regulator1' },
  steward: { actor: 'steward1' },
  admin: { actor: 'admin1' },
}

const STORAGE_KEY = 'darumen.role'

function isRole(value: unknown): value is Role {
  return typeof value === 'string' && (ROLES as string[]).includes(value)
}

function readStorage(): Role | null {
  try {
    const saved = localStorage.getItem(STORAGE_KEY)
    return isRole(saved) ? saved : null
  } catch {
    return null
  }
}

function writeStorage(role: Role | null) {
  try {
    if (role) localStorage.setItem(STORAGE_KEY, role)
    else localStorage.removeItem(STORAGE_KEY)
  } catch {
    // приватный режим браузера: роль не сохраняется
  }
}

export const useAuthStore = defineStore('auth', () => {
  const mode = ref<'headers' | 'keycloak'>(import.meta.env.VITE_AUTH_MODE === 'keycloak' ? 'keycloak' : 'headers')
  const actor = ref<string | null>(null)
  const roles = ref<Role[]>([])
  const region = ref<string | null>(null)
  let keycloak: Keycloak | null = null

  const isAuthenticated = computed(() => actor.value !== null)
  const role = computed<Role | null>(() => roles.value[0] ?? null)

  function hasRole(...allowed: Role[]): boolean {
    return roles.value.includes('admin') || roles.value.some((r) => allowed.includes(r))
  }

  function readToken() {
    const parsed = (keycloak?.tokenParsed ?? {}) as { preferred_username?: string; realm_access?: { roles?: string[] }; region_kato?: string }
    actor.value = parsed.preferred_username ?? null
    roles.value = (parsed.realm_access?.roles ?? []).filter(isRole)
    region.value = parsed.region_kato ?? null
  }

  async function init() {
    if (mode.value === 'headers') {
      setDemoRole(readStorage())
      return
    }
    keycloak = new Keycloak({
      url: import.meta.env.VITE_KEYCLOAK_URL ?? 'http://localhost:8080',
      realm: import.meta.env.VITE_KEYCLOAK_REALM ?? 'darumen',
      clientId: import.meta.env.VITE_KEYCLOAK_CLIENT ?? 'darumen-web',
    })
    try {
      // тихая проверка сессии через iframe со статической страницей, иначе keycloak-js делает полный редирект
      // и оставляет в адресе #error=login_required, который потом ломает разбор кода авторизации
      const authenticated = await keycloak.init({
        onLoad: 'check-sso',
        silentCheckSsoRedirectUri: `${window.location.origin}/silent-check-sso.html`,
        pkceMethod: 'S256',
        checkLoginIframe: false,
      })
      if (authenticated) readToken()
      if (window.location.hash.includes('error=') || window.location.hash.includes('state=')) {
        window.history.replaceState(null, '', window.location.pathname + window.location.search)
      }
    } catch (error) {
      console.warn('Keycloak недоступен, вход отключён', error)
    }
  }

  function setDemoRole(next: Role | null) {
    if (!next) {
      actor.value = null
      roles.value = []
      region.value = null
      writeStorage(null)
      return
    }
    const user = DEMO_USERS[next]
    actor.value = user.actor
    roles.value = [next]
    region.value = user.region ?? null
    writeStorage(next)
  }

  /** Домашний экран роли: гражданин → ожидание, врач → рабочий список, главврач → свой регион, регулятор → карта, стюард → консоль. */
  function roleHome(): string {
    switch (role.value) {
      case 'citizen':
        return '/wait'
      case 'doctor':
        return '/doctor/worklist'
      case 'chief':
        return region.value ? `/gov/regions/${region.value}` : '/gov'
      case 'regulator':
      case 'admin':
        return '/gov'
      case 'steward':
        return '/steward'
      default:
        return '/'
    }
  }

  /** Куда вернуться после входа: на страницу, с которой отправили домой из-за роли, иначе на текущую. */
  function returnPath(): string {
    const denied = new URLSearchParams(window.location.search).get('denied')
    return denied && denied.startsWith('/') && !denied.startsWith('//') ? denied : window.location.pathname
  }

  async function login() {
    if (mode.value === 'keycloak') await keycloak?.login({ redirectUri: window.location.origin + returnPath() })
  }

  async function logout() {
    if (mode.value === 'keycloak') await keycloak?.logout({ redirectUri: window.location.origin })
    else setDemoRole(null)
  }

  /** Заголовки для API: Bearer из Keycloak (с обновлением) или X-Actor/X-Role/X-Region. */
  async function authHeaders(): Promise<Record<string, string>> {
    if (mode.value === 'keycloak') {
      if (!keycloak?.token) return {}
      try {
        await keycloak.updateToken(30)
        readToken()
      } catch {
        return {}
      }
      return { Authorization: `Bearer ${keycloak.token}` }
    }
    if (!actor.value) return {}
    const headers: Record<string, string> = { 'X-Actor': actor.value, 'X-Role': roles.value.join(',') }
    if (region.value) headers['X-Region'] = region.value
    return headers
  }

  return { mode, actor, roles, role, region, isAuthenticated, hasRole, init, setDemoRole, roleHome, login, logout, authHeaders }
})
