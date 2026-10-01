<script setup lang="ts">
import OriginTag from '@/components/OriginTag.vue'
import Skeleton from './Skeleton.vue'
import StatusTag from './StatusTag.vue'
import type { StatusTone } from './tones'

/** KPI-карточка: белая radius 16, значение 42 / 500 + единица 17 ink-2, подпись 14 ink-2, при необходимости чип
 * (по умолчанию critical) рядом со значением. У чисел модели `origin` обязателен по соглашению проекта. */
defineProps<{
  value: string | number
  unit?: string
  label: string
  origin?: 'ml' | 'formula' | 'ai'
  hint?: string
  /** чип рядом со значением («4 аномалии», «выше среднего по профилю») */
  chip?: string
  chipTone?: StatusTone
  tone?: 'ok' | 'warn' | 'danger'
  loading?: boolean
  /** подпись над числом («Пациентов в листе ожидания» → 1784): читается как фраза */
  labelFirst?: boolean
}>()
</script>

<template>
  <div class="item" :class="[tone, { 'label-first': labelFirst }]">
    <div v-if="labelFirst" class="label-line"><span class="label">{{ label }}</span><OriginTag v-if="origin" :kind="origin" /></div>
    <Skeleton v-if="loading" kind="kpi" />
    <div v-else class="value tabular">
      <span class="number">{{ value }}</span><span v-if="unit" class="unit">{{ unit }}</span>
      <StatusTag v-if="chip" :value="chip" :tone="chipTone ?? 'danger'" class="chip" />
    </div>
    <div v-if="!labelFirst" class="label-line"><span class="label">{{ label }}</span><OriginTag v-if="origin" :kind="origin" /></div>
    <div v-if="hint" class="hint caption">{{ hint }}</div>
  </div>
</template>

<style scoped>
.value { display: flex; align-items: baseline; gap: 10px; flex-wrap: wrap; }
.label-line { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
.label { min-height: 0; }
.item.ok .number { color: var(--dm-ok); }
.item.warn .number { color: var(--dm-warn); }
.item.danger .number { color: var(--dm-danger); }
.chip { align-self: center; }
.label-first { gap: 10px; }
.label-first .label { color: var(--text-secondary); font-size: var(--fs-base-sm, 15px); font-weight: var(--fw-semibold, 600); line-height: 1.35; }
.label-first .hint { line-height: 1.45; }
</style>
