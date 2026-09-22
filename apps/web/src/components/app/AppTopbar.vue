<script setup lang="ts">
import Button from 'primevue/button'
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRouter } from 'vue-router'
import LocaleSwitch from './LocaleSwitch.vue'
import ThemeToggle from './ThemeToggle.vue'
import { useAuthStore } from '@/stores/auth'

const { t } = useI18n()
const auth = useAuthStore()
const router = useRouter()

/** Меню — из маршрутов с meta.nav, доступных ролям пользователя; порядок задаёт meta.nav. */
const links = computed(() =>
  router
    .getRoutes()
    .filter((r) => r.meta.nav !== undefined && r.meta.title !== undefined && (!r.meta.roles || auth.hasRole(...r.meta.roles)))
    .sort((a, b) => (a.meta.nav ?? 0) - (b.meta.nav ?? 0))
    .map((r) => ({ to: r.path, label: t(r.meta.title ?? '') })),
)
</script>

<template>
  <header class="topbar">
    <div class="inner">
      <RouterLink class="brand" to="/">Darumen Health</RouterLink>
      <nav>
        <RouterLink v-for="link in links" :key="link.to" :to="link.to">{{ link.label }}</RouterLink>
      </nav>
      <span class="spacer" />
      <LocaleSwitch />
      <ThemeToggle />
      <template v-if="auth.isAuthenticated">
        <span class="muted" data-testid="user-chip">
          {{ auth.actor }}<template v-if="auth.role"> · {{ t('decision.role.' + auth.role) }}</template>
        </span>
        <Button :label="t('auth.logout')" size="small" severity="secondary" data-testid="logout" @click="auth.logout()" />
      </template>
      <span v-else-if="auth.keycloakUnavailable" class="muted">{{ t('auth.unavailable') }}</span>
      <Button v-else :label="t('auth.login')" size="small" data-testid="login-topbar" @click="auth.login()" />
    </div>
  </header>
</template>
