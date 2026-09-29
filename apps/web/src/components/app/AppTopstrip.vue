<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import { useAuthStore } from '@/stores/auth'
import LocaleSwitch from './LocaleSwitch.vue'
import NotificationBell from './NotificationBell.vue'
import ThemeToggle from './ThemeToggle.vue'

/** Верхняя полоса кабинета (components.md): высота 60, белая, разделитель снизу; справа — колокольчик,
 * локаль, кнопка темы, чип пользователя (ссылка на профиль) и «Выйти». На телефоне полосу заменяет mobilebar
 * с drawer-версией сайдбара (там те же элементы в подвале навигации). Логика — та же, что была в подвале сайдбара. */
const { t } = useI18n()
const auth = useAuthStore()
</script>

<template>
  <header class="topstrip">
    <span class="spacer" />
    <NotificationBell />
    <LocaleSwitch surface="soft" />
    <ThemeToggle />
    <RouterLink class="user-chip" to="/account/profile" :title="t('nav.accountProfile')" data-testid="user-chip">
      <i class="pi pi-user" aria-hidden="true" /><span class="user-name">{{ auth.actor }}</span>
    </RouterLink>
    <button type="button" class="logout" :title="t('auth.logout')" data-testid="logout" @click="auth.logout()">
      <i class="pi pi-sign-out" aria-hidden="true" /><span class="visually-hidden">{{ t('auth.logout') }}</span>
    </button>
  </header>
</template>

<style scoped>
.topstrip { height: var(--topstrip-h); flex: none; display: flex; align-items: center; gap: 10px; padding: 0 28px; background: var(--surface); border-bottom: 1px solid var(--border); box-sizing: border-box; }
.spacer { flex: 1; }
.user-chip { display: inline-flex; align-items: center; gap: 8px; height: 36px; padding: 0 14px; border-radius: var(--radius-pill); background: var(--surface-muted); color: var(--text); font-size: var(--fs-base-sm); font-weight: var(--fw-bold); text-decoration: none; max-width: 260px; }
.user-chip .pi { font-size: 13px; color: var(--text-secondary); }
.user-name { overflow: hidden; white-space: nowrap; text-overflow: ellipsis; }
.logout { display: inline-flex; align-items: center; justify-content: center; width: 32px; height: 32px; border: 0; border-radius: 50%; background: transparent; color: var(--text-muted); cursor: pointer; }
.logout:hover { background: var(--danger-bg); color: var(--danger-strong); }
.visually-hidden { position: absolute; width: 1px; height: 1px; margin: -1px; overflow: hidden; clip: rect(0 0 0 0); white-space: nowrap; }
@media (max-width: 640px) { .topstrip { display: none; } }
</style>
