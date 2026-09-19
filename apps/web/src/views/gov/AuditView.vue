<script setup lang="ts">
import Button from 'primevue/button'
import Column from 'primevue/column'
import DataTable from 'primevue/datatable'
import InputText from 'primevue/inputtext'
import Tag from 'primevue/tag'
import { onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { journal } from '@/api/endpoints'
import type { AuditEntry } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'

const { t, locale } = useI18n()

const items = ref<AuditEntry[]>([])
const total = ref(0)
const error = ref<unknown>(null)
const loading = ref(false)

const actor = ref('')
const page = ref(0)
const rows = ref(25)

async function load() {
  loading.value = true
  error.value = null
  try {
    const response = await journal.audit({ actor: actor.value.trim() || undefined, page: page.value + 1, size: rows.value })
    items.value = response.items
    total.value = response.total
  } catch (e) {
    error.value = e
    items.value = []
    total.value = 0
  } finally {
    loading.value = false
  }
}

function onPage(event: { page: number; rows: number }) {
  page.value = event.page
  rows.value = event.rows
  load()
}

function onFilter() {
  page.value = 0
  load()
}

onMounted(load)
</script>

<template>
  <main class="page">
    <h1>{{ t('gov.audit.title') }}</h1>
    <p class="lead">{{ t('gov.audit.lead') }}</p>

    <div class="actions" style="margin: 0 0 12px; align-items: center">
      <div class="field" style="margin: 0">
        <label>{{ t('gov.audit.actorFilter') }}</label>
        <InputText v-model="actor" :placeholder="t('gov.audit.actorPlaceholder')" @keyup.enter="onFilter" />
      </div>
      <Button :label="t('gov.audit.refresh')" icon="pi pi-refresh" size="small" severity="secondary" :loading="loading" @click="onFilter" />
    </div>

    <ErrorBox :error="error" />

    <p class="muted">{{ t('gov.audit.total') }}: {{ total }}</p>

    <DataTable
      :value="items"
      size="small"
      :loading="loading"
      paginator
      lazy
      :rows="rows"
      :total-records="total"
      :first="page * rows"
      @page="onPage"
    >
      <Column field="at" :header="t('gov.audit.colWhen')">
        <template #body="{ data }">{{ new Date(data.at).toLocaleString(locale === 'kk' ? 'kk-KZ' : 'ru-RU') }}</template>
      </Column>
      <Column field="actor" :header="t('gov.audit.colActor')" />
      <Column field="role" :header="t('gov.audit.colRole')" />
      <Column field="method" :header="t('gov.audit.colMethod')" />
      <Column field="path" :header="t('gov.audit.colPath')" />
      <Column field="query" :header="t('gov.audit.colQuery')" />
      <Column field="status" :header="t('gov.audit.colStatus')">
        <template #body="{ data }"><Tag :value="data.status" :severity="data.status < 400 ? 'success' : 'danger'" /></template>
      </Column>
      <Column field="durationMs" :header="t('gov.audit.colDuration')" />
      <Column field="traceId" :header="t('gov.audit.colTrace')" />
      <template #empty>{{ t('gov.audit.empty') }}</template>
    </DataTable>
  </main>
</template>
