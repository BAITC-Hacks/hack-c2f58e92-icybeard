<script setup lang="ts">
import { useI18n } from 'vue-i18n'

/** Вкладки аккаунта (W-Account-*): пилюли «Профиль · Безопасность · Уведомления · Данные и согласия», активная —
 * фиолетовая с белым текстом, остальные белые. */
const { t } = useI18n()
const tabs = [
  { to: '/account/profile', key: 'profile' },
  { to: '/account/security', key: 'security' },
  { to: '/account/notifications', key: 'notifications' },
  { to: '/account/consents', key: 'consents' },
] as const
</script>

<template>
  <nav class="account-tabs" :aria-label="t('account.menu')">
    <RouterLink v-for="tab in tabs" :key="tab.to" :to="tab.to" class="chip-filter" active-class="active" :data-testid="`account-tab-${tab.key}`">{{ t(`account.tabs.${tab.key}`) }}</RouterLink>
  </nav>
</template>

<style scoped>
.account-tabs { display: flex; flex-wrap: wrap; gap: 8px; }
.account-tabs .chip-filter { text-decoration: none; }
</style>
