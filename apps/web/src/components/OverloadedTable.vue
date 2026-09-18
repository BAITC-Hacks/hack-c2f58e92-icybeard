<script setup lang="ts">
import Column from 'primevue/column'
import DataTable from 'primevue/datatable'
import { useI18n } from 'vue-i18n'
import type { OverloadedOrganization } from '@/api/types'
import { pct } from '@/lib/format'

defineProps<{ items: OverloadedOrganization[] }>()
const emit = defineEmits<{ organization: [moCode: string]; simulate: [item: OverloadedOrganization] }>()
const { t } = useI18n()

/** Больше 1 — поток направлений превышает госпитализации, очередь растёт; null — госпитализаций вообще нет
 * при живом потоке (throughput_per_day = 0), это тоже перегрузка, просто без коэффициента. */
function loadLabel(load: number | null): string {
  return load === null ? t('overloadedTable.noAdmissions') : load.toFixed(1)
}
</script>

<template>
  <DataTable :value="items" size="small" scrollable scroll-height="420px">
    <Column field="name" :header="t('common.organization')">
      <template #body="{ data }">
        <a href="#" @click.prevent="emit('organization', data.moCode)">{{ data.name }}</a>
        <span class="muted"> ({{ data.moCode }})</span>
      </template>
    </Column>
    <Column :header="t('overloadedTable.load')" style="width: 8rem">
      <template #body="{ data }"><span :class="{ minus: data.load === null || data.load > 1 }">{{ loadLabel(data.load) }}</span></template>
    </Column>
    <Column field="queueLen" :header="t('overloadedTable.queue')" style="width: 6rem" />
    <Column :header="`p90, ${t('common.days')}`" style="width: 6rem">
      <template #body="{ data }">{{ data.queueAgeP90?.toFixed(0) ?? '—' }}</template>
    </Column>
    <Column :header="t('overloadedTable.refusals')" style="width: 6rem">
      <template #body="{ data }">{{ pct(data.refusalRate4w) }}</template>
    </Column>
    <Column header="" style="width: 8rem">
      <template #body="{ data }"><a href="#" @click.prevent="emit('simulate', data)">{{ t('overloadedTable.toSimulator') }} →</a></template>
    </Column>
  </DataTable>
  <p v-if="!items.length" class="muted">{{ t('overloadedTable.none') }}</p>
</template>
