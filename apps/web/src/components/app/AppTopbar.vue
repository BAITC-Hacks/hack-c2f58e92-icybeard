<script setup lang="ts">
import Button from 'primevue/button'
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRouter } from 'vue-router'
import BrandMark from '@/components/app/BrandMark.vue'
import LocaleSwitch from './LocaleSwitch.vue'
import ThemeToggle from './ThemeToggle.vue'
import { useAuthStore } from '@/stores/auth'

/** Верхняя полоса гражданина (W-Home): 72 px, прозрачная на ground; слева знак + «darumen», по центру белая
 * пилюля-контейнер с пунктами (Мой путь · Сколько ждут · Проверка рецепта; активный ink/белый), справа RU/KK,
 * тема и «Войти»/«Выйти». До входа пунктов нет: без сессии открыта только страница входа. */
const { t } = useI18n()
const auth = useAuthStore()
const router = useRouter()

const links = computed(() =>
  auth.isAuthenticated
    ? router
        .getRoutes()
        // вместо «Главная» — «Мой путь»: главная и так уводит на домашний экран роли
        .filter((r) => r.name !== 'home' && r.meta.group === 'citizen' && r.meta.nav !== undefined && r.meta.title !== undefined && (!r.meta.roles || auth.hasRole(...r.meta.roles)))
        .sort((a, b) => (a.meta.nav ?? 0) - (b.meta.nav ?? 0))
        .map((r) => ({ to: r.path, label: t(r.meta.navTitle ?? r.meta.title ?? '') }))
    : [],
)
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
        <span class="muted small user" data-testid="user-chip">
          {{ auth.actor }}<template v-if="auth.role"> · {{ t('nav.affiliation.' + auth.role) }}</template>
        </span>
        <Button :label="t('auth.logout')" class="session-button" data-testid="logout" @click="auth.logout()" />
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
.pill:hover { background: var(--dm-surface-2); color: var(--dm-ink); }
.pill.active { background: var(--dm-ink); color: var(--dm-surface); }
.session-button { min-height: 40px; height: 40px; padding: 0 20px; }
.session-button :deep(.p-button-label) { font-size: var(--dm-text-sm); }
@media (max-width: 900px) { .pills { order: 10; flex-basis: 100%; justify-content: center; } .spacer { display: none; } .brand { margin-right: auto; } }
@media (max-width: 640px) { .user { display: none; } .inner { width: min(1200px, 100% - 32px); } }
</style>
