<script setup lang="ts">
import Button from 'primevue/button'
import Menu from 'primevue/menu'
import { computed, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRouter } from 'vue-router'
import BrandMark from '@/components/app/BrandMark.vue'
import { accountNav, topbarNav } from '@/lib/nav'
import { useAuthStore } from '@/stores/auth'
import LocaleSwitch from './LocaleSwitch.vue'
import ThemeToggle from './ThemeToggle.vue'

/** Верхняя полоса гражданина (W-Home): 72 px, прозрачная на холсте; слева знак + «darumen», по центру белая
 * пилюля-контейнер с пунктами из разрешений (Мой путь · Сколько ждут · Проверка рецепта; активный фиолетовый/белый),
 * справа RU/KK, тема и меню пользователя (аккаунт, «Выйти»); без сессии — «Войти» (пунктов нет). */
const { t } = useI18n()
const auth = useAuthStore()
const router = useRouter()
const menu = ref<InstanceType<typeof Menu> | null>(null)

const links = computed(() => (auth.isAuthenticated ? topbarNav(router.getRoutes(), { can: auth.can }).map((i) => ({ to: i.to, label: t(i.labelKey) })) : []))
const accountItems = computed(() => [
  ...accountNav(router.getRoutes()).map((item) => ({ label: t(item.labelKey), icon: item.icon, command: () => router.push(item.to) })),
  { separator: true },
  { label: t('auth.logout'), icon: 'pi pi-sign-out', command: () => auth.logout() },
])
</script>

<template>
  <header class="topbar">
    <div class="inner">
      <RouterLink class="brand" to="/"><BrandMark :size="28" /><span>darumen</span></RouterLink>
      <span class="spacer" />
      <nav v-if="links.length" class="pills" :aria-label="t('shell.menu')">
        <RouterLink v-for="link in links" :key="link.to" :to="link.to" class="pill" active-class="active">{{ link.label }}</RouterLink>
      </nav>
      <span class="spacer" />
      <LocaleSwitch />
      <ThemeToggle />
      <template v-if="auth.isAuthenticated">
        <button type="button" class="user" aria-haspopup="true" :aria-label="t('account.menu')" data-testid="user-chip" @click="menu?.toggle($event)">
          <i class="pi pi-user" aria-hidden="true" /><span class="user-name">{{ auth.actor }}</span><i class="pi pi-angle-down" aria-hidden="true" />
        </button>
        <Menu ref="menu" :model="accountItems" popup data-testid="user-menu" />
      </template>
      <span v-else-if="auth.keycloakUnavailable" class="muted small">{{ t('auth.unavailable') }}</span>
      <Button v-else :label="t('auth.login')" class="session-button" data-testid="login-topbar" @click="auth.login()" />
    </div>
  </header>
</template>

<style scoped>
.topbar { background: transparent; }
.inner { width: min(1200px, 100% - 48px); margin: 0 auto; min-height: 72px; display: flex; align-items: center; gap: var(--dm-space-4); flex-wrap: wrap; }
.brand { display: inline-flex; align-items: center; gap: 10px; text-decoration: none; color: var(--dm-ink); font-size: var(--dm-text-lg); font-weight: 600; letter-spacing: -0.02em; }
.spacer { flex: 1; }
.pills { display: flex; gap: 2px; background: var(--dm-surface); border-radius: var(--dm-radius-pill); padding: 4px; }
.pill { padding: 8px 16px; border-radius: var(--dm-radius-pill); font-size: var(--dm-text-sm); font-weight: 500; color: var(--dm-ink); text-decoration: none; white-space: nowrap; }
.pill:hover { background: var(--dm-bg); color: var(--dm-ink); }
.pill.active { background: var(--dm-primary); color: var(--dm-primary-contrast); }
.user { display: inline-flex; align-items: center; gap: 8px; height: 40px; padding: 0 14px; border: 0; border-radius: var(--dm-radius-pill); background: var(--dm-surface); color: var(--dm-ink); font: inherit; font-size: var(--dm-text-sm); font-weight: 500; cursor: pointer; }
.user:hover { background: var(--dm-accent-soft); }
.session-button { min-height: 40px; height: 40px; padding: 0 20px; }
.session-button :deep(.p-button-label) { font-size: var(--dm-text-sm); }
@media (max-width: 900px) { .pills { order: 10; flex-basis: 100%; justify-content: center; } .spacer { display: none; } .brand { margin-right: auto; } }
@media (max-width: 640px) { .user-name { display: none; } .inner { width: min(1200px, 100% - 32px); } }
</style>
