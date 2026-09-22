<script setup lang="ts">
import OriginTag from '@/components/OriginTag.vue'
import Skeleton from './Skeleton.vue'

/** Плитка показателя: табличные цифры, подпись до двух строк (казахский длиннее). У чисел модели `origin` обязателен
 * по соглашению проекта — иначе непонятно, откуда число. */
defineProps<{ value: string | number; label: string; origin?: 'ml' | 'formula' | 'ai'; hint?: string; tone?: 'ok' | 'warn' | 'danger'; loading?: boolean }>()
</script>

<template>
  <div class="item" :class="tone">
    <Skeleton v-if="loading" kind="kpi" />
    <div v-else class="value tabular">{{ value }}</div>
    <div class="label">{{ label }} <OriginTag v-if="origin" :kind="origin" /></div>
    <div v-if="hint" class="hint muted">{{ hint }}</div>
  </div>
</template>

<style scoped>
.item.ok .value { color: var(--dm-ok); }
.item.warn .value { color: var(--dm-warn); }
.item.danger .value { color: var(--dm-danger); }
.hint { font-size: 0.8rem; margin-top: 2px; }
.label { min-height: 2.4em; }
</style>
