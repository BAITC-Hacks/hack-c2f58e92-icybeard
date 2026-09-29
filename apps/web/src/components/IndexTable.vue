<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import type { IndexItem } from '@/api/types'
import { days, indexColor, pct } from '@/lib/format'

/** Ранжированная таблица регионов по индексу: квадратик ступени шкалы (пять синих) рядом со значением; наведение и
 * клик уходят наружу — подсветка общая с картой. */
defineProps<{ items: IndexItem[]; highlight?: string | null }>()
const emit = defineEmits<{ select: [kato: string]; hover: [kato: string | null] }>()
const { t } = useI18n()
</script>

<template>
  <div class="table-wrap index-wrap">
    <table class="dense-table" data-testid="index-table">
      <thead>
        <tr><th>#</th><th>{{ t('common.region') }}</th><th class="num">{{ t('indexTable.index') }}</th><th class="num">&gt; 30 {{ t('common.days') }}</th><th class="num">p90</th><th class="num">n</th></tr>
      </thead>
      <tbody>
        <tr
          v-for="item in items"
          :key="item.regionKato"
          class="clickable"
          :class="{ selected: highlight === item.regionKato }"
          @click="emit('select', item.regionKato)"
          @mouseenter="emit('hover', item.regionKato)"
          @mouseleave="emit('hover', null)"
        >
          <td class="muted">{{ item.rank }}</td>
          <td>{{ item.name }}</td>
          <td class="num"><span class="index"><span class="swatch" :style="{ background: indexColor(item.indexValue) }" aria-hidden="true" />{{ item.indexValue.toFixed(1) }}</span></td>
          <td class="num">{{ pct(item.shareOver30) }}</td>
          <td class="num">{{ days(item.p90Days) }}</td>
          <td class="num muted">{{ item.n }}</td>
        </tr>
      </tbody>
    </table>
  </div>
</template>

<style scoped>
.index-wrap { max-height: 520px; overflow-y: auto; }
.index { font-weight: var(--fw-bold); display: inline-flex; align-items: center; gap: 8px; justify-content: flex-end; }
.swatch { width: 12px; height: 12px; border-radius: 3px; display: inline-block; flex: none; }
</style>
