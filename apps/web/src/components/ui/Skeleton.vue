<script setup lang="ts">
/** Скелетон загрузки: kpi — одно число, lines — несколько строк текста, table — строки таблицы, chart — область графика. */
withDefaults(defineProps<{ kind?: 'kpi' | 'lines' | 'table' | 'chart'; lines?: number }>(), { kind: 'lines', lines: 3 })
</script>

<template>
  <div class="skeleton" :class="kind" aria-hidden="true">
    <template v-if="kind === 'kpi'"><span class="bar value" /></template>
    <template v-else-if="kind === 'chart'"><span class="bar area" /></template>
    <template v-else>
      <span v-for="i in lines" :key="i" class="bar line" :style="{ width: `${100 - ((i * 17) % 40)}%` }" />
    </template>
  </div>
</template>

<style scoped>
.skeleton { display: flex; flex-direction: column; gap: 10px; }
.bar { display: block; border-radius: var(--dm-radius-sm); background: var(--dm-neutral-soft); animation: pulse 1.4s ease-in-out infinite; }
.bar.line { height: 14px; }
.bar.value { height: 42px; width: 50%; border-radius: var(--dm-radius-md); }
.bar.area { height: 220px; width: 100%; border-radius: var(--dm-radius-md); }
.skeleton.table .bar.line { height: 36px; }
@keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.45; } }
@media (prefers-reduced-motion: reduce) { .bar { animation: none; } }
</style>
