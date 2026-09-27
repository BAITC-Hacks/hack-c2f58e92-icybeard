<script setup lang="ts">
import Message from 'primevue/message'
import { ApiError } from '@/api/client'
import StateNoAccess from '@/components/states/StateNoAccess.vue'
import { isForbidden } from '@/lib/support'

/** Сообщение об ошибке запроса. 403 от API на любой странице — состояние «Нет доступа к разделу» с запросом доступа
 * (docs/rbac.md: проверки на клиенте — только UX, отказ API показывается как «Нет доступа»). */
defineProps<{ error: unknown }>()

function describe(error: unknown): string {
  if (error instanceof ApiError) {
    const fields = error.errors ? Object.entries(error.errors).map(([k, v]) => `${k}: ${v.join(', ')}`).join('; ') : ''
    return [error.title, error.detail, fields].filter(Boolean).join(' — ')
  }
  return error instanceof Error ? error.message : String(error)
}
</script>

<template>
  <div v-if="isForbidden(error)" class="card no-access"><StateNoAccess :detail="error.detail" :permissions="error.permissions" compact /></div>
  <Message v-else-if="error" severity="error" :closable="false">{{ describe(error) }}</Message>
</template>

<style scoped>
.no-access { padding: 0; }
</style>
