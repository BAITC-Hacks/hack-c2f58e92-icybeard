import Keycloak from 'keycloak-js'
import { defineStore } from 'pinia'
import { computed, ref } from 'vue'
import { account } from '@/api/endpoints'
import type { MeResponse } from '@/api/types'
import { i18n } from '@/i18n'
import {
  homePath, normalizeRoles, permissionsForRoles, primaryRole, scopeIn, usesSidebar as sidebarFor, type Permission, type RoleKey, type Scope,
} from '@/lib/permissions'

export type { RoleKey as Role } from '@/lib/permissions'

/** Клеймы токена, которые читает клиент; region_kato и mo_code — атрибуты пользователя (мапперы клиента darumen-web
 * в realm); mo_code есть у врача и администратора организации и может отсутствовать — тогда null. */
interface TokenClaims {
  preferred_username?: string
  name?: string
  given_name?: string
  email?: string
  realm_access?: { roles?: string[] }
  region_kato?: string
  mo_code?: string
}

/** Сколько ждать `/me` перед первой навигацией: дольше — роутер стартует на разрешениях из токена. */
const ME_TIMEOUT_MS = 5000
/** Признак «экран „Первый вход“ уже показан» — по пользователю, в localStorage. */
const WELCOME_KEY = 'darumen.welcome.'

