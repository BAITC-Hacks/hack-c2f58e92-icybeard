/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_KEYCLOAK_URL?: string
  readonly VITE_KEYCLOAK_REALM?: string
  readonly VITE_KEYCLOAK_CLIENT?: string
  /** 'true' — кнопка «Войти через eGov mobile» ведёт в брокер realm (idpHint egov), иначе на экран «Скоро». */
  readonly VITE_EGOV_ENABLED?: string
  readonly VITE_API_BASE?: string
  readonly VITE_MAP_STYLE?: string
  /** Стиль тайлов для тёмной темы; пусто — светлый стиль затемняется CSS-фильтром. */
  readonly VITE_MAP_STYLE_DARK?: string
}
