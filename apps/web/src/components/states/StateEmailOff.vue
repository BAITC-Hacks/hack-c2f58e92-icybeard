<script setup lang="ts">
import { useServiceStatusStore } from '@/stores/serviceStatus'

/** Почта недоступна (GET /public/service-status) — пояснение там, где система отправила бы письмо: приглашение, код
 * подтверждения, решение по заявке. Тон attention. Почта доступна или статус неизвестен — ничего не показывает. */
defineProps<{ text: string }>()
const status = useServiceStatusStore()
</script>

<template>
  <div v-if="status.emailUnavailable" class="email-off" role="note" data-testid="email-off">
    <i class="pi pi-envelope" aria-hidden="true" />
    <span>{{ text }}</span>
  </div>
</template>

<style scoped>
.email-off { display: flex; align-items: flex-start; gap: 10px; padding: 12px 16px; border-radius: var(--dm-radius-md); background: var(--dm-warn-soft); color: var(--dm-ink); font-size: var(--dm-text-sm); line-height: 1.45; }
.email-off i { color: var(--dm-warn-strong); margin-top: 2px; }
</style>
