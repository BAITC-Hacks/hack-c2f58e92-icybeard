<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import OriginTag from '@/components/OriginTag.vue'

/** Одна пометка на страницу вместо метки на каждом блоке: все числа — расчёт по правилу (формуле) из данных;
 * блоки, где работает модель, по-прежнему помечены «прогноз модели» прямо в заголовке. */
const { t } = useI18n()
</script>

<template>
  <span class="origin-legend" data-testid="origin-legend">
    <OriginTag kind="formula" />
    <span>{{ t('originTag.legend') }}</span>
  </span>
</template>

<style scoped>
.origin-legend { display: flex; align-items: flex-start; gap: 10px; font-size: var(--fs-sm); color: var(--text-secondary); line-height: 1.45; max-width: 860px; }
.origin-legend > :first-child { flex: none; }
.origin-legend > span:last-child { padding-top: 2px; }
</style>
