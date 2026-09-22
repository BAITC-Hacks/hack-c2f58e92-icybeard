<script setup lang="ts">
/** Пустое состояние: одна фраза, что сделать, и необязательное действие. */
withDefaults(defineProps<{ title: string; text?: string; icon?: string }>(), { icon: 'pi pi-inbox' })
</script>

<template>
  <div class="empty">
    <i :class="icon" />
    <div class="empty-title">{{ title }}</div>
    <p v-if="text" class="muted">{{ text }}</p>
    <div v-if="$slots.default" class="actions"><slot /></div>
  </div>
</template>

<style scoped>
.empty { text-align: center; padding: var(--dm-space-6) var(--dm-space-4); color: var(--dm-muted); }
.empty i { font-size: 1.6rem; color: var(--dm-faint); }
.empty-title { margin-top: var(--dm-space-2); color: var(--dm-ink); font-weight: 600; }
.empty p { margin: 4px 0 0; }
.empty .actions { justify-content: center; }
</style>
