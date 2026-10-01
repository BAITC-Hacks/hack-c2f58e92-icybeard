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
import KpiRow from '@/components/ui/KpiRow.vue'
import KpiTile from '@/components/ui/KpiTile.vue'
import PageShell from '@/components/ui/PageShell.vue'
import SidePanel from '@/components/ui/SidePanel.vue'
import Skeleton from '@/components/ui/Skeleton.vue'
import StatusTag from '@/components/ui/StatusTag.vue'
import { useLocaleFormat } from '@/composables/useLocaleFormat'
import { dateShort } from '@/lib/route'

/** Консоль стюарда (W-Steward): «Опубликовать витрину» — загрузка файла в Data Intake Fabric; четыре KPI (срез данных,
 * последняя публикация, источников прошли контракт, предупреждения качества) и таблица «Источники» — по партиям
 * /intake/batches (последняя партия каждого набора); справа «Конвейер публикации» (шаги bronze/silver/gold/PostgreSQL —
 * описание по docs, статус по партиям) и «Запросы к организаторам» (№ 6, 9, 11 — статично). Черновики контрактов
 * и ручной карантин — свёрнуты; панель партии справа. */
const STATUS_TONES: Record<string, 'ok' | 'warn' | 'danger' | 'neutral'> = { loaded: 'ok', quarantined: 'warn', blocked: 'danger', failed: 'danger' }
const PIPELINE = ['bronze', 'silver', 'gold', 'postgres'] as const
const REQUESTS = [{ key: 'r6', open: true }, { key: 'r9', open: true }, { key: 'r11', open: false }] as const
const { t } = useI18n()
const { num, dateTime } = useLocaleFormat()
const items = ref<Batch[]>([])
const loading = ref(true)
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
const selected = ref<Batch | null>(null)
const panelOpen = ref(false)
const panelRows = ref<Record<string, unknown>[]>([])
const panelBusy = ref(false)
const panelError = ref<unknown>(null)

