import Keycloak from 'keycloak-js'
import { defineStore } from 'pinia'
import { computed, ref } from 'vue'
import { isRole, roleHome as homeOf, type Role } from '@/router/roles'

export type { Role } from '@/router/roles'

/** Клеймы токена, которые читает клиент; region_kato — атрибут пользователя (маппер клиента darumen-web в realm). */
interface TokenClaims {
  preferred_username?: string
  realm_access?: { roles?: string[] }
  region_kato?: string
}

export const useAuthStore = defineStore('auth', () => {
  const actor = ref<string | null>(null)
  const roles = ref<Role[]>([])
  const region = ref<string | null>(null)
  /** Keycloak не ответил при старте: вместо кнопки входа — подпись, публичные страницы работают. */
  const keycloakUnavailable = ref(false)
  let keycloak: Keycloak | null = null

  const isAuthenticated = computed(() => actor.value !== null)
  const role = computed<Role | null>(() => roles.value[0] ?? null)

  function hasRole(...allowed: Role[]): boolean {
    return roles.value.includes('admin') || roles.value.some((r) => allowed.includes(r))
  }

  function readToken() {
    const parsed = (keycloak?.tokenParsed ?? {}) as TokenClaims
    actor.value = parsed.preferred_username ?? null
    roles.value = (parsed.realm_access?.roles ?? []).filter(isRole)
    region.value = parsed.region_kato ?? null
  }

  const url: string = import.meta.env.VITE_KEYCLOAK_URL ?? 'http://localhost:8080'
  const realm: string = import.meta.env.VITE_KEYCLOAK_REALM ?? 'darumen'

  /** Отвечает ли realm: публичное описание realm с коротким таймаутом (без cookies и iframe). */
  async function realmReachable(): Promise<boolean> {
    try {
      const signal = typeof AbortSignal.timeout === 'function' ? AbortSignal.timeout(5000) : undefined
      return (await fetch(`${url}/realms/${realm}`, { signal })).ok
    } catch {
      return false
    }
  }

  async function init() {
    keycloak = new Keycloak({ url, realm, clientId: import.meta.env.VITE_KEYCLOAK_CLIENT ?? 'darumen-web' })
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
      // init падает и когда сервер входа не отвечает, и когда тихую проверку сессии в iframe заблокировал прокси
      // (X-Frame-Options/CSP на хостовом Caddy): во втором случае вход по кнопке — полный редирект — работает,
      // поэтому кнопку гасим только если сам realm не отвечает
      keycloakUnavailable.value = !(await realmReachable())
      console.warn(
        keycloakUnavailable.value ? 'Keycloak недоступен, вход отключён' : 'Тихая проверка сессии Keycloak не прошла (iframe заблокирован?), вход по кнопке доступен',
        error,
      )
    }
  }

  function roleHome(): string {
    return homeOf(role.value, region.value)
  }

  /** Куда вернуться после входа: на страницу, с которой отправили домой из-за роли, иначе на текущую. */
  function returnPath(): string {
    const denied = new URLSearchParams(window.location.search).get('denied')
    return denied && denied.startsWith('/') && !denied.startsWith('//') ? denied : window.location.pathname
  }

  /** Вход через Keycloak (PKCE). idpHint — брокер realm (например eGov), когда он настроен: docs/egov-auth.md. */
  async function login(options: { idpHint?: string } = {}) {
    await keycloak?.login({ redirectUri: window.location.origin + returnPath(), ...options })
  }

  async function logout() {
    await keycloak?.logout({ redirectUri: window.location.origin })
  }

  /** Заголовки для API: Bearer из Keycloak с обновлением токена; без сессии — пусто (публичные эндпоинты). */
  async function authHeaders(): Promise<Record<string, string>> {
    if (!keycloak?.token) return {}
    try {
      await keycloak.updateToken(30)
      readToken()
    } catch {
      return {}
    }
    return { Authorization: `Bearer ${keycloak.token}` }
  }

  return { actor, roles, role, region, isAuthenticated, keycloakUnavailable, hasRole, init, roleHome, login, logout, authHeaders }
})
