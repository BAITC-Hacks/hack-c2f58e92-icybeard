<script setup lang="ts">
import { computed } from 'vue'

/** Спарклайн в плитке KPI: ломаная по значениям, цвет — currentColor (через токены родителя). */
const props = withDefaults(defineProps<{ values: (number | null)[]; width?: number; height?: number }>(), { width: 88, height: 26 })

const points = computed(() => {
  const vals = props.values.map((v) => (v === null || Number.isNaN(v) ? null : v))
  const known = vals.filter((v): v is number => v !== null)
  if (known.length < 2) return ''
  const min = Math.min(...known)
  const max = Math.max(...known)
  const span = max - min || 1
  const step = props.width / (vals.length - 1)
  return vals
    .map((v, i) => (v === null ? null : `${(i * step).toFixed(1)},${(props.height - 2 - ((v - min) / span) * (props.height - 4)).toFixed(1)}`))
    .filter((p): p is string => p !== null)
    .join(' ')
})
</script>

<template>
  <svg v-if="points" class="spark" :width="width" :height="height" :viewBox="`0 0 ${width} ${height}`" aria-hidden="true">
    <polyline :points="points" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round" stroke-linecap="round" />
  </svg>
</template>

<style scoped>
.spark { display: block; color: var(--dm-accent); overflow: visible; }
</style>
