<script setup lang="ts">
import BrandMark from '@/components/app/BrandMark.vue'
import Button from 'primevue/button'
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRouter } from 'vue-router'
import LocaleSwitch from './LocaleSwitch.vue'
import ThemeToggle from './ThemeToggle.vue'
import { useAuthStore } from '@/stores/auth'

/** Верхняя полоса гражданина: три пункта (Мой путь · Сколько ждут · Проверка рецепта), язык, тема, выход. До входа —
 * только знак, язык, тема и «Войти»: без сессии пункты меню всё равно ведут на страницу входа. */
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
      <RouterLink class="brand" to="/"><BrandMark :size="26" /><span>Darumen Health</span></RouterLink>
      <nav>
        <RouterLink v-for="link in links" :key="link.to" :to="link.to">{{ link.label }}</RouterLink>
      </nav>
      <span class="spacer" />
      <LocaleSwitch />
      <ThemeToggle />
      <template v-if="auth.isAuthenticated">
        <span class="muted user" data-testid="user-chip">
          {{ auth.actor }}<template v-if="auth.role"> · {{ t('decision.role.' + auth.role) }}</template>
        </span>
        <Button :label="t('auth.logout')" size="small" severity="secondary" data-testid="logout" @click="auth.logout()" />
      </template>
      <span v-else-if="auth.keycloakUnavailable" class="muted">{{ t('auth.unavailable') }}</span>
      <Button v-else :label="t('auth.login')" size="small" data-testid="login-topbar" @click="auth.login()" />
    </div>
  </header>
</template>

<style scoped>
.topbar .inner { width: min(960px, 100% - 32px); }
.user { font-size: 0.9rem; }
@media (max-width: 640px) { .user { display: none; } }
</style>
