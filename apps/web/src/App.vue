<script setup lang="ts">
import Button from 'primevue/button'
import Select from 'primevue/select'
import SelectButton from 'primevue/selectbutton'
import Toast from 'primevue/toast'
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { setLocale } from '@/i18n'
import { ROLES, useAuthStore, type Role } from '@/stores/auth'

const { t, locale } = useI18n()
const auth = useAuthStore()

const links = computed(() => {
  const items: { to: string; label: string; roles?: Role[] }[] = [
    { to: '/wait', label: t('nav.wait') },
    { to: '/medicines', label: t('nav.medicines') },
    { to: '/gov', label: t('nav.gov'), roles: ['chief', 'regulator'] },
    { to: '/gov/simulator', label: t('nav.simulator'), roles: ['regulator'] },
    { to: '/gov/insight', label: t('nav.insight'), roles: ['chief', 'regulator'] },
    { to: '/doctor/referral', label: t('nav.referral'), roles: ['doctor'] },
    { to: '/doctor/worklist', label: t('nav.worklist'), roles: ['doctor'] },
    { to: '/doctor/decisions', label: t('nav.decisions'), roles: ['doctor', 'regulator'] },
    { to: '/doctor/scribe', label: t('nav.scribe'), roles: ['doctor'] },
    { to: '/steward', label: t('nav.steward'), roles: ['steward'] },
  ]
  return items.filter((item) => !item.roles || auth.hasRole(...item.roles))
})

const roleOptions = ROLES.map((role: Role) => ({ label: role, value: role }))
const localeOptions = [
  { label: 'RU', value: 'ru' },
  { label: 'KK', value: 'kk' },
]

function onLocale(value: 'ru' | 'kk' | null) {
  if (value) setLocale(value)
}
</script>

<template>
  <div class="shell">
    <header class="topbar">
      <div class="inner">
        <RouterLink class="brand" to="/">Darumen Health</RouterLink>
        <nav>
          <RouterLink v-for="link in links" :key="link.to" :to="link.to">{{ link.label }}</RouterLink>
        </nav>
        <span class="spacer" />
        <SelectButton :model-value="locale" :options="localeOptions" option-label="label" option-value="value" size="small" @update:model-value="onLocale" />
        <template v-if="auth.mode === 'headers'">
          <Select
            :model-value="auth.role"
            :options="roleOptions"
            option-label="label"
            option-value="value"
            :placeholder="t('auth.role')"
            show-clear
            size="small"
            data-testid="role-select"
            @update:model-value="auth.setDemoRole($event)"
          />
          <span class="muted">{{ auth.actor ?? t('auth.guest') }} · {{ t('auth.demo') }}</span>
        </template>
        <template v-else>
          <span class="muted">{{ auth.actor ?? t('auth.guest') }}</span>
          <Button v-if="!auth.isAuthenticated" :label="t('auth.login')" size="small" @click="auth.login()" />
          <Button v-else :label="t('auth.logout')" size="small" severity="secondary" @click="auth.logout()" />
        </template>
      </div>
    </header>
    <Toast />
    <RouterView />
    <footer class="footer">Darumen Health · GovTech Camp 2026 · данные МЗ РК, I квартал 2025 и история ЭРСБ с 2012</footer>
  </div>
</template>
