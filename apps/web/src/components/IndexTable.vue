<script setup lang="ts">
import Column from 'primevue/column'
import DataTable from 'primevue/datatable'
import { useI18n } from 'vue-i18n'
import type { IndexItem } from '@/api/types'
import { days, indexColor, pct } from '@/lib/format'

defineProps<{ items: IndexItem[]; selected?: string | null }>()
const emit = defineEmits<{ select: [kato: string] }>()
const { t } = useI18n()
</script>

<template>
  <DataTable :value="items" size="small" scrollable scroll-height="460px" selection-mode="single" data-key="regionKato" @row-click="emit('select', $event.data.regionKato)">
    <Column field="rank" header="#" style="width: 3rem" />
    <Column field="name" :header="t('common.region')" />
    <Column :header="t('indexTable.index')" style="width: 6rem">
      <template #body="{ data }">
        <span :style="{ color: indexColor(data.indexValue), fontWeight: 600 }">{{ data.indexValue.toFixed(1) }}</span>
      </template>
    </Column>
    <Column :header="`> 30 ${t('common.days')}`" style="width: 6rem">
      <template #body="{ data }">{{ pct(data.shareOver30) }}</template>
    </Column>
    <Column :header="`p90, ${t('common.days')}`" style="width: 6rem">
      <template #body="{ data }">{{ days(data.p90Days) }}</template>
    </Column>
    <Column field="n" header="n" style="width: 5rem" />
  </DataTable>
</template>
