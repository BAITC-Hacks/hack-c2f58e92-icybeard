<script setup lang="ts">
import type { RouteLocationRaw } from 'vue-router'
import { useI18n } from 'vue-i18n'
import OriginTag from '@/components/OriginTag.vue'
import { dateShort } from '@/lib/route'

/** Каркас страницы (W-*): шапка — H1 35 / 500 (у гражданина 42) с меткой происхождения и чипами (title-extra),
 * подпись 15 ink-2 с датой данных (asOf), ссылка «← назад» над заголовком, справа фильтры-пилюли (actions). */
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
        <RouterLink v-if="back" class="back" :to="back.to"><span aria-hidden="true">←</span> {{ back.label }}</RouterLink>
        <div class="title-row">
          <h1>{{ title }}</h1>
          <OriginTag v-if="origin" :kind="origin" :note="originNote" />
          <slot name="title-extra" />
        </div>
        <div v-if="$slots.subtitle" class="subtitle lead"><slot name="subtitle" /></div>
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
.page-head { display: flex; align-items: flex-end; justify-content: space-between; gap: var(--dm-space-4); flex-wrap: wrap; }
.page-title { min-width: 0; display: flex; flex-direction: column; gap: 6px; }
.title-row { display: flex; align-items: center; gap: 12px; flex-wrap: wrap; }
.back { display: inline-flex; align-items: center; gap: 6px; font-size: var(--dm-text-sm); font-weight: 500; color: var(--dm-muted); text-decoration: none; margin-bottom: 8px; }
.back:hover { color: var(--dm-ink); }
.asof { white-space: nowrap; }
.page-actions { display: flex; gap: var(--dm-space-2); flex-wrap: wrap; align-items: center; }
.page-actions :deep(.p-select), .page-actions :deep(.p-inputtext) { background: var(--dm-surface); border-radius: var(--dm-radius-pill); min-height: 36px; }
.page-actions :deep(.search-select) { width: auto; min-width: 220px; max-width: 320px; }
.page-actions :deep(.p-select-sm .p-select-label) { padding-block: 6px; }
/* фильтры-пилюли, выпадающие списки и кнопки в одной строке — одной высоты */
.page-actions :deep(.chip-filter), .page-actions :deep(.p-button-sm) { height: 36px; }
.page-actions :deep(.p-select-sm) { height: 36px; align-items: center; }
.page-actions :deep(.p-select-label) { padding-inline: 16px 6px; }
.page-actions :deep(.p-select-dropdown) { padding-right: 10px; }
.page-actions :deep(.chips) { gap: var(--dm-space-2); }
</style>
