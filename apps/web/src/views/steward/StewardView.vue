<script setup lang="ts">
import Column from 'primevue/column'
import DataTable from 'primevue/datatable'
import Tag from 'primevue/tag'
import { onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { intake } from '@/api/endpoints'
import type { Batch } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import { num } from '@/lib/format'

const { t, locale } = useI18n()
const items = ref<Batch[]>([])
const error = ref<unknown>(null)

onMounted(async () => {
  try {
    items.value = (await intake.batches({ size: 100 })).items
  } catch (e) {
    error.value = e
  }
})
</script>

<template>
  <main class="page">
    <h1>{{ t('steward.title') }}</h1>
    <p class="lead">{{ t('steward.lead') }}</p>
    <ErrorBox :error="error" />
    <div class="card">
      <h2>{{ t('steward.batches') }}</h2>
      <DataTable :value="items" size="small" paginator :rows="20">
        <Column field="receivedAt" :header="t('steward.received')"><template #body="{ data }">{{ new Date(data.receivedAt).toLocaleString(locale === 'kk' ? 'kk-KZ' : 'ru-RU') }}</template></Column>
        <Column field="dataset" :header="t('steward.dataset')" />
        <Column field="status" :header="t('steward.status')"><template #body="{ data }"><Tag :value="data.status" :severity="data.status === 'loaded' ? 'success' : 'warn'" /></template></Column>
        <Column :header="t('steward.loaded')"><template #body="{ data }">{{ num(data.rowsLoaded) }}</template></Column>
        <Column :header="t('steward.quarantined')"><template #body="{ data }">{{ num(data.rowsQuarantined) }}</template></Column>
        <Column :header="t('steward.partitions')"><template #body="{ data }">{{ data.partitions.length }}</template></Column>
        <Column field="batchId" :header="t('steward.batch')" />
      </DataTable>
      <p v-if="items.length === 0" class="muted">{{ t('steward.noBatches') }} <code>make data</code> {{ t('steward.noBatchesSuffix') }}</p>
    </div>
    <div class="grid cols-2" style="margin-top: 16px">
      <div class="card"><h2>{{ t('steward.contractsTitle') }}</h2><p class="muted">{{ t('steward.contractsHint') }}</p></div>
      <div class="card"><h2>{{ t('steward.quarantineTitle') }}</h2><p class="muted">{{ t('steward.quarantineHint') }}</p></div>
    </div>
  </main>
</template>
