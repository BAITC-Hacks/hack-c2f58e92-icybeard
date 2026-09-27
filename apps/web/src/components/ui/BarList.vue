<script setup lang="ts">
import { computed } from 'vue'

export interface BarItem { key: string; label: string; value: number; display?: string; highlight?: boolean; title?: string }

/** Бары по образцу досок: подпись 150 px слева, дорожка soft 10 px radius 4, заливка ink (коралл — выделенная
 * строка), значение справа табличными цифрами. Ширина — доля от максимума. */
const props = defineProps<{ items: BarItem[]; labelWidth?: number }>()
const max = computed(() => Math.max(1e-9, ...props.items.map((i) => i.value)))
</script>

<template>
  <div class="bars tabular">
    <div v-for="item in items" :key="item.key" class="bar-row" :title="item.title ?? item.label">
      <span class="bar-label" :style="{ width: `${labelWidth ?? 150}px` }">{{ item.label }}</span>
      <span class="track" aria-hidden="true"><span class="fill" :class="{ highlight: item.highlight }" :style="{ width: `${Math.max(1, (item.value / max) * 100)}%` }" /></span>
      <span class="bar-value">{{ item.display ?? item.value }}</span>
    </div>
  </div>
</template>

<style scoped>
.bars { display: flex; flex-direction: column; gap: 10px; font-size: var(--dm-text-sm); }
.bar-row { display: flex; align-items: center; gap: 12px; }
.bar-label { flex: none; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.track { flex: 1; height: 10px; border-radius: 4px; background: var(--dm-surface-2); overflow: hidden; }
.fill { display: block; height: 100%; border-radius: 4px; background: var(--dm-ink); }
.fill.highlight { background: var(--dm-accent); }
.bar-value { width: 56px; text-align: right; flex: none; }
</style>
