<script setup lang="ts">
import Button from 'primevue/button'
import Column from 'primevue/column'
import DataTable from 'primevue/datatable'
import InputText from 'primevue/inputtext'
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { intake } from '@/api/endpoints'
import type { Batch, IntakeDraftSummary, IntakeUploadResult } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import { useLocaleFormat } from '@/composables/useLocaleFormat'
import PageShell from '@/components/ui/PageShell.vue'
import StatusTag from '@/components/ui/StatusTag.vue'

const { t } = useI18n()
const { num, dateTime } = useLocaleFormat()
const items = ref<Batch[]>([])
const error = ref<unknown>(null)

const fileInput = ref<HTMLInputElement | null>(null)
const uploading = ref(false)
const uploadError = ref<unknown>(null)
const uploadResult = ref<IntakeUploadResult | null>(null)

const drafts = ref<IntakeDraftSummary[]>([])
const approvingDataset = ref<string | null>(null)
const approveError = ref<unknown>(null)
const approveMessage = ref<Record<string, string>>({})

const quarantineDataset = ref('')
const quarantineBatchId = ref('')
const quarantineLoading = ref(false)
const quarantineError = ref<unknown>(null)
const quarantineRows = ref<Record<string, unknown>[]>([])
const quarantineTotal = ref(0)
const quarantineColumns = computed(() => (quarantineRows.value[0] ? Object.keys(quarantineRows.value[0]) : []))

async function loadBatches() {
  try {
    items.value = (await intake.batches({ size: 100 })).items
  } catch (e) {
    error.value = e
  }
}

async function loadDrafts() {
  try {
    drafts.value = (await intake.drafts()).items
  } catch (e) {
    approveError.value = e
  }
}

async function upload() {
  const file = fileInput.value?.files?.[0]
  if (!file) return
  uploading.value = true
  uploadError.value = null
  uploadResult.value = null
  try {
    uploadResult.value = await intake.upload(file, file.name)
    if (uploadResult.value.status === 'unknown') await loadDrafts()
    else await loadBatches()
  } catch (e) {
    uploadError.value = e
  } finally {
    uploading.value = false
    if (fileInput.value) fileInput.value.value = ''
  }
}

async function approve(dataset: string) {
  approvingDataset.value = dataset
  approveError.value = null
  try {
    const result = await intake.approveDraft(dataset)
    const summary = result.reprocessed?.batch
      ? t('steward.rowsSummary', { bronze: num(result.reprocessed.batch.rowsBronze), silver: num(result.reprocessed.batch.rowsSilver), quarantine: num(result.reprocessed.batch.rowsQuarantine) })
      : null
    approveMessage.value[dataset] = summary ? t('steward.draftApprovedReprocessed', { summary }) : t('steward.draftApprovedNoSource')
    await Promise.all([loadDrafts(), loadBatches()])
  } catch (e) {
    approveError.value = e
  } finally {
    approvingDataset.value = null
  }
}

async function loadQuarantine() {
  if (!quarantineDataset.value.trim()) return
  quarantineLoading.value = true
  quarantineError.value = null
  try {
    const response = await intake.quarantine(quarantineDataset.value.trim(), quarantineBatchId.value.trim() || undefined)
    quarantineRows.value = response.items
    quarantineTotal.value = response.total
  } catch (e) {
    quarantineError.value = e
    quarantineRows.value = []
    quarantineTotal.value = 0
  } finally {
    quarantineLoading.value = false
  }
}

onMounted(async () => {
  await Promise.all([loadBatches(), loadDrafts()])
})
</script>

