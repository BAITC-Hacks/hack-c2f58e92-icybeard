<script setup lang="ts">
import { computed } from 'vue'

/** Приоритет в строке рабочего списка: число и полоса относительно максимума в списке (дорожка soft, заливка ink). */
const props = withDefaults(defineProps<{ value: number; max?: number }>(), { max: 100 })
const width = computed(() => `${Math.max(4, Math.min(100, (props.value / (props.max || 1)) * 100)).toFixed(0)}%`)
</script>

<template>
  <span class="priority" :title="String(value)">
    <span class="tabular number">{{ Math.round(value) }}</span>
    <span class="track" aria-hidden="true"><span class="fill" :style="{ width }" /></span>
  </span>
</template>

<style scoped>
.priority { display: inline-flex; align-items: center; gap: 8px; }
.number { min-width: 3ch; text-align: right; font-weight: 500; }
.track { width: 56px; height: 6px; border-radius: 3px; background: var(--dm-neutral-soft); overflow: hidden; }
.fill { display: block; height: 100%; background: var(--dm-ink); border-radius: 3px; }
</style>
