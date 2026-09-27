<script setup lang="ts">
/** Пустое состояние: одна фраза, что сделать, и необязательное действие. Иконка — в круге soft 40 px. */
withDefaults(defineProps<{ title: string; text?: string; icon?: string }>(), { icon: 'pi pi-inbox' })
</script>

<template>
  <div class="empty">
    <span class="icon-wrap"><i :class="icon" /></span>
    <div class="empty-title">{{ title }}</div>
    <p v-if="text" class="muted small">{{ text }}</p>
    <div v-if="$slots.default" class="actions"><slot /></div>
  </div>
</template>

<style scoped>
.empty { text-align: center; padding: var(--dm-space-6) var(--dm-space-4); color: var(--dm-muted); display: flex; flex-direction: column; align-items: center; gap: 8px; }
.icon-wrap { width: 40px; height: 40px; border-radius: 50%; background: var(--dm-surface-2); display: grid; place-items: center; color: var(--dm-muted); }
.empty-title { color: var(--dm-ink); font-weight: 500; font-size: var(--dm-text-base); }
.empty p { margin: 0; max-width: 48ch; }
.empty .actions { justify-content: center; margin-top: 4px; }
</style>
