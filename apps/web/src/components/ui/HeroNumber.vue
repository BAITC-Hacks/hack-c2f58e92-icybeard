<script setup lang="ts">
import OriginTag from '@/components/OriginTag.vue'
import Skeleton from './Skeleton.vue'

/** Одно главное число экрана: hero 60 / 600 (compact — 42 / 500) с единицей 17 ink-2, над ним label uppercase с меткой
 * происхождения справа, под числом формулировка («половина ждёт не дольше») и второй ряд мельче. */
defineProps<{
  value: string | number
  unit?: string
  /** формулировка под числом («половина ждёт не дольше») */
  label: string
  /** второй ряд: остальные цифры мельче («9 из 10 — до 106 · 54 % за 30 дней») */
  sub?: string
  /** label uppercase над числом; без него метка происхождения встаёт в строку формулировки */
  caption?: string
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
    <div v-if="caption" class="hero-caption"><span class="eyebrow">{{ caption }}</span><span class="spacer" /><OriginTag v-if="origin" :kind="origin" :note="originNote" /></div>
    <Skeleton v-if="loading" kind="kpi" />
    <div v-else class="hero-value tabular"><span class="number">{{ value }}</span><span v-if="unit" class="unit">{{ unit }}</span></div>
    <div class="hero-label">{{ label }} <OriginTag v-if="origin && !caption" :kind="origin" :note="originNote" /></div>
    <div v-if="sub" class="hero-sub muted tabular">{{ sub }}</div>
    <div v-if="$slots.default" class="hero-extra"><slot /></div>
  </div>
</template>

<style scoped>
.hero { display: flex; flex-direction: column; gap: 8px; }
.hero-caption { display: flex; align-items: center; gap: 10px; }
.spacer { flex: 1; }
.hero-value { display: flex; align-items: baseline; gap: 10px; line-height: 1; margin-top: 4px; }
.number { font-size: var(--dm-text-hero); font-weight: 600; letter-spacing: -0.02em; }
.compact .number { font-size: var(--dm-text-kpi); font-weight: 500; }
.unit { font-size: var(--dm-text-base); color: var(--dm-muted); }
.hero-label { font-size: var(--dm-text-md); }
.hero-sub { font-size: var(--dm-text-sm); }
.hero-extra { margin-top: 4px; }
.hero.ok .number { color: var(--dm-ok); }
.hero.warn .number, .hero.danger .number { color: var(--dm-danger); }
</style>
