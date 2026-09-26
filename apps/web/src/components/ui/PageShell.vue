<script setup lang="ts">
import type { RouteLocationRaw } from 'vue-router'
import { useI18n } from 'vue-i18n'
import OriginTag from '@/components/OriginTag.vue'
import { dateShort } from '@/lib/route'

/** Каркас страницы: заголовок с меткой происхождения, подпись (lead) с датой данных (asOf), при необходимости
 * ссылка «назад», пометка «синтетические данные» и действия справа (PDF / Excel, фильтры). */
defineProps<{
  title: string
  lead?: string
  /** дата данных (ISO или уже отформатированная) — подпись «данные на …» */
  asOf?: string
  origin?: 'ml' | 'formula' | 'ai'
  originNote?: string
  synthetic?: string
  back?: { to: RouteLocationRaw; label: string }
}>()
const { t } = useI18n()
</script>

<template>
  <main class="page">
    <header class="page-head">
      <div class="page-title">
        <RouterLink v-if="back" class="back muted" :to="back.to">← {{ back.label }}</RouterLink>
        <h1>{{ title }} <OriginTag v-if="origin" :kind="origin" :note="originNote" /><slot name="title-extra" /></h1>
        <div v-if="$slots.subtitle" class="subtitle muted"><slot name="subtitle" /></div>
        <p v-if="lead || asOf" class="lead">
          <template v-if="lead">{{ lead }}</template>
          <span v-if="asOf" class="asof">{{ lead ? ' · ' : '' }}{{ t('shell.asOf', { date: dateShort(asOf) }) }}</span>
        </p>
        <p v-if="synthetic" class="lead synthetic">{{ synthetic }}</p>
      </div>
      <div v-if="$slots.actions" class="page-actions"><slot name="actions" /></div>
    </header>
    <slot />
  </main>
</template>

<style scoped>
.page-head { display: flex; align-items: flex-start; justify-content: space-between; gap: var(--dm-space-4); flex-wrap: wrap; margin-bottom: var(--dm-space-4); }
.page-title { min-width: 0; }
.page-head h1 { margin-bottom: 4px; }
.page-head .lead { margin-bottom: 0; }
.subtitle { margin: -2px 0 4px; font-size: 0.95rem; }
.back { display: inline-block; font-size: 0.85rem; text-decoration: none; margin-bottom: 4px; }
.back:hover { color: var(--dm-accent); }
.asof { white-space: nowrap; }
.page-actions { display: flex; gap: var(--dm-space-2); flex-wrap: wrap; align-items: center; }
</style>
