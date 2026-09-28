<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import { useServiceStatusStore } from '@/stores/serviceStatus'

/** Баннер каркаса вошедшего пользователя, тон attention: почтовый сервер недоступен (GET /public/service-status) —
 * приглашения, сброс пароля и уведомления по почте не уходят. «Скрыть» действует до конца сессии браузера
 * (sessionStorage); в новой сессии баннер вернётся, если почта всё ещё недоступна. */
const { t } = useI18n()
const status = useServiceStatusStore()
</script>

<template>
  <div v-if="status.emailBannerVisible" class="outage" role="status" data-testid="email-outage-banner">
    <span class="outage-icon" aria-hidden="true"><i class="pi pi-envelope" /></span>
    <p class="outage-text">{{ t('serviceStatus.emailBanner') }}</p>
    <button type="button" class="outage-close" :aria-label="t('serviceStatus.dismiss')" :title="t('serviceStatus.dismiss')" data-testid="email-outage-dismiss" @click="status.dismissEmailBanner()">
      <i class="pi pi-times" aria-hidden="true" />
    </button>
  </div>
</template>

<style scoped>
/* ширина и поля — как у .page в обоих каркасах (base.css), чтобы баннер стоял ровно над содержимым страницы */
.outage { display: flex; align-items: center; gap: 12px; box-sizing: border-box; width: min(1200px, 100% - 48px); margin: 16px auto 0; padding: 10px 12px 10px 16px; border-radius: var(--dm-radius-md); background: var(--dm-warn-soft); color: var(--dm-ink); font-size: var(--dm-text-sm); }
.shell--side .outage { width: auto; max-width: 1360px; margin: 24px 40px 0; }
.outage-icon { width: 28px; height: 28px; border-radius: 50%; display: grid; place-items: center; flex: none; background: var(--dm-surface); color: var(--dm-warn-strong); }
.outage-text { flex: 1; min-width: 0; margin: 0; line-height: 1.45; }
.outage-close { width: 32px; height: 32px; flex: none; display: grid; place-items: center; border: 0; border-radius: 50%; background: transparent; color: var(--dm-warn); cursor: pointer; }
.outage-close:hover { background: var(--dm-surface); }
.outage-close:focus-visible { outline: 2px solid var(--dm-accent); outline-offset: 2px; }
@media (max-width: 1100px) { .shell--side .outage { margin: 16px 24px 0; } }
@media (max-width: 640px) { .outage, .shell--side .outage { width: auto; margin: 12px 16px 0; } }
</style>
