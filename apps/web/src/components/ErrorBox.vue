<script setup lang="ts">
import Message from 'primevue/message'
import { ApiError } from '@/api/client'

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
  <Message v-if="error" severity="error" :closable="false">{{ describe(error) }}</Message>
</template>