export const useAuthStore = defineStore('auth', () => {
  const actor = ref<string | null>(null)
  const roles = ref<RoleKey[]>([])
  const region = ref<string | null>(null)
  /** Код организации (клейм mo_code / `/me.moCode`) — scope `own`, домашний экран и кабинет организации. */
  const moCode = ref<string | null>(null)
  const displayName = ref<string | null>(null)
  /** Имя для приветствия («Добро пожаловать, Асель») — клейм given_name. */
  const givenName = ref<string | null>(null)
  const email = ref<string | null>(null)
  /** Ответ `GET /me`; null — эндпоинт ещё не ответил или недоступен (тогда разрешения — из матрицы по ролям токена). */
  const me = ref<MeResponse | null>(null)
  /** Откуда разрешения: `token` — фолбэк по матрице docs/rbac.md, `api` — из `/me`. */
  const permissionSource = ref<'token' | 'api'>('token')
  const permissions = ref<Permission[]>([])
  /** Keycloak не ответил при старте: вместо кнопки входа — подпись на странице входа. */
  const keycloakUnavailable = ref(false)
  let keycloak: Keycloak | null = null

  const isAuthenticated = computed(() => actor.value !== null)
  const role = computed<RoleKey | null>(() => primaryRole(roles.value))
  const sidebar = computed(() => isAuthenticated.value && sidebarFor(permissions.value))

  /** Действующий scope разрешения: `own` без организации пуст; admin проходит всё. */
  function scopeOf(code: string): Scope | null {
    if (roles.value.includes('admin')) return 'all'
    return scopeIn(permissions.value, code, moCode.value)
  }
  function can(code: string): boolean {
    return scopeOf(code) !== null
  }
  function canAny(codes: readonly string[]): boolean {
    return codes.length === 0 || codes.some(can)
  }

  function readToken() {
    const parsed = (keycloak?.tokenParsed ?? {}) as TokenClaims
    actor.value = parsed.preferred_username ?? null
    if (permissionSource.value === 'api') return
    roles.value = normalizeRoles(parsed.realm_access?.roles)
    region.value = parsed.region_kato ?? null
    moCode.value = parsed.mo_code || null
    displayName.value = parsed.name ?? null
    givenName.value = parsed.given_name ?? null
    email.value = parsed.email ?? null
    permissions.value = permissionsForRoles(roles.value)
  }

  /** `GET /me`: разрешения, роли и организация с бэкенда. Пока эндпоинта нет (404) или он не ответил — остаётся
   * фолбэк по ролям токена; возвращает, удалось ли загрузить. */
  async function loadMe(): Promise<boolean> {
    if (!isAuthenticated.value) return false
    try {
      const timeout = new Promise<never>((_, reject) => window.setTimeout(() => reject(new Error('me timeout')), ME_TIMEOUT_MS))
      const response = await Promise.race([account.me(), timeout])
      me.value = response
      roles.value = normalizeRoles(response.roles)
      permissions.value = response.permissions.map((p) => ({ code: p.code, scope: p.scope }))
      moCode.value = response.moCode ?? moCode.value
      region.value = response.regionKato ?? region.value
      displayName.value = response.displayName ?? displayName.value
      email.value = response.email ?? email.value
      permissionSource.value = 'api'
      return true
    } catch (error) {
      console.warn('GET /api/v1/me недоступен — разрешения из ролей токена (docs/rbac.md)', error)
      return false
    }
  }

  function welcomeSeen(): boolean {
    try {
      return !actor.value || window.localStorage.getItem(WELCOME_KEY + actor.value) === '1'
    } catch {
      return true
    }
  }
  function markWelcomeSeen() {
    try {
      if (actor.value) window.localStorage.setItem(WELCOME_KEY + actor.value, '1')
    } catch {
      // без storage экран «Первый вход» просто покажется ещё раз
    }
  }

  // Без VITE_KEYCLOAK_URL прод-сборка берёт Keycloak своего origin (nginx стенда проксирует /auth): один образ из CI
  // подходит любому домену стенда. В dev по умолчанию — Keycloak из make serve.
  const url: string =
    import.meta.env.VITE_KEYCLOAK_URL || (import.meta.env.DEV ? 'http://localhost:8080' : `${window.location.origin}/auth`)
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

  /** Признак, что в этом браузере уже входили: только тогда стоит проверять сессию редиректом. Гость без него
   * открывает страницу без перехода в Keycloak (и без второй загрузки, которая обрывала заставку). */
  const SESSION_HINT = 'darumen.session'
  /** Ставится перед любым редиректом в Keycloak: после возврата заставка index.html не запускается второй раз. */
  const BOOT_SKIP = 'darumen.boot.skip'

  function markRedirect() {
    try {
      window.sessionStorage.setItem(BOOT_SKIP, '1')
    } catch {
      // приватный режим без storage — заставка просто сыграет ещё раз
    }
  }

  async function init() {
    keycloak = new Keycloak({ url, realm, clientId: import.meta.env.VITE_KEYCLOAK_CLIENT ?? 'darumen-web' })
    const returning = window.location.hash.includes('state=') || window.location.hash.includes('error=')
    // форма входа Keycloak устарела (вкладку оставили открытой): Keycloak 26 возвращает
    // #error=temporarily_unavailable&error_description=authentication_expired — вход запускается заново молча
    const loginExpired = /(^|[#&])error_description=authentication_expired(&|$)/.test(window.location.hash)
    let authenticatedNow = false
    let hadSession = false
    try {
      hadSession = window.localStorage.getItem(SESSION_HINT) === '1'
    } catch {
      hadSession = false
    }
    try {
      // проверка сессии полным редиректом (prompt=none) без iframe: тихая проверка через iframe и проверка
      // 3p-cookies не переживают X-Frame-Options: DENY / CSP frame-ancestors на прокси стенда. Редирект
      // делаем только тем, кто уже входил в этом браузере, или при возврате из Keycloak; кто не входил, остаётся на
      // странице входа без перехода. #error=login_required keycloak-js убирает из адреса сам
      const checkSession = returning || hadSession
      if (checkSession && !returning) markRedirect()
      const authenticated = await keycloak.init({
        ...(checkSession ? { onLoad: 'check-sso' as const } : {}),
        pkceMethod: 'S256',
        checkLoginIframe: false,
      })
      authenticatedNow = authenticated
      if (authenticated) readToken()
      try {
        if (authenticated) window.localStorage.setItem(SESSION_HINT, '1')
        else if (returning) window.localStorage.removeItem(SESSION_HINT)
      } catch {
        // без storage признак просто не сохраняется
      }
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
    if (loginExpired && !authenticatedNow && !keycloakUnavailable.value) {
      if (window.location.hash) window.history.replaceState(null, '', window.location.pathname + window.location.search)
      await login()
    }
  }

  /** Домашний экран по разрешениям (docs/rbac.md); без сессии — страница входа. */
  function roleHome(): string {
    return isAuthenticated.value ? homePath({ can, moCode: moCode.value }) : '/'
  }

  /** Куда вести с `/` после входа: при первом входе — «Первый вход», затем — домашний экран. */
  function landing(): string {
    if (!isAuthenticated.value) return '/'
    return welcomeSeen() ? roleHome() : '/welcome'
  }

  /** Куда вернуться после входа: на страницу, с которой отправили домой из-за роли, иначе на текущую. */
  function returnPath(): string {
    const denied = new URLSearchParams(window.location.search).get('denied')
    return denied && denied.startsWith('/') && !denied.startsWith('//') ? denied : window.location.pathname
  }

  /** Вход через Keycloak (PKCE). idpHint — брокер realm (например eGov), когда он настроен: docs/egov-auth.md. */
  async function login(options: { idpHint?: string } = {}) {
    markRedirect()
    // страница входа Keycloak (тема darumen) открывается на языке интерфейса
    await keycloak?.login({ redirectUri: window.location.origin + returnPath(), locale: String(i18n.global.locale.value), ...options })
  }

  /** Действие Keycloak (kc_action): смена пароля или настройка приложения-аутентификатора; возврат на текущую страницу. */
  async function accountAction(action: 'UPDATE_PASSWORD' | 'CONFIGURE_TOTP') {
    markRedirect()
    await keycloak?.login({ action, redirectUri: window.location.href, locale: String(i18n.global.locale.value) })
  }

  /** Запрос доступа к разделу: пишется в аудит и виден администратору организации/системы. */
  async function requestAccess(permission: string, path: string, comment?: string) {
    await account.requestAccess({ permission, path, ...(comment ? { comment } : {}) })
  }

  async function logout() {
    markRedirect()
    try {
      window.localStorage.removeItem(SESSION_HINT)
    } catch {
      // без storage признак и так не хранился
    }
    await keycloak?.logout({ redirectUri: window.location.origin })
  }

  /** Заголовки для API: Bearer из Keycloak с обновлением токена; без сессии — пусто (публичные эндпоинты страницы входа). */
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

  return {
    actor, roles, role, region, moCode, displayName, givenName, email, me, permissions, permissionSource, isAuthenticated, keycloakUnavailable, sidebar,
    scopeOf, can, canAny, init, loadMe, roleHome, landing, welcomeSeen, markWelcomeSeen, login, logout, accountAction, requestAccess, authHeaders,
  }
})
