<script setup lang="ts">
import Button from 'primevue/button'
import InputText from 'primevue/inputtext'
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { intake } from '@/api/endpoints'
import type { Batch, IntakeDraftSummary, IntakeUploadResult } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import AppCard from '@/components/ui/AppCard.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import KpiRow from '@/components/ui/KpiRow.vue'
import KpiTile from '@/components/ui/KpiTile.vue'
import PageShell from '@/components/ui/PageShell.vue'
import SearchSelect from '@/components/ui/SearchSelect.vue'
import SidePanel from '@/components/ui/SidePanel.vue'
import Skeleton from '@/components/ui/Skeleton.vue'
import StatusTag from '@/components/ui/StatusTag.vue'
import { useLocaleFormat } from '@/composables/useLocaleFormat'
import { dateShort } from '@/lib/route'

/** Консоль оператора данных (W-Steward) для обычного пользователя, сверху вниз: кнопка «Загрузить файл с данными»
 * (Data Intake Fabric), результат загрузки словами; четыре KPI (данные по состоянию на, последнее обновление,
 * наборов без ошибок, требуют внимания); если есть файлы с незнакомой структурой — карточка с черновиками описаний
 * и кнопкой «Утвердить и обработать» (выше таблицы: это единственное действие, которое ждёт оператора);
 * «Конвейер публикации» — горизонтальная полоса из четырёх шагов словами (технические имена bronze/silver/gold
 * мелкой пилюлей); таблица «Загруженные данные» на всю ширину — последняя партия каждого набора /intake/batches
 * с человеческими названиями наборов (admin.orgs.dataset.*) и периодами из партиций; внизу в один ряд «Отклонённые
 * строки (карантин)» (набор выбирается из списка, а не вводится кодом; результат — отдельной широкой карточкой ниже)
 * и «Запросы на дополнительные данные» (№ 6, 9, 11 — статично). Блоки идут на всю ширину или парами одинаковой
 * высоты, чтобы при малом числе наборов не оставалось пустых колонок. Панель партии справа. */
const STATUS_TONES: Record<string, 'ok' | 'warn' | 'danger' | 'neutral'> = { loaded: 'ok', quarantined: 'warn', blocked: 'danger', failed: 'danger' }
const PIPELINE = ['bronze', 'silver', 'gold', 'postgres'] as const
const REQUESTS = [{ key: 'r6', n: 6, open: true }, { key: 'r9', n: 9, open: true }, { key: 'r11', n: 11, open: false }] as const
const PANEL_ROWS = 20
const REASON_KEY = '_quarantine_reason'
const { t, te } = useI18n()
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
const quarantineDataset = ref<string | null>(null)
const quarantineBatchId = ref('')
const quarantineLoading = ref(false)
const quarantineError = ref<unknown>(null)
const quarantineRows = ref<Record<string, unknown>[]>([])
const quarantineTotal = ref(0)
const quarantineAsked = ref(false)
/** Колонки результата карантина: причина первой, остальные — как пришли. */
const quarantineColumns = computed(() => {
  const keys = quarantineRows.value[0] ? Object.keys(quarantineRows.value[0]) : []
  return keys.includes(REASON_KEY) ? [REASON_KEY, ...keys.filter((k) => k !== REASON_KEY)] : keys
})
const selected = ref<Batch | null>(null)
const panelOpen = ref(false)
const panelRows = ref<Record<string, unknown>[]>([])
const panelBusy = ref(false)
const panelError = ref<unknown>(null)

const statusTone = (status: string) => STATUS_TONES[status] ?? 'neutral'
/** Статус партии словами («принят», «не принят»); незнакомый статус API — как есть. */
const statusLabel = (status: string) => (te(`steward.status.${status}`) ? t(`steward.status.${status}`) : status)
/** Название набора для людей (admin.orgs.dataset.*), код — мелкой подписью рядом. */
const datasetTitle = (dataset: string) => (te(`admin.orgs.dataset.${dataset}`) ? t(`admin.orgs.dataset.${dataset}`) : dataset)
/** Последняя партия каждого набора — строка таблицы «Загруженные данные». */
const sources = computed(() => {
  const latest = new Map<string, Batch>()
  for (const b of [...items.value].sort((a, c) => (a.receivedAt < c.receivedAt ? -1 : 1))) latest.set(b.dataset, b)
  return [...latest.values()].sort((a, b) => datasetTitle(a.dataset).localeCompare(datasetTitle(b.dataset)))
})
const lastPublished = computed(() => items.value.map((b) => b.receivedAt).sort().at(-1) ?? null)
const dataSlice = computed(() => items.value.map((b) => b.occurredAt).filter((d): d is string => !!d).sort().at(-1) ?? null)
const contractPassed = computed(() => sources.value.filter((b) => b.status === 'loaded').length)
const warnings = computed(() => sources.value.filter((b) => b.rowsQuarantined > 0 || b.status !== 'loaded').length)
const datasetOptions = computed(() => sources.value.map((b) => ({ code: b.dataset, label: `${datasetTitle(b.dataset)} · ${b.dataset}` })))

