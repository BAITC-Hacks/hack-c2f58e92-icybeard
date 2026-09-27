<script setup lang="ts">
import Button from 'primevue/button'
import InputText from 'primevue/inputtext'
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { intake } from '@/api/endpoints'
import type { Batch, IntakeDraftSummary, IntakeUploadResult } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import AppCard from '@/components/ui/AppCard.vue'
import CollapsibleSection from '@/components/ui/CollapsibleSection.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import PageShell from '@/components/ui/PageShell.vue'
import SidePanel from '@/components/ui/SidePanel.vue'
import Skeleton from '@/components/ui/Skeleton.vue'
import StatusTag from '@/components/ui/StatusTag.vue'
import { useLocaleFormat } from '@/composables/useLocaleFormat'

/** Консоль стюарда: зона drag-and-drop с ожидаемыми наборами, таблица партий с чипами статусов и подсветкой
 * карантина, панель партии справа (строки карантина с причиной); черновики контрактов и ручной карантин — свёрнуты. */
const STATUS_TONES: Record<string, 'ok' | 'warn' | 'danger' | 'neutral'> = { loaded: 'ok', quarantined: 'warn', blocked: 'danger', failed: 'danger' }
const { t } = useI18n()
const { num, dateTime } = useLocaleFormat()
const items = ref<Batch[]>([])
const loading = ref(true)
const error = ref<unknown>(null)
const fileInput = ref<HTMLInputElement | null>(null)
const dragging = ref(false)
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
// панель партии
const selected = ref<Batch | null>(null)
const panelOpen = ref(false)
const panelRows = ref<Record<string, unknown>[]>([])
const panelBusy = ref(false)
const panelError = ref<unknown>(null)

/** Ожидаемые наборы — все наборы, которые стенд уже видел в партиях и черновиках. */
const expectedDatasets = computed(() => [...new Set([...items.value.map((b) => b.dataset), ...drafts.value.map((d) => d.dataset)])].sort())
const statusTone = (status: string) => STATUS_TONES[status] ?? 'neutral'

async function loadBatches() {
  try {
    items.value = (await intake.batches({ size: 100 })).items
  } catch (e) {
    error.value = e
  } finally {
    loading.value = false
  }
}

async function loadDrafts() {
  try {
    drafts.value = (await intake.drafts()).items
  } catch (e) {
    approveError.value = e
  }
}