const statusTone = (status: string) => STATUS_TONES[status] ?? 'neutral'
/** Последняя партия каждого набора — строка таблицы «Источники». */
const sources = computed(() => {
  const latest = new Map<string, Batch>()
  for (const b of [...items.value].sort((a, c) => (a.receivedAt < c.receivedAt ? -1 : 1))) latest.set(b.dataset, b)
  return [...latest.values()].sort((a, b) => a.dataset.localeCompare(b.dataset))
})
const lastPublished = computed(() => items.value.map((b) => b.receivedAt).sort().at(-1) ?? null)
const dataSlice = computed(() => items.value.map((b) => b.occurredAt).filter((d): d is string => !!d).sort().at(-1) ?? null)
const contractPassed = computed(() => sources.value.filter((b) => b.status === 'loaded').length)
const warnings = computed(() => sources.value.filter((b) => b.rowsQuarantined > 0 || b.status !== 'loaded').length)
const periodOf = (b: Batch) => (b.partitions.length ? `${b.partitions[0]}${b.partitions.length > 1 ? ` — ${b.partitions.at(-1)}` : ''}` : '—')

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
  <PageShell :title="t('steward.title')">
    <template #subtitle>{{ t('steward.subtitle') }}<template v-if="lastPublished"> · {{ t('steward.lastPublish', { date: dateTime(lastPublished) }) }}</template></template>
    <template #actions>
      <input ref="fileInput" type="file" accept=".csv,.txt,.parquet" hidden :aria-label="t('steward.chooseFile')" data-testid="steward-file" @change="onPick" />
      <Button :label="uploading ? t('steward.uploading') : t('steward.publish')" icon="pi pi-cloud-upload" :loading="uploading" data-testid="steward-publish" @click="fileInput?.click()" />
    </template>
    <ErrorBox :error="error" />
    <ErrorBox :error="uploadError" />
    <div v-if="uploadResult" class="card small result">
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

    <KpiRow data-testid="steward-kpis">
      <KpiTile :value="dataSlice ? dateShort(dataSlice) : '—'" :label="t('steward.kpiSlice')" :loading="loading" />
      <KpiTile :value="lastPublished ? dateShort(lastPublished) : '—'" :label="t('steward.kpiPublished')" :hint="lastPublished ? dateTime(lastPublished) : undefined" :loading="loading" />
      <KpiTile :value="`${contractPassed} / ${sources.length}`" :label="t('steward.kpiContract')" :loading="loading" />
      <KpiTile :value="warnings" :label="t('steward.kpiWarnings')" :tone="warnings ? 'warn' : undefined" :loading="loading" />
    </KpiRow>

    <div class="main-grid">
      <AppCard :title="t('steward.sourcesTitle')">
        <template #header><span class="caption">{{ items.length }} · {{ t('steward.batches').toLowerCase() }}</span></template>
        <Skeleton v-if="loading" kind="table" :lines="6" />
        <EmptyState v-else-if="sources.length === 0" :title="t('steward.noBatches')" icon="pi pi-database"><code>make data</code> <span class="muted small">{{ t('steward.noBatchesSuffix') }}</span></EmptyState>
        <div v-else class="table-wrap">
          <table class="dense-table" data-testid="batches-table">
            <thead><tr><th>{{ t('steward.dataset') }}</th><th class="num">{{ t('steward.colRows') }}</th><th>{{ t('steward.colPeriod') }}</th><th>{{ t('steward.colContract') }}</th><th>{{ t('steward.colQuality') }}</th></tr></thead>
            <tbody>
              <tr v-for="b in sources" :key="b.batchId" class="clickable" :class="{ quarantine: b.rowsQuarantined > 0 || b.status !== 'loaded', selected: selected?.batchId === b.batchId && panelOpen }" @click="openBatch(b)">
                <td><span class="mono strong">{{ b.dataset }}</span><div class="caption">{{ dateTime(b.receivedAt) }}</div></td>
                <td class="num">{{ num(b.rowsLoaded) }}</td>
                <td class="caption tabular period">{{ periodOf(b) }}</td>
                <td class="nowrap"><StatusTag :value="b.status === 'loaded' ? t('steward.contractOk') : b.status" :tone="statusTone(b.status)" /></td>
                <td class="nowrap"><StatusTag :value="b.rowsQuarantined > 0 ? t('steward.qualityWarn', { n: num(b.rowsQuarantined) }) : t('steward.qualityOk')" :tone="b.rowsQuarantined > 0 ? 'warn' : 'ok'" /></td>
              </tr>
            </tbody>
          </table>
        </div>
      </AppCard>

      <div class="col">
        <AppCard :title="t('steward.pipelineTitle')">
          <template #header><span class="caption">{{ t('steward.pipelineCaption', { done: contractPassed, total: sources.length }) }}</span></template>
          <div class="rows">
            <div v-for="step in PIPELINE" :key="step" class="row step-row">
              <span class="step-dot" :class="{ warn: step === 'silver' && warnings > 0 }" aria-hidden="true"><i class="pi pi-check" /></span>
              <span class="row-main"><span>{{ t('steward.pipeline.' + step) }}</span><span class="row-sub">{{ step === 'postgres' && lastPublished ? dateTime(lastPublished) : t('steward.pipeline.' + step + 'Note') }}</span></span>
            </div>
          </div>
        </AppCard>
        <AppCard :title="t('steward.requestsTitle')">
          <div class="rows">
            <div v-for="r in REQUESTS" :key="r.key" class="row"><span class="row-main">{{ t('steward.requests.' + r.key) }}</span><span class="row-value"><StatusTag :value="r.open ? t('steward.requestOpen') : t('steward.requestPlanned')" :tone="r.open ? 'warn' : 'neutral'" /></span></div>
          </div>
        </AppCard>
      </div>
    </div>

    <CollapsibleSection :title="t('steward.contractsTitle')" :summary="String(drafts.length)" :tone="drafts.length ? 'warn' : undefined">
      <p class="muted small">{{ t('steward.contractsHint') }}</p>
      <ErrorBox :error="approveError" />
      <p v-if="drafts.length === 0" class="muted">{{ t('steward.noDrafts') }}</p>
      <div v-for="d in drafts" :key="d.dataset" class="row draft">
        <div class="row-main">
          <span class="strong">{{ d.title }}</span> <span class="muted small">({{ d.dataset }}, {{ t('steward.draftColumns', { count: d.columns.length }) }})</span>
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
            <div class="row-main"><div v-for="(value, key) in row" :key="key" class="small"><span class="muted">{{ key }}:</span> <span class="mono">{{ value }}</span></div></div>
          </div>
        </div>
      </template>
    </SidePanel>
  </PageShell>
</template>

<style scoped>
.result { padding: 12px 16px; }
.result p { margin: 2px 0; }
.main-grid { display: grid; grid-template-columns: minmax(0, 1.5fr) minmax(0, 1fr); gap: var(--dm-space-4); align-items: start; }
.period { max-width: 180px; }
.nowrap { white-space: nowrap; }
.col { display: flex; flex-direction: column; gap: var(--dm-space-4); min-width: 0; }
.strong { font-weight: var(--fw-bold); }
.step-row { justify-content: flex-start; gap: 12px; }
.step-row .row-main { display: flex; flex-direction: column; gap: 2px; }
.step-dot { width: 22px; height: 22px; border-radius: 50%; background: var(--dm-ok-soft); color: var(--dm-ok); display: grid; place-items: center; font-size: 12px; flex: none; }
.step-dot.warn { background: var(--dm-warn-soft); color: var(--dm-warn); }
.draft { align-items: flex-start; }
.panel-sub { font-size: var(--dm-text-base); margin: 16px 0 8px; }
@media (max-width: 1000px) { .main-grid { grid-template-columns: 1fr; } }
</style>