/** Период партии словами из партиций: `p_month=2025-01` → «01.2025 — 03.2025», `p_date=2026-04-30` → «на 30.04.2026»;
 * ключи region_kato и прочие не показываются (полная строка партиций — в панели партии). */
function periodOf(b: Batch): string {
  const months = new Set<string>()
  const dates = new Set<string>()
  for (const p of b.partitions) {
    const month = /p_month=(\d{4})-(\d{2})/.exec(p)
    const date = /p_date=(\d{4}-\d{2}-\d{2})/.exec(p)
    if (month) months.add(`${month[2]}.${month[1]}`)
    if (date) dates.add(date[1]!)
  }
  const byTime = (a: string, b: string) => a.slice(3) + a.slice(0, 2) < b.slice(3) + b.slice(0, 2) ? -1 : 1
  if (months.size) {
    const sorted = [...months].sort(byTime)
    return sorted.length > 1 ? `${sorted[0]} — ${sorted.at(-1)}` : sorted[0]!
  }
  if (dates.size) {
    const sorted = [...dates].sort()
    return t('steward.periodOn', { date: sorted.length > 1 ? `${dateShort(sorted[0]!)} — ${dateShort(sorted.at(-1)!)}` : dateShort(sorted[0]!) })
  }
  return b.partitions.length ? `${b.partitions[0]}${b.partitions.length > 1 ? ` — ${b.partitions.at(-1)}` : ''}` : '—'
}
/** Состояние шага конвейера: silver — предупреждение при карантине, публикация — пусто, пока ничего не публиковалось. */
function stepTone(step: (typeof PIPELINE)[number]): 'ok' | 'warn' | 'idle' {
  if (sources.value.length === 0) return 'idle'
  if (step === 'silver' && warnings.value > 0) return 'warn'
  if (step === 'postgres' && !lastPublished.value) return 'idle'
  return 'ok'
}
/** Причина карантина — отдельной строкой, остальные поля строки — списком. */
const reasonOf = (row: Record<string, unknown>) => (row[REASON_KEY] == null ? null : String(row[REASON_KEY]))
const fieldsOf = (row: Record<string, unknown>) => Object.entries(row).filter(([key]) => key !== REASON_KEY)

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
  const dataset = quarantineDataset.value
  if (!dataset) return
  quarantineLoading.value = true
  quarantineError.value = null
  quarantineAsked.value = true
  try {
    const response = await intake.quarantine(dataset, quarantineBatchId.value.trim() || undefined)
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

/** Панель партии: факты и отклонённые строки этой партии (в каждой — причина, по которой строка не прошла проверку). */
async function openBatch(batch: Batch) {
  selected.value = batch
  panelOpen.value = true
  panelRows.value = []
  panelError.value = null
  if (batch.rowsQuarantined === 0 && batch.status === 'loaded') return
  panelBusy.value = true
  try {
    panelRows.value = (await intake.quarantine(batch.dataset, batch.batchId)).items.slice(0, PANEL_ROWS)
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
    <div v-if="uploadResult" class="card notice" :class="uploadResult.status === 'blocked' ? 'danger' : uploadResult.status === 'unknown' ? 'warn' : 'ok'" role="status">
      <p v-if="uploadResult.status === 'unknown'">{{ t('steward.uploadedUnknown', { dataset: uploadResult.dataset }) }}</p>
      <p v-else-if="uploadResult.status === 'blocked'">{{ t('steward.uploadedBlocked', { error: uploadResult.batch?.error ?? '' }) }}</p>
      <template v-else>
        <p>{{ t('steward.uploadedKnown', { dataset: datasetTitle(uploadResult.batch?.dataset ?? ''), score: uploadResult.matchScore?.toFixed(2) }) }}</p>
        <p v-if="uploadResult.batch" class="caption">{{ t('steward.rowsSummary', { bronze: num(uploadResult.batch.rowsBronze), silver: num(uploadResult.batch.rowsSilver), quarantine: num(uploadResult.batch.rowsQuarantine) }) }}</p>
        <p v-if="uploadResult.batch?.gold?.rebuilt.length" class="caption">{{ t('steward.goldRebuilt', { tables: uploadResult.batch.gold.rebuilt.map((r) => r.table).join(', ') }) }}</p>
        <p v-if="uploadResult.batch?.gold?.warning" class="caption">{{ uploadResult.batch.gold.warning }}</p>
        <p v-if="uploadResult.batch?.eventId" class="caption">{{ t('steward.eventPublished') }}</p>
      </template>
    </div>

    <KpiRow data-testid="steward-kpis">
      <KpiTile label-first :value="dataSlice ? dateShort(dataSlice) : '—'" :label="t('steward.kpiSlice')" :loading="loading" />
      <KpiTile label-first :value="lastPublished ? dateShort(lastPublished) : '—'" :label="t('steward.kpiPublished')" :hint="lastPublished ? dateTime(lastPublished) : undefined" :loading="loading" />
      <KpiTile label-first :value="`${contractPassed} / ${sources.length}`" :label="t('steward.kpiContract')" :loading="loading" />
      <KpiTile label-first :value="warnings" :label="t('steward.kpiWarnings')" :hint="warnings ? t('steward.kpiWarningsHint') : t('steward.kpiWarningsNone')" :tone="warnings ? 'warn' : undefined" :loading="loading" />
    </KpiRow>

    <AppCard v-if="drafts.length" :title="t('steward.contractsTitle')" class="attention" data-testid="steward-drafts">
      <template #header><StatusTag :value="t('steward.contractsCount', { n: drafts.length })" tone="warn" /></template>
      <p class="caption card-lead">{{ t('steward.contractsHint') }}</p>
      <ErrorBox :error="approveError" />
      <div class="rows">
        <div v-for="d in drafts" :key="d.dataset" class="row draft">
          <div class="row-main">
            <span class="strong">{{ d.title }}</span> <span class="caption">{{ d.dataset }} · {{ t('steward.draftColumns', { count: d.columns.length }) }}</span>
            <div class="row-sub mono small">{{ d.columns.join(', ') }}</div>
            <div v-if="approveMessage[d.dataset]" class="row-sub ok-text">{{ approveMessage[d.dataset] }}</div>
          </div>
          <div class="row-value"><Button :label="t('steward.approveDraft')" size="small" :loading="approvingDataset === d.dataset" @click="approve(d.dataset)" /></div>
        </div>
      </div>
    </AppCard>
    <ErrorBox v-else :error="approveError" />

    <AppCard :title="t('steward.pipelineTitle')" data-testid="steward-pipeline">
      <template #header><span class="caption">{{ t('steward.pipelineCaption', { done: contractPassed, total: sources.length }) }}</span></template>
      <p class="caption card-lead">{{ t('steward.pipelineLead') }}</p>
      <ol class="steps">
        <li v-for="(step, i) in PIPELINE" :key="step" class="step">
          <span class="step-dot" :class="stepTone(step)" aria-hidden="true"><i :class="stepTone(step) === 'idle' ? 'pi pi-minus' : 'pi pi-check'" /></span>
          <span class="step-body">
            <span class="step-title"><span class="step-n caption">{{ i + 1 }}.</span> {{ t('steward.pipeline.' + step) }} <span class="stage mono">{{ t('steward.stage.' + step) }}</span></span>
            <span class="row-sub">{{ step === 'postgres' && lastPublished ? dateTime(lastPublished) : t('steward.pipeline.' + step + 'Note') }}</span>
          </span>
        </li>
      </ol>
    </AppCard>

    <AppCard :title="t('steward.sourcesTitle')">
      <template #header><span class="caption">{{ t('steward.batches', { n: items.length }) }}</span></template>
      <p class="caption card-lead">{{ t('steward.sourcesLead') }}</p>
      <Skeleton v-if="loading" kind="table" :lines="6" />
      <EmptyState v-else-if="sources.length === 0" :title="t('steward.noBatches')" :text="t('steward.noBatchesHint')" icon="pi pi-database" />
      <div v-else class="table-wrap">
        <table class="dense-table" data-testid="batches-table">
          <thead><tr><th>{{ t('steward.dataset') }}</th><th class="num">{{ t('steward.colRows') }}</th><th>{{ t('steward.colPeriod') }}</th><th>{{ t('steward.colContract') }}</th><th>{{ t('steward.colQuality') }}</th></tr></thead>
          <tbody>
            <tr v-for="b in sources" :key="b.batchId" class="clickable" :class="{ quarantine: b.rowsQuarantined > 0 || b.status !== 'loaded', selected: selected?.batchId === b.batchId && panelOpen }" @click="openBatch(b)">
              <td><span class="strong">{{ datasetTitle(b.dataset) }}</span><div class="caption"><span class="mono">{{ b.dataset }}</span> · {{ dateTime(b.receivedAt) }}</div></td>
              <td class="num">{{ num(b.rowsLoaded) }}</td>
              <td class="tabular period" :title="b.partitions.join(', ')">{{ periodOf(b) }}</td>
              <td class="nowrap"><StatusTag :value="statusLabel(b.status)" :tone="statusTone(b.status)" /></td>
              <td class="nowrap"><StatusTag :value="b.rowsQuarantined > 0 ? t('steward.qualityWarn', { n: num(b.rowsQuarantined) }) : t('steward.qualityOk')" :tone="b.rowsQuarantined > 0 ? 'warn' : 'ok'" /></td>
            </tr>
          </tbody>
        </table>
      </div>
    </AppCard>

    <div class="bottom-grid">
      <AppCard :title="t('steward.quarantineTitle')" data-testid="steward-quarantine">
        <p class="caption card-lead">{{ t('steward.quarantineHint') }}</p>
        <div class="form-grid">
          <div class="field"><label>{{ t('steward.quarantineDataset') }}</label><SearchSelect v-model="quarantineDataset" :options="datasetOptions" option-label="label" option-value="code" :placeholder="t('steward.quarantinePick')" /></div>
          <div class="field"><label>{{ t('steward.quarantineBatch') }}</label><InputText v-model="quarantineBatchId" class="mono" @keyup.enter="loadQuarantine" /></div>
        </div>
        <div class="actions"><Button :label="t('steward.quarantineLoad')" size="small" :loading="quarantineLoading" :disabled="!quarantineDataset" @click="loadQuarantine" /></div>
        <ErrorBox :error="quarantineError" />
        <p v-if="quarantineAsked && !quarantineLoading && !quarantineError && quarantineRows.length === 0" class="muted">{{ t('steward.quarantineEmpty') }}</p>
      </AppCard>
      <AppCard :title="t('steward.requestsTitle')">
        <p class="caption card-lead">{{ t('steward.requestsLead') }}</p>
        <div class="rows">
          <div v-for="r in REQUESTS" :key="r.key" class="row">
            <span class="row-main">{{ t('steward.requests.' + r.key) }}<div class="row-sub">{{ t('steward.requestNo', { n: r.n }) }}</div></span>
            <span class="row-value"><StatusTag :value="r.open ? t('steward.requestOpen') : t('steward.requestPlanned')" :tone="r.open ? 'warn' : 'neutral'" /></span>
          </div>
        </div>
      </AppCard>
    </div>

    <AppCard v-if="quarantineRows.length" :title="`${t('steward.quarantineTitle')} · ${datasetTitle(quarantineDataset ?? '')}`" data-testid="steward-quarantine-rows">
      <template #header><span class="caption">{{ t('steward.quarantineTotal', { total: num(quarantineTotal), shown: num(quarantineRows.length) }) }}</span></template>
      <div class="table-wrap">
        <table class="dense-table">
          <thead><tr><th v-for="col in quarantineColumns" :key="col">{{ col === REASON_KEY ? t('steward.reason') : col }}</th></tr></thead>
          <tbody><tr v-for="(row, i) in quarantineRows" :key="i"><td v-for="col in quarantineColumns" :key="col" :class="{ 'reason-cell': col === REASON_KEY }">{{ row[col] }}</td></tr></tbody>
        </table>
      </div>
    </AppCard>

    <SidePanel v-model:visible="panelOpen" :title="selected ? datasetTitle(selected.dataset) : ''" :subtitle="selected ? `${selected.dataset} · ${t('steward.received').toLowerCase()} ${dateTime(selected.receivedAt)}` : ''">
      <template v-if="selected">
        <dl class="facts">
          <dt>{{ t('steward.colContract') }}</dt><dd><StatusTag :value="statusLabel(selected.status)" :tone="statusTone(selected.status)" /></dd>
          <dt>{{ t('steward.loaded') }}</dt><dd class="tabular">{{ num(selected.rowsLoaded) }}</dd>
          <dt>{{ t('steward.quarantined') }}</dt><dd class="tabular">{{ num(selected.rowsQuarantined) }}</dd>
          <dt>{{ t('steward.occurredAt') }}</dt><dd class="tabular">{{ selected.occurredAt ? dateTime(selected.occurredAt) : '—' }}</dd>
          <dt>{{ t('steward.partitions') }}</dt><dd>{{ periodOf(selected) }}<div class="caption mono">{{ selected.partitions.join(', ') || '—' }}</div></dd>
          <dt>{{ t('steward.panelBatch') }}</dt><dd class="mono small">{{ selected.batchId }}</dd>
        </dl>
        <template v-if="selected.status !== 'loaded' || selected.rowsQuarantined > 0">
          <h3 class="panel-sub">{{ selected.status !== 'loaded' ? t('steward.blockReason') : t('steward.rejectedTitle') }} <span v-if="panelRows.length === PANEL_ROWS" class="caption">· {{ t('steward.rejectedShown', { n: PANEL_ROWS }) }}</span></h3>
          <ErrorBox :error="panelError" />
          <Skeleton v-if="panelBusy" :lines="4" />
          <p v-else-if="panelRows.length === 0" class="muted small">{{ selected.status !== 'loaded' ? t('steward.blockReasonMissing') : t('steward.quarantineEmpty') }}</p>
          <div v-else class="rows">
            <div v-for="(row, i) in panelRows" :key="i" class="row rejected">
              <div class="row-main">
                <div v-if="reasonOf(row)" class="reason">{{ reasonOf(row) }}</div>
                <div class="fields caption"><span v-for="[key, value] in fieldsOf(row)" :key="key" class="field-pair"><span class="muted">{{ key }}:</span> <span class="mono">{{ value }}</span></span></div>
              </div>
            </div>
          </div>
        </template>
      </template>
    </SidePanel>
  </PageShell>
</template>

<style scoped>
.notice { padding: 14px 20px; border-left: 4px solid var(--dm-ok); }
.notice.warn { border-left-color: var(--dm-warn); }
.notice.danger { border-left-color: var(--dm-danger); }
.notice p { margin: 2px 0; line-height: 1.5; }
.card-lead { margin: -4px 0 12px; line-height: 1.5; }
.attention { box-shadow: inset 0 0 0 1.5px color-mix(in srgb, var(--dm-warn) 55%, transparent); }
.period { max-width: 200px; white-space: nowrap; }
.nowrap { white-space: nowrap; }
.strong { font-weight: var(--fw-bold); }
.ok-text { color: var(--dm-ok); }
.steps { list-style: none; margin: 0; padding: 0; display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); }
.step { display: flex; gap: 12px; align-items: flex-start; padding: 2px 16px 2px 0; min-width: 0; }
.step + .step { padding-left: 16px; border-left: 1px solid var(--dm-hairline); }
.step-body { display: flex; flex-direction: column; gap: 3px; min-width: 0; }
.step-title { display: inline-flex; align-items: center; gap: 6px; flex-wrap: wrap; font-weight: var(--fw-bold); line-height: 1.3; }
.step-n { font-weight: 400; }
.bottom-grid { display: grid; grid-template-columns: minmax(0, 1.4fr) minmax(0, 1fr); gap: var(--dm-space-4); align-items: stretch; }
.stage { font-size: 11px; padding: 1px 7px; border-radius: 999px; background: var(--surface-muted); color: var(--text-muted); }
.step-dot { width: 22px; height: 22px; margin-top: 1px; border-radius: 50%; background: var(--dm-ok-soft); color: var(--dm-ok); display: grid; place-items: center; font-size: 12px; flex: none; }
.step-dot.warn { background: var(--dm-warn-soft); color: var(--dm-warn); }
.step-dot.idle { background: var(--surface-muted); color: var(--text-muted); }
.draft { align-items: flex-start; }
.panel-sub { font-size: var(--dm-text-base); margin: 20px 0 8px; display: flex; align-items: baseline; gap: 6px; flex-wrap: wrap; }
.rejected { align-items: flex-start; }
.reason { font-weight: var(--fw-bold); color: var(--dm-danger); margin-bottom: 4px; line-height: 1.4; }
.fields { display: flex; flex-wrap: wrap; gap: 2px 14px; }
.field-pair { white-space: nowrap; }
.reason-cell { color: var(--dm-danger); font-weight: var(--fw-semibold); }
@media (max-width: 1000px) { .bottom-grid { grid-template-columns: 1fr; } }
@media (max-width: 900px) { .steps { grid-template-columns: 1fr; } .step { padding: 10px 0; } .step + .step { padding-left: 0; border-left: 0; border-top: 1px solid var(--dm-hairline); } }
</style>
