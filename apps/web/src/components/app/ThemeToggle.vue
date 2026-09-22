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
  <Button :icon="icon" :aria-label="label" :title="label" text rounded size="small" data-testid="theme-toggle" @click="cycle" />
</template>
