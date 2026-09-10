<script setup lang="ts">
import Column from 'primevue/column'
import DataTable from 'primevue/datatable'
import Tag from 'primevue/tag'
import { onMounted, ref } from 'vue'
import { intake } from '@/api/endpoints'
import type { Batch } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import { num } from '@/lib/format'

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
    <h1>Консоль стюарда</h1>
    <p class="lead">Партии загрузки Data Intake Fabric: событие intake.batch.loaded приходит из Python через Kafka, строки в карантине ждут проверки.</p>
    <ErrorBox :error="error" />
    <div class="card">
      <h2>Партии</h2>
      <DataTable :value="items" size="small" paginator :rows="20">
        <Column field="receivedAt" header="Получено"><template #body="{ data }">{{ new Date(data.receivedAt).toLocaleString('ru-RU') }}</template></Column>
        <Column field="dataset" header="Набор" />
        <Column field="status" header="Статус"><template #body="{ data }"><Tag :value="data.status" :severity="data.status === 'loaded' ? 'success' : 'warn'" /></template></Column>
        <Column header="Загружено"><template #body="{ data }">{{ num(data.rowsLoaded) }}</template></Column>
        <Column header="В карантине"><template #body="{ data }">{{ num(data.rowsQuarantined) }}</template></Column>
        <Column header="Партиции"><template #body="{ data }">{{ data.partitions.length }}</template></Column>
        <Column field="batchId" header="Партия" />
      </DataTable>
      <p v-if="items.length === 0" class="muted">Партий пока нет: запустите <code>make data</code> с заданными KAFKA_BOOTSTRAP и SCHEMA_REGISTRY_URL.</p>
    </div>
    <div class="grid cols-2" style="margin-top: 16px">
      <div class="card"><h2>Контракты на утверждение</h2><p class="muted">Черновики контрактов для файлов с неизвестной схемой лежат в lakehouse/drafts; утверждение из интерфейса появится вместе с загрузкой файлов через API.</p></div>
      <div class="card"><h2>Карантин</h2><p class="muted">Строки, не прошедшие правила контракта, хранятся по партиям в lakehouse/quarantine с причиной; переработка после правки контракта.</p></div>
    </div>
  </main>
</template>
