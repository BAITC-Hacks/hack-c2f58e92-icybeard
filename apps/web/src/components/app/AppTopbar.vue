<script setup lang="ts">
import Button from 'primevue/button'
import Menu from 'primevue/menu'
import { computed, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute, useRouter } from 'vue-router'
import BrandMark from '@/components/app/BrandMark.vue'
import { accountNav, topbarNav } from '@/lib/nav'
import { useAuthStore } from '@/stores/auth'
import LocaleSwitch from './LocaleSwitch.vue'
import ThemeToggle from './ThemeToggle.vue'

/** Шапка гражданина («синяя гамма», components.md): 84 px, белая с разделителем, контейнер 1240; слева знак +
 * «darumen», по центру пункты из разрешений (Мой путь · Сколько ждут · Проверка рецепта) с подчёркиванием активной
 * вкладки, справа RU/KK, тема и меню пользователя (аккаунт, «Выйти»); без сессии — «Войти» (пунктов нет).
 * На главной без входа (home-prop-5) шапка прозрачная — фон даёт градиент каркаса. */
const { t } = useI18n()
const auth = useAuthStore()
const router = useRouter()
const route = useRoute()
const menu = ref<InstanceType<typeof Menu> | null>(null)
/** Прозрачный вариант шапки — только главная без входа (градиент — на .shell--hero). */
const hero = computed(() => route.name === 'home' && !auth.isAuthenticated)

const links = computed(() => (auth.isAuthenticated ? topbarNav(router.getRoutes(), { can: auth.can }).map((i) => ({ to: i.to, label: t(i.labelKey) })) : []))
const accountItems = computed(() => [
  ...accountNav(router.getRoutes()).map((item) => ({ label: t(item.labelKey), icon: item.icon, command: () => router.push(item.to) })),
  { separator: true },
  { label: t('auth.logout'), icon: 'pi pi-sign-out', command: () => auth.logout() },
])
</script>

<template>
  <header class="topbar" :class="{ hero }">
    <div class="inner">
      <RouterLink class="brand" to="/"><BrandMark :size="28" /><span>darumen</span></RouterLink>
      <span class="spacer" />
      <nav v-if="links.length" class="nav-links" :aria-label="t('shell.menu')">
        <RouterLink v-for="link in links" :key="link.to" :to="link.to" class="nav-link" active-class="active">{{ link.label }}</RouterLink>
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
.topbar { background: var(--surface); border-bottom: 1px solid var(--border); }
.topbar.hero { background: transparent; border-bottom: 0; }
.inner { width: min(var(--citizen-container), 100% - 48px); margin: 0 auto; min-height: var(--citizen-header-h); display: flex; align-items: center; gap: 20px; flex-wrap: wrap; }
.brand { display: inline-flex; align-items: center; gap: 10px; text-decoration: none; color: var(--text); font-size: 18px; font-weight: var(--fw-extrabold); letter-spacing: -0.01em; }
.spacer { flex: 1; }
.nav-links { display: flex; gap: 26px; align-self: stretch; }
.nav-link { display: inline-flex; align-items: center; font-size: var(--fs-md); font-weight: var(--fw-bold); color: var(--text-muted); text-decoration: none; white-space: nowrap; border-bottom: 2.5px solid transparent; padding-top: 2.5px; box-sizing: border-box; }
.nav-link:hover { color: var(--text); }
.nav-link.active { color: var(--text); border-bottom-color: var(--accent); }
.user { display: inline-flex; align-items: center; gap: 8px; height: 40px; padding: 0 14px; border: 0; border-radius: var(--radius-pill); background: var(--surface-muted); color: var(--text); font: inherit; font-size: var(--fs-base); font-weight: var(--fw-bold); cursor: pointer; }
.user:hover { background: var(--accent-soft); }
.session-button { min-height: 40px; height: 40px; padding: 0 20px; }
.session-button :deep(.p-button-label) { font-size: var(--fs-base); }
@media (max-width: 900px) { .nav-links { order: 10; flex-basis: 100%; justify-content: center; align-self: auto; } .nav-link { padding-block: 8px 10px; } .spacer { display: none; } .brand { margin-right: auto; } }
@media (max-width: 640px) { .user-name { display: none; } .inner { width: min(var(--citizen-container), 100% - 32px); min-height: 64px; } }
</style>
