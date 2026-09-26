<script setup lang="ts">
import OriginTag from '@/components/OriginTag.vue'
import Skeleton from './Skeleton.vue'

/** Одно главное число экрана: крупное значение с единицей, под ним формулировка NHS («9 из 10 — до 106 дней»)
 * и второй ряд мельче. Метка происхождения — одна на блок. */
defineProps<{
  value: string | number
  unit?: string
  /** формулировка под числом («половина ждёт не дольше») */
  label: string
  /** второй ряд: остальные цифры мельче («9 из 10 — до 106 · 54 % за 30 дней») */
  sub?: string
  origin?: 'ml' | 'formula' | 'ai'
  originNote?: string
  loading?: boolean
  tone?: 'ok' | 'warn' | 'danger'
  /** компактный вариант для колонок */
  compact?: boolean
}>()
</script>

<template>
  <div class="hero" :class="[tone, { compact }]">
    <Skeleton v-if="loading" kind="kpi" />
    <div v-else class="hero-value tabular"><span class="number">{{ value }}</span><span v-if="unit" class="unit">{{ unit }}</span></div>
    <div class="hero-label">{{ label }} <OriginTag v-if="origin" :kind="origin" :note="originNote" /></div>
    <div v-if="sub" class="hero-sub muted">{{ sub }}</div>
    <div v-if="$slots.default" class="hero-extra"><slot /></div>
  </div>
</template>

<style scoped>
.hero { display: flex; flex-direction: column; gap: 4px; }
.hero-value { display: flex; align-items: baseline; gap: 6px; line-height: 1; }
.number { font-size: 48px; font-weight: 600; letter-spacing: -0.02em; }
.compact .number { font-size: 36px; }
.unit { font-size: 1.1rem; color: var(--dm-muted); }
.hero-label { font-size: 1rem; }
.hero-sub { font-size: 0.9rem; }
.hero-extra { margin-top: 6px; }
.hero.ok .number { color: var(--dm-ok); }
.hero.warn .number { color: var(--dm-warn); }
.hero.danger .number { color: var(--dm-danger); }
</style>