async function uploadFile(file: File) {
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

function onDrop(event: DragEvent) {
  dragging.value = false
  const file = event.dataTransfer?.files?.[0]
  if (file) void uploadFile(file)
}

function onPick() {
  const file = fileInput.value?.files?.[0]
  if (file) void uploadFile(file)
}

async function approve(dataset: string) {
  approvingDataset.value = dataset
  approveError.value = null
  try {
    const result = await intake.approveDraft(dataset)
    const summary = result.reprocessed?.batch
      ? t('steward.rowsSummary', { bronze: num(result.reprocessed.batch.rowsBronze), silver: num(result.reprocessed.batch.rowsSilver), quarantine: num(result.reprocessed.batch.rowsQuarantine) })
      : null
    approveMessage.value = { ...approveMessage.value, [dataset]: summary ? t('steward.draftApprovedReprocessed', { summary }) : t('steward.draftApprovedNoSource') }
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

/** Панель партии: факты и строки карантина этой партии (в них — причина, по которой строка не прошла контракт). */
async function openBatch(batch: Batch) {
  selected.value = batch
  panelOpen.value = true
  panelRows.value = []
  panelError.value = null
  if (batch.rowsQuarantined === 0 && batch.status === 'loaded') return
  panelBusy.value = true
  try {
    panelRows.value = (await intake.quarantine(batch.dataset, batch.batchId)).items.slice(0, 20)
  } catch (e) {
    panelError.value = e
  } finally {
    panelBusy.value = false
  }
}

onMounted(async () => {
  await Promise.all([loadBatches(), loadDrafts()])
})
</script>

<template>
  <PageShell :title="t('steward.title')" :lead="t('steward.lead')">
    <ErrorBox :error="error" />

    <div
      class="dropzone card"
      :class="{ dragging, uploading }"
      data-testid="dropzone"
      @dragover.prevent="dragging = true"
      @dragleave.prevent="dragging = false"
      @drop.prevent="onDrop"
    >
      <i class="pi pi-cloud-upload" aria-hidden="true" />
      <div class="drop-title">{{ uploading ? t('steward.uploading') : t('steward.dropTitle') }}</div>
      <p class="muted small">{{ t('steward.dropText') }}</p>
      <label class="p-button p-button-secondary p-button-sm picker"><input ref="fileInput" type="file" accept=".csv,.txt" hidden :aria-label="t('steward.chooseFile')" @change="onPick" />{{ t('steward.chooseFile') }}</label>
      <div v-if="expectedDatasets.length" class="chips expected">
        <span class="muted small">{{ t('steward.expected') }}:</span>
        <StatusTag v-for="d in expectedDatasets" :key="d" :value="d" tone="neutral" />
      </div>
      <ErrorBox :error="uploadError" />
      <div v-if="uploadResult" class="muted small result">
        <p v-if="uploadResult.status === 'unknown'">{{ t('steward.uploadedUnknown', { dataset: uploadResult.dataset }) }}</p>
        <p v-else-if="uploadResult.status === 'blocked'">{{ t('steward.uploadedBlocked', { error: uploadResult.batch?.error ?? '' }) }}</p>
        <template v-else>
          <p>{{ t('steward.uploadedKnown', { dataset: uploadResult.batch?.dataset, kind: uploadResult.matchKind, score: uploadResult.matchScore?.toFixed(2) }) }}</p>
          <p v-if="uploadResult.batch">{{ t('steward.rowsSummary', { bronze: num(uploadResult.batch.rowsBronze), silver: num(uploadResult.batch.rowsSilver), quarantine: num(uploadResult.batch.rowsQuarantine) }) }}</p>
          <p v-if="uploadResult.batch?.gold?.rebuilt.length">{{ t('steward.goldRebuilt', { tables: uploadResult.batch.gold.rebuilt.map((r) => r.table).join(', ') }) }}</p>
          <p v-if="uploadResult.batch?.gold?.warning">{{ uploadResult.batch.gold.warning }}</p>
          <p v-if="uploadResult.batch?.eventId">{{ t('steward.eventPublished') }}</p>
        </template>
      </div>
    </div>

    <AppCard :title="t('steward.batches')">
      <template #header><span class="muted small">{{ items.length }}</span></template>
      <Skeleton v-if="loading" kind="table" :lines="6" />
      <EmptyState v-else-if="items.length === 0" :title="t('steward.noBatches')" icon="pi pi-database"><code>make data</code> <span class="muted small">{{ t('steward.noBatchesSuffix') }}</span></EmptyState>
      <div v-else class="table-wrap">
        <table class="dense-table" data-testid="batches-table">
          <thead><tr><th>{{ t('steward.received') }}</th><th>{{ t('steward.dataset') }}</th><th>{{ t('steward.status') }}</th><th class="num">{{ t('steward.loaded') }}</th><th class="num">{{ t('steward.quarantined') }}</th><th class="num">{{ t('steward.partitions') }}</th><th>{{ t('steward.batch') }}</th></tr></thead>
          <tbody>
            <tr v-for="b in items" :key="b.batchId" class="clickable" :class="{ quarantine: b.rowsQuarantined > 0 || b.status !== 'loaded', selected: selected?.batchId === b.batchId && panelOpen }" @click="openBatch(b)">
              <td class="nowrap">{{ dateTime(b.receivedAt) }}</td>
              <td class="mono">{{ b.dataset }}</td>
              <td><StatusTag :value="b.status" :tone="statusTone(b.status)" /></td>
              <td class="num">{{ num(b.rowsLoaded) }}</td>
              <td class="num" :class="{ 'delta-up': b.rowsQuarantined > 0 }">{{ num(b.rowsQuarantined) }}</td>
              <td class="num muted">{{ b.partitions.length }}</td>
              <td class="mono muted small">{{ b.batchId }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </AppCard>

    <div class="extras">
      <CollapsibleSection :title="t('steward.contractsTitle')" :summary="String(drafts.length)" :tone="drafts.length ? 'warn' : undefined">
        <p class="muted small">{{ t('steward.contractsHint') }}</p>
        <ErrorBox :error="approveError" />
        <p v-if="drafts.length === 0" class="muted">{{ t('steward.noDrafts') }}</p>
        <div v-for="d in drafts" :key="d.dataset" class="row draft">
          <div class="row-main">
            <b>{{ d.title }}</b> <span class="muted small">({{ d.dataset }}, {{ t('steward.draftColumns', { count: d.columns.length }) }})</span>
            <div class="row-sub mono">{{ d.columns.join(', ') }}</div>
            <div v-if="approveMessage[d.dataset]" class="row-sub">{{ approveMessage[d.dataset] }}</div>
          </div>
          <div class="row-value"><Button :label="t('steward.approveDraft')" size="small" :loading="approvingDataset === d.dataset" @click="approve(d.dataset)" /></div>
        </div>
      </CollapsibleSection>

      <CollapsibleSection :title="t('steward.quarantineTitle')" :summary="quarantineTotal ? num(quarantineTotal) : ''">
        <p class="muted small">{{ t('steward.quarantineHint') }}</p>
        <div class="form-grid">
          <div class="field"><label>{{ t('steward.quarantineDataset') }}</label><InputText v-model="quarantineDataset" @keyup.enter="loadQuarantine" /></div>
          <div class="field"><label>{{ t('steward.quarantineBatch') }}</label><InputText v-model="quarantineBatchId" @keyup.enter="loadQuarantine" /></div>
        </div>
        <div class="actions"><Button :label="t('steward.quarantineLoad')" size="small" :loading="quarantineLoading" @click="loadQuarantine" /></div>
        <ErrorBox :error="quarantineError" />
        <p v-if="quarantineDataset && !quarantineLoading && quarantineRows.length === 0" class="muted">{{ t('steward.quarantineEmpty') }}</p>
        <template v-if="quarantineRows.length">
          <p class="muted small">{{ t('steward.quarantineTotal', { total: num(quarantineTotal), shown: num(quarantineRows.length) }) }}</p>
          <div class="table-wrap">
            <table class="dense-table">
              <thead><tr><th v-for="col in quarantineColumns" :key="col">{{ col }}</th></tr></thead>
              <tbody><tr v-for="(row, i) in quarantineRows" :key="i"><td v-for="col in quarantineColumns" :key="col">{{ row[col] }}</td></tr></tbody>
            </table>
          </div>
        </template>
      </CollapsibleSection>
    </div>

    <SidePanel v-model:visible="panelOpen" :title="selected?.dataset ?? ''" :subtitle="selected ? dateTime(selected.receivedAt) : ''" width="min(560px, 100vw)">
      <template v-if="selected">
        <dl class="facts">
          <dt>{{ t('steward.status') }}</dt><dd><StatusTag :value="selected.status" :tone="statusTone(selected.status)" /></dd>
          <dt>{{ t('steward.batch') }}</dt><dd class="mono">{{ selected.batchId }}</dd>
          <dt>{{ t('steward.loaded') }}</dt><dd class="tabular">{{ num(selected.rowsLoaded) }}</dd>
          <dt>{{ t('steward.quarantined') }}</dt><dd class="tabular">{{ num(selected.rowsQuarantined) }}</dd>
          <dt>{{ t('steward.partitions') }}</dt><dd class="mono small">{{ selected.partitions.join(', ') || '—' }}</dd>
          <dt>{{ t('steward.occurredAt') }}</dt><dd class="tabular">{{ selected.occurredAt ? dateTime(selected.occurredAt) : '—' }}</dd>
        </dl>
        <h3 class="panel-sub">{{ selected.status !== 'loaded' ? t('steward.blockReason') : t('steward.quarantineTitle') }}</h3>
        <ErrorBox :error="panelError" />
        <Skeleton v-if="panelBusy" :lines="4" />
        <p v-else-if="panelRows.length === 0" class="muted small">{{ selected.status !== 'loaded' ? t('steward.blockReasonMissing') : t('steward.quarantineEmpty') }}</p>
        <div v-else class="rows">
          <div v-for="(row, i) in panelRows" :key="i" class="row">
            <div class="row-main">
              <div v-for="(value, key) in row" :key="key" class="small"><span class="muted">{{ key }}:</span> <span class="mono">{{ value }}</span></div>
            </div>
          </div>
        </div>
      </template>
    </SidePanel>
  </PageShell>
</template>

<style scoped>
.dropzone { border: 2px dashed var(--dm-hairline); text-align: center; padding: var(--dm-space-5); transition: border-color 0.15s ease, background-color 0.15s ease; }
.dropzone.dragging { border-color: var(--dm-ink); background: var(--dm-surface-2); }
.dropzone i { font-size: 1.8rem; color: var(--dm-accent); }
.drop-title { font-weight: 500; font-size: var(--dm-text-lg); margin-top: 6px; }
.picker { cursor: pointer; margin-top: 4px; }
.expected { justify-content: center; margin-top: 12px; }
.result { text-align: left; margin-top: 12px; }
.result p { margin: 2px 0; }
.nowrap { white-space: nowrap; }
.extras { display: flex; flex-direction: column; gap: var(--dm-space-3); }
.draft { align-items: flex-start; }
.panel-sub { font-size: var(--dm-text-base); margin: 16px 0 8px; }
</style>