<template>
  <PageShell :title="t('steward.title')" :lead="t('steward.lead')">
    <ErrorBox :error="error" />

    <div class="card">
      <h2>{{ t('steward.uploadTitle') }}</h2>
      <div class="actions" style="align-items: center">
        <input ref="fileInput" type="file" accept=".csv,.txt" :aria-label="t('steward.chooseFile')" />
        <Button :label="t('steward.upload')" icon="pi pi-upload" :loading="uploading" @click="upload" />
      </div>
      <ErrorBox :error="uploadError" />
      <div v-if="uploadResult" class="muted" style="margin-top: 8px">
        <p v-if="uploadResult.status === 'unknown'">
          {{ t('steward.uploadedUnknown', { dataset: uploadResult.dataset }) }}
        </p>
        <p v-else-if="uploadResult.status === 'blocked'">
          {{ t('steward.uploadedBlocked', { error: uploadResult.batch?.error ?? '' }) }}
        </p>
        <template v-else>
          <p>{{ t('steward.uploadedKnown', { dataset: uploadResult.batch?.dataset, kind: uploadResult.matchKind, score: uploadResult.matchScore?.toFixed(2) }) }}</p>
          <p v-if="uploadResult.batch">{{ t('steward.rowsSummary', { bronze: num(uploadResult.batch.rowsBronze), silver: num(uploadResult.batch.rowsSilver), quarantine: num(uploadResult.batch.rowsQuarantine) }) }}</p>
          <p v-if="uploadResult.batch?.gold?.rebuilt.length">{{ t('steward.goldRebuilt', { tables: uploadResult.batch.gold.rebuilt.map((r) => r.table).join(', ') }) }}</p>
          <p v-if="uploadResult.batch?.gold?.warning">{{ uploadResult.batch.gold.warning }}</p>
          <p v-if="uploadResult.batch?.eventId">{{ t('steward.eventPublished') }}</p>
        </template>
      </div>
    </div>

    <div class="card" style="margin-top: 16px">
      <h2>{{ t('steward.batches') }}</h2>
      <DataTable :value="items" size="small" paginator :rows="20">
        <Column field="receivedAt" :header="t('steward.received')"><template #body="{ data }">{{ dateTime(data.receivedAt) }}</template></Column>
        <Column field="dataset" :header="t('steward.dataset')" />
        <Column field="status" :header="t('steward.status')"><template #body="{ data }"><StatusTag :value="data.status" :tone="data.status === 'loaded' ? 'ok' : 'warn'" /></template></Column>
        <Column :header="t('steward.loaded')"><template #body="{ data }">{{ num(data.rowsLoaded) }}</template></Column>
        <Column :header="t('steward.quarantined')"><template #body="{ data }">{{ num(data.rowsQuarantined) }}</template></Column>
        <Column :header="t('steward.partitions')"><template #body="{ data }">{{ data.partitions.length }}</template></Column>
        <Column field="batchId" :header="t('steward.batch')" />
      </DataTable>
      <p v-if="items.length === 0" class="muted">{{ t('steward.noBatches') }} <code>make data</code> {{ t('steward.noBatchesSuffix') }}</p>
    </div>

    <div class="grid cols-2" style="margin-top: 16px">
      <div class="card">
        <h2>{{ t('steward.contractsTitle') }}</h2>
        <p class="muted">{{ t('steward.contractsHint') }}</p>
        <ErrorBox :error="approveError" />
        <p v-if="drafts.length === 0" class="muted">{{ t('steward.noDrafts') }}</p>
        <div v-for="d in drafts" :key="d.dataset" class="factor" style="align-items: flex-start; flex-direction: column; gap: 4px">
          <div style="display: flex; justify-content: space-between; width: 100%; align-items: center">
            <span><strong>{{ d.title }}</strong> <span class="muted">({{ d.dataset }}, {{ t('steward.draftColumns', { count: d.columns.length }) }})</span></span>
            <Button :label="t('steward.approveDraft')" size="small" :loading="approvingDataset === d.dataset" @click="approve(d.dataset)" />
          </div>
          <span class="muted" style="font-size: 0.85em">{{ d.columns.join(', ') }}</span>
          <span v-if="approveMessage[d.dataset]" class="muted">{{ approveMessage[d.dataset] }}</span>
        </div>
      </div>
      <div class="card">
        <h2>{{ t('steward.quarantineTitle') }}</h2>
        <p class="muted">{{ t('steward.quarantineHint') }}</p>
        <div class="form-grid">
          <div class="field"><label>{{ t('steward.quarantineDataset') }}</label><InputText v-model="quarantineDataset" @keyup.enter="loadQuarantine" /></div>
          <div class="field"><label>{{ t('steward.quarantineBatch') }}</label><InputText v-model="quarantineBatchId" @keyup.enter="loadQuarantine" /></div>
        </div>
        <div class="actions"><Button :label="t('steward.quarantineLoad')" size="small" :loading="quarantineLoading" @click="loadQuarantine" /></div>
        <ErrorBox :error="quarantineError" />
        <p v-if="quarantineDataset && !quarantineLoading && quarantineRows.length === 0" class="muted">{{ t('steward.quarantineEmpty') }}</p>
        <template v-if="quarantineRows.length">
          <p class="muted">{{ t('steward.quarantineTotal', { total: num(quarantineTotal), shown: num(quarantineRows.length) }) }}</p>
          <DataTable :value="quarantineRows" size="small" paginator :rows="10" scrollable scroll-height="300px">
            <Column v-for="col in quarantineColumns" :key="col" :field="col" :header="col" />
          </DataTable>
        </template>
      </div>
    </div>
  </PageShell>
</template>
