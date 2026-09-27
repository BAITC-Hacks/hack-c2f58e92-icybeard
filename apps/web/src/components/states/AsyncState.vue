<script setup lang="ts">
import Skeleton from '@/components/ui/Skeleton.vue'
import StateBlock from './StateBlock.vue'
import StateError from './StateError.vue'
import StateFiltered from './StateFiltered.vue'

/** Шесть состояний списка (W-States) одним компонентом: загрузка (скелет той же высоты), ошибка (Повторить /
 * поддержка; 403 — «Нет доступа»), пусто по фильтру («Сбросить фильтры»), пусто (нет данных, с действием в слоте
 * empty-actions) и содержимое. Баннер «данные устарели» — отдельный StateStale над блоком. */
withDefaults(
  defineProps<{
    loading: boolean
    error?: unknown
    empty: boolean
    filtered?: boolean
    skeleton?: 'table' | 'lines' | 'kpi' | 'chart'
    lines?: number
    emptyTitle: string
    emptyText?: string
    emptyIcon?: string
    filterHint?: string
  }>(),
  { filtered: false, skeleton: 'table', lines: 6, emptyIcon: 'pi pi-inbox' },
)
const emit = defineEmits<{ retry: []; reset: [] }>()
</script>

<template>
  <StateError v-if="error" :error="error" @retry="emit('retry')" />
  <Skeleton v-else-if="loading && empty" :kind="skeleton" :lines="lines" />
  <StateFiltered v-else-if="empty && filtered" :hint="filterHint" @reset="emit('reset')" />
  <StateBlock v-else-if="empty" :icon="emptyIcon" :title="emptyTitle" :text="emptyText" data-testid="state-empty">
    <slot name="empty-actions" />
  </StateBlock>
  <slot v-else />
</template>
