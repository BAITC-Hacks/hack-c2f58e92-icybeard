<script setup lang="ts">
import Button from 'primevue/button'
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { useTheme } from '@/composables/useTheme'

const { t } = useI18n()
const { theme, cycle } = useTheme()
const icon = computed(() => ({ light: 'pi pi-sun', dark: 'pi pi-moon', system: 'pi pi-desktop' })[theme.value])
const label = computed(() => t(`theme.${theme.value}`))
</script>

<template>
  <Button :icon="icon" :aria-label="label" :title="label" text rounded size="small" class="theme-toggle" data-testid="theme-toggle" @click="cycle" />
</template>

<style scoped>
/* круг 32–36 на --surface-muted с приглушённой иконкой (components.md «Кнопка темы») */
.theme-toggle.p-button { width: 32px; height: 32px; min-height: 32px; padding: 0; background: var(--surface-muted); color: var(--text-muted); border: 0; }
.theme-toggle.p-button:hover { background: var(--accent-soft); color: var(--accent-strong); }
</style>
