<script setup lang="ts">
import { computed } from 'vue'

/** Приоритет в строке рабочего списка: число и полоса относительно максимума в списке.
 * Заливка семантическая (спека «синей гаммы»): верхняя треть — риск (--danger-strong),
 * нижняя треть — норма (--scale-good), середина — акцент. Только представление. */
const props = withDefaults(defineProps<{ value: number; max?: number }>(), { max: 100 })
const ratio = computed(() => Math.max(0.04, Math.min(1, props.value / (props.max || 1))))
const width = computed(() => `${(ratio.value * 100).toFixed(0)}%`)
const fill = computed(() => (ratio.value >= 2 / 3 ? 'var(--danger-strong)' : ratio.value < 1 / 3 ? 'var(--scale-good)' : 'var(--accent)'))
</script>

<template>
  <span class="priority" :title="String(value)">
    <span class="tabular number">{{ Math.round(value) }}</span>
    <span class="track" aria-hidden="true"><span class="fill" :style="{ width, background: fill }" /></span>
  </span>
</template>

<style scoped>
.priority { display: inline-flex; align-items: center; gap: 8px; }
.number { min-width: 3ch; text-align: right; font-weight: 500; }
.track { width: 56px; height: 6px; border-radius: var(--radius-xs); background: var(--surface-muted); overflow: hidden; }
.fill { display: block; height: 100%; border-radius: var(--radius-xs); }
</style>
