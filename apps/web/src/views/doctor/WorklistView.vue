<script setup lang="ts">
import Button from 'primevue/button'
import IconField from 'primevue/iconfield'
import InputIcon from 'primevue/inputicon'
import InputText from 'primevue/inputtext'
import Select from 'primevue/select'
import { useToast } from 'primevue/usetoast'
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRouter } from 'vue-router'
import { journal, route as routeApi } from '@/api/endpoints'
import type { PatientRoute, WorklistItem } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import OriginTag from '@/components/OriginTag.vue'
import AsyncState from '@/components/states/AsyncState.vue'
import StateStale from '@/components/states/StateStale.vue'
import AppCard from '@/components/ui/AppCard.vue'
import KpiRow from '@/components/ui/KpiRow.vue'
import KpiTile from '@/components/ui/KpiTile.vue'
import PageShell from '@/components/ui/PageShell.vue'
import PriorityBadge from '@/components/ui/PriorityBadge.vue'
import SidePanel from '@/components/ui/SidePanel.vue'
import Skeleton from '@/components/ui/Skeleton.vue'
import StatusTag from '@/components/ui/StatusTag.vue'
import { days, pct, refusalWords, shortOrgName } from '@/lib/format'
import { isStale } from '@/lib/freshness'
import { dateShort, nextActionKey } from '@/lib/route'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'

/** Рабочий список врача (W-Worklist): «Пациенты · регион», четыре KPI-карточки, карточка списка: фильтр
 * выпадающим списком, поиск пациента, сортировка кликом по заголовку колонки. Полный список региона грузится
 * один раз, фильтры, поиск и сортировка считаются на клиенте; строки с запросом пациента — ответ прямо в строке.
 * Клик по строке — быстрый просмотр маршрута в панели справа; «Открыть →» — полная страница маршрута. */
const FLAGS = ['stuck_over_30', 'refusal_risk', 'faster_alternative', 'patient_signal'] as const
type Flag = (typeof FLAGS)[number]
const SORT_COLUMNS: { key: SortKey; label: string; num?: boolean }[] = [
  { key: 'patient', label: 'doctor.worklist.patient' },
  { key: 'profile', label: 'common.profile' },
  { key: 'org', label: 'common.organization' },
  { key: 'days', label: 'doctor.worklist.daysWaiting', num: true },
  { key: 'priority', label: 'doctor.worklist.priority', num: true },
]
const FLAG_TONES: Record<Flag, 'neutral' | 'danger' | 'accent' | 'warn'> = { stuck_over_30: 'neutral', refusal_risk: 'danger', faster_alternative: 'accent', patient_signal: 'warn' }
const STAGE_TONES: Record<string, 'neutral' | 'accent' | 'ok'> = { registered: 'ok', waiting: 'accent', called: 'ok' }

const { t, te } = useI18n()
const toast = useToast()
const router = useRouter()
const refdata = useRefdataStore()
const auth = useAuthStore()
const items = ref<WorklistItem[]>([])
const modelBacked = ref(false)
const asOf = ref('')
const error = ref<unknown>(null)
/** Ошибка ответа на запрос пациента — не заменяет список. */
const actionError = ref<unknown>(null)
const busy = ref(true)
/** Фильтр списка: 'all' — все пациенты (выбран сразу, чтобы в поле было видно, что показано). */
const flag = ref<Flag | 'all'>('all')
const search = ref('')

/** Сортировка по колонке: повторный клик меняет направление; по умолчанию — приоритет по убыванию. */
type SortKey = 'patient' | 'profile' | 'org' | 'days' | 'priority'
const sortKey = ref<SortKey>('priority')
const sortDir = ref<1 | -1>(-1)
function sortOn(key: SortKey) {
  if (sortKey.value === key) sortDir.value = sortDir.value === 1 ? -1 : 1
  else {
    sortKey.value = key
    sortDir.value = key === 'days' || key === 'priority' ? -1 : 1
  }
}
const ariaSort = (key: SortKey) => (sortKey.value !== key ? 'none' : sortDir.value === 1 ? 'ascending' : 'descending')
const sortIcon = (key: SortKey) => (sortKey.value !== key ? 'pi-sort-alt' : sortDir.value === 1 ? 'pi-sort-amount-up-alt' : 'pi-sort-amount-down')
function compare(a: WorklistItem, b: WorklistItem): number {
  switch (sortKey.value) {
    case 'patient': return a.patientRef.localeCompare(b.patientRef)
    case 'profile': return refdata.profileName(a.profileCode).localeCompare(refdata.profileName(b.profileCode))
    case 'org': return shortOrgName(a.moName).localeCompare(shortOrgName(b.moName))
    case 'days': return a.daysWaiting - b.daysWaiting
    default: return a.priority - b.priority
  }
}

const filterOptions = computed(() => [
  { label: `${t('doctor.worklist.filter.all')} · ${items.value.length}`, value: 'all' },
  ...FLAGS.map((f) => ({ label: `${t('doctor.worklist.filter.' + f)} · ${counts.value[f]}`, value: f })),
])

const counts = computed(() => Object.fromEntries(FLAGS.map((f) => [f, items.value.filter((i) => i.riskFlags.includes(f)).length])) as Record<Flag, number>)
const maxPriority = computed(() => Math.max(1, ...items.value.map((i) => i.priority)))
const visible = computed(() => {
  const q = search.value.trim().toLowerCase()
  return items.value
    .filter((i) => flag.value === 'all' || i.riskFlags.includes(flag.value))
    .filter((i) => !q || i.patientRef.toLowerCase().includes(q))
    .sort((a, b) => compare(a, b) * sortDir.value)
})

const flagLabel = (f: string) => (te(`route.flags.${f}`) ? t(`route.flags.${f}`) : f)
function stageLabel(item: WorklistItem): string {
  const key = `doctor.worklist.stageCode.${item.stageCode}`
  return te(key) ? t(key) : item.stage
}
/** Главный чип строки: запрос пациента, иначе риск отказа, иначе первый флаг, иначе этап. */
function primaryFlag(item: WorklistItem): { label: string; tone: 'neutral' | 'danger' | 'accent' | 'warn' | 'ok' } {
  const f = (['patient_signal', 'refusal_risk', 'faster_alternative', 'stuck_over_30'] as const).find((x) => item.riskFlags.includes(x))
  return f ? { label: flagLabel(f), tone: FLAG_TONES[f] } : { label: stageLabel(item), tone: STAGE_TONES[item.stageCode] ?? 'neutral' }
}
/** Короткая подпись следующего шага (doctor.worklist.actionShort.<code>); незнакомый код — русская подпись API как есть. */
function nextAction(item: WorklistItem): string {
  const key = nextActionKey(item.nextActionCode)
  return key ? t(key.replace('.action.', '.actionShort.')) : item.nextAction
}

// ответ на запрос пациента прямо в строке: причина обязательна и попадает в журнал
const answering = ref<{ ref: string; action: 'redirect' | 'keep' } | null>(null)
const reason = ref('')
const sending = ref<string | null>(null)

function startAnswer(item: WorklistItem, action: 'redirect' | 'keep') {
  answering.value = { ref: item.patientRef, action }
  reason.value = ''
}

async function sendAnswer(item: WorklistItem) {
  if (!answering.value || !reason.value.trim()) {
    toast.add({ severity: 'warn', summary: t('route.reasonRequired'), life: 3000 })
    return
  }
  sending.value = item.patientRef
  try {
    const key = crypto.randomUUID()
    if (answering.value.action === 'redirect' && item.patientSignal?.toMoCode) {
      await routeApi.redirect(item.patientRef, { toMoCode: item.patientSignal.toMoCode, reason: reason.value.trim() }, key)
      toast.add({ severity: 'success', summary: t('route.redirected'), life: 4000 })
    } else {
      await routeApi.keep(item.patientRef, { reason: reason.value.trim() }, key)
      toast.add({ severity: 'success', summary: t('route.keepDone'), life: 4000 })
    }
    answering.value = null
    await load()
  } catch (e) {
    actionError.value = e
  } finally {
    sending.value = null
  }
}

// панель справа: превью маршрута по клику в строке
const panelOpen = ref(false)
const selected = ref<WorklistItem | null>(null)
const preview = ref<PatientRoute | null>(null)
const previewError = ref<unknown>(null)
const previewBusy = ref(false)
const expiredCount = computed(() => preview.value?.checklist.filter((c) => c.status === 'expired').length ?? 0)

async function openPanel(item: WorklistItem) {
  selected.value = item
  panelOpen.value = true
  preview.value = null
  previewError.value = null
  previewBusy.value = true
  try {
    preview.value = await routeApi.patient(item.patientRef)
  } catch (e) {
    previewError.value = e
  } finally {
    previewBusy.value = false
  }
}

function resetFilters() {
  flag.value = 'all'
  search.value = ''
}

async function load() {
  error.value = null
  actionError.value = null
  busy.value = true
  try {
    const response = await journal.worklist({ regionKato: auth.region ?? undefined })
    items.value = response.items
    modelBacked.value = response.modelBacked
    asOf.value = response.asOf
  } catch (e) {
    error.value = e
  } finally {
    busy.value = false
  }
}

onMounted(async () => {
  await refdata.load()
  await load()
})
</script>

<template>
  <PageShell :title="`${t('nav.group.patients')} · ${refdata.regionName(auth.region)}`">
    <template #subtitle>
      {{ t('doctor.worklist.subtitle') }}<template v-if="asOf && !isStale(asOf)"> · {{ t('shell.asOf', { date: dateShort(asOf) }) }}</template> · {{ t('doctor.worklist.syntheticShort') }}
    </template>
    <p v-if="!busy && !error && !modelBacked" class="lead synthetic">{{ t('doctor.worklist.noteFallback') }}</p>

    <StateStale v-if="!busy && !error && isStale(asOf)" :as-of="asOf" />
    <ErrorBox :error="actionError" />

    <KpiRow>
      <KpiTile :value="items.length" :label="t('doctor.worklist.kpiTotal')" :loading="busy && items.length === 0" />
      <KpiTile :value="counts.stuck_over_30" :label="t('doctor.worklist.kpiStuck')" tone="warn" :loading="busy && items.length === 0" />
      <KpiTile :value="counts.refusal_risk" :label="t('doctor.worklist.kpiRisk')" :hint="t('doctor.worklist.kpiRiskHint')" tone="danger" :loading="busy && items.length === 0" />
      <KpiTile :value="counts.faster_alternative" :label="t('doctor.worklist.kpiFaster')" :loading="busy && items.length === 0" />
    </KpiRow>

    <AppCard>
      <div class="toolbar list-toolbar">
        <span class="caption">{{ t('doctor.worklist.shown', { shown: visible.length, total: items.length }) }}</span>
        <OriginTag :kind="modelBacked ? 'ml' : 'formula'" :note="modelBacked ? t('doctor.worklist.note') : t('doctor.worklist.noteFallback')" />
        <span class="spacer" />
        <Select v-model="flag" :options="filterOptions" option-label="label" option-value="value" class="filter-select" :aria-label="t('doctor.worklist.flags')" data-testid="worklist-filter" />
        <IconField class="search-field">
          <InputIcon class="pi pi-search" />
          <InputText v-model="search" :placeholder="t('doctor.worklist.searchPatient')" :aria-label="t('doctor.worklist.searchPatient')" data-testid="worklist-search" />
        </IconField>
      </div>
      <AsyncState :loading="busy" :error="error" :empty="visible.length === 0" :filtered="items.length > 0 && (flag !== 'all' || !!search)" :lines="8"
        :empty-title="t('doctor.worklist.empty')" :empty-text="t('doctor.worklist.emptyText')" :filter-hint="t('doctor.worklist.emptyFilter')" empty-icon="pi pi-user-plus" @retry="load" @reset="resetFilters">
        <template v-if="auth.can('referral.assist')" #empty-actions><Button :label="t('doctor.worklist.createReferral')" size="small" @click="router.push({ name: 'referral' })" /></template>
      <div class="table-wrap">
        <table class="dense-table" data-testid="worklist-table">
          <thead>
            <tr>
              <th v-for="c in SORT_COLUMNS" :key="c.key" :class="{ num: c.num }" :aria-sort="ariaSort(c.key)">
                <button type="button" class="sort-btn" :class="{ on: sortKey === c.key }" :data-testid="`sort-${c.key}`" @click="sortOn(c.key)">{{ t(c.label) }}<i class="pi" :class="sortIcon(c.key)" aria-hidden="true" /></button>
              </th>
              <th>{{ t('doctor.worklist.status') }}</th>
              <th>{{ t('doctor.worklist.nextStep') }}</th><th></th>
            </tr>
          </thead>
          <tbody>
            <template v-for="item in visible" :key="item.patientRef">
              <tr class="clickable" :class="{ accent: item.patientSignal, selected: selected?.patientRef === item.patientRef && panelOpen }" @click="openPanel(item)">
                <td class="ref" data-testid="worklist-patient">{{ item.patientRef }}</td>
                <td class="clip">{{ refdata.profileName(item.profileCode) }}</td>
                <td class="clip muted" :title="item.moName">{{ shortOrgName(item.moName) }}</td>
                <td class="num">{{ item.daysWaiting }}</td>
                <td class="num"><PriorityBadge :value="item.priority" :max="maxPriority" /></td>
                <td><StatusTag :value="primaryFlag(item).label" :tone="primaryFlag(item).tone" /></td>
                <td class="next">
                  <div v-if="item.patientSignal" class="signal" data-testid="worklist-signal" :title="item.patientSignal.toMoName ?? ''">
                    {{ t('route.patientSignal.' + item.patientSignal.kind, { name: shortOrgName(item.patientSignal.toMoName) }) }}<span v-if="item.patientSignal.comment" class="muted"> — «{{ item.patientSignal.comment }}»</span>
                  </div>
                  <span class="muted">{{ nextAction(item) }}</span>
                </td>
                <td class="actions-cell" @click.stop>
                  <template v-if="item.patientSignal">
                    <Button v-if="item.patientSignal.toMoCode" :label="t('route.referHereShort')" size="small" severity="secondary" :disabled="sending !== null" @click="startAnswer(item, 'redirect')" />
                    <Button :label="t('route.keepHere')" size="small" severity="secondary" :disabled="sending !== null" @click="startAnswer(item, 'keep')" />
                  </template>
                </td>
              </tr>
              <tr v-if="answering?.ref === item.patientRef" class="answer-row">
                <td colspan="8">
                  <div class="answer">
                    <span class="muted small">{{ answering.action === 'redirect' ? t('route.referHereShort') : t('route.keepHere') }} · {{ t('route.reason') }}</span>
                    <InputText v-model="reason" size="small" :placeholder="t('route.reasonPlaceholder')" data-testid="worklist-reason" @keyup.enter="sendAnswer(item)" />
                    <Button :label="t('common.confirm')" size="small" :loading="sending === item.patientRef" data-testid="worklist-send" @click="sendAnswer(item)" />
                    <Button :label="t('common.cancel')" size="small" text severity="secondary" @click="answering = null" />
                  </div>
                </td>
              </tr>
            </template>
          </tbody>
        </table>
      </div>
      </AsyncState>
    </AppCard>

    <SidePanel v-model:visible="panelOpen" :title="selected ? t('doctor.worklist.panel.title', { ref: selected.patientRef }) : ''"
      :subtitle="selected ? t('doctor.worklist.panel.sub', { days: selected.daysWaiting, date: preview ? dateShort(preview.dates.registeredAt) : '…' }) : ''">
      <ErrorBox :error="previewError" />
      <Skeleton v-if="previewBusy" :lines="8" />
      <div v-else-if="preview && preview.doctor" class="preview" data-testid="worklist-preview">
        <div class="chips">
          <StatusTag :value="t('route.stage.' + preview.stage)" tone="accent" />
          <StatusTag v-for="f in preview.doctor.riskFlags" :key="f" :value="flagLabel(f)" :tone="FLAG_TONES[f as Flag] ?? 'neutral'" />
        </div>

        <!-- текущая больница: сроки и риск строками, как на странице пациента -->
        <section class="p-section">
          <div class="p-head"><h3 class="p-title">{{ t('route.doctorView.currentHospital') }}</h3><OriginTag :kind="preview.forecast.fromModel ? 'ml' : 'formula'" /></div>
          <div class="p-name" :title="preview.organization.moName">{{ shortOrgName(preview.organization.moName) }}</div>
          <div class="p-sub">{{ preview.organization.profileName }} · {{ preview.organization.moCode }}</div>
          <div class="rows p-rows">
            <div class="row"><span class="row-main">{{ t('route.doctorView.half') }}</span><span class="row-value strong">≈ {{ days(preview.forecast.p50Days) }} {{ t('common.days') }}</span></div>
            <div class="row"><span class="row-main">{{ t('route.doctorView.ninety') }}</span><span class="row-value strong">≈ {{ days(preview.forecast.p90Days) }} {{ t('common.days') }}</span></div>
            <div class="row"><span class="row-main">{{ t('route.dates.expected') }}</span><span class="row-value strong">{{ dateShort(preview.dates.expectedAt) }}</span></div>
            <div class="row">
              <span class="row-main">{{ t('route.doctorView.refusal') }}</span>
              <span class="row-value strong" :class="{ danger: preview.doctor.pRefusal > 0.2 }">{{ preview.doctor.refusalOrgInTraining ? pct(preview.doctor.pRefusal) : refusalWords(preview.doctor.pRefusal) }}</span>
            </div>
          </div>
        </section>

        <section class="p-section">
          <h3 class="p-title">{{ t('route.doctorView.todo') }}</h3>
          <ul class="todo-list"><li>{{ nextActionKey(preview.doctor.nextActionCode) ? t(nextActionKey(preview.doctor.nextActionCode)!) : preview.doctor.nextAction }}</li></ul>
          <p v-if="preview.doctor.explanation" class="p-why"><span class="muted">{{ t('route.doctorView.basis') }}:</span> {{ preview.doctor.explanation }}</p>
        </section>

        <section class="p-section">
          <h3 class="p-title">{{ t('route.checklist') }}</h3>
          <p class="p-text">
            <span :class="{ danger: expiredCount > 0 }">{{ t('doctor.worklist.panel.testsExpired', { n: expiredCount }) }}</span> ·
            <span>{{ t('doctor.worklist.panel.testsValid', { n: preview.checklist.length - expiredCount }) }}</span>
          </p>
          <p v-if="expiredCount" class="p-why">{{ t('doctor.worklist.panel.testsHint') }}</p>
        </section>

        <section class="p-section">
          <h3 class="p-title">{{ t('route.whereFaster') }}</h3>
          <div v-if="preview.alternatives.length" class="rows">
            <div v-for="alt in preview.alternatives.slice(0, 3)" :key="alt.mo.moCode" class="row">
              <span class="row-main">
                <span :title="alt.mo.name">{{ shortOrgName(alt.mo.name) }}</span>
                <span class="row-sub">{{ alt.mo.moCode }}<template v-if="alt.isNeighborRegion"> · {{ t('citizen.wait.neighborRegion', { region: refdata.regionName(alt.mo.regionKato) }) }}</template> · {{ t('route.doctorView.altNine', { days: days(alt.p90Days) }) }} · <span :class="{ danger: alt.pRefusal > 0.2 }">{{ t('route.doctorView.altRefusal', { pct: pct(alt.pRefusal) }) }}</span></span>
              </span>
              <span class="alt-wait"><span class="alt-label">{{ t('route.doctorView.halfShort') }}</span><span class="alt-days">≈ {{ days(alt.p50Days) }} {{ t('common.days') }}</span></span>
            </div>
          </div>
          <p v-else class="p-text muted">{{ t('doctor.worklist.panel.fasterNone') }}</p>
        </section>
      </div>
      <template #footer>
        <Button class="go-btn" :label="t('doctor.worklist.panel.go')" icon="pi pi-arrow-right" icon-pos="right" :disabled="!selected" data-testid="worklist-go"
          @click="selected && router.push({ name: 'patient-route', params: { patientRef: selected.patientRef } })" />
      </template>
    </SidePanel>
  </PageShell>
</template>

<style scoped>
.list-toolbar { margin-bottom: var(--gap-cabinet); row-gap: 8px; }
.ref { font-weight: var(--fw-bold); white-space: nowrap; }
.filter-select { min-width: 260px; }
.search-field { flex: 1 1 320px; max-width: 480px; }
.search-field :deep(.p-inputtext) { width: 100%; }
.sort-btn { display: inline-flex; align-items: center; gap: 6px; padding: 0; border: 0; background: none; font: inherit; color: inherit; text-transform: inherit; letter-spacing: inherit; cursor: pointer; white-space: nowrap; }
.sort-btn .pi { font-size: 11px; opacity: 0.45; }
.sort-btn:hover, .sort-btn.on { color: var(--text); }
.sort-btn.on .pi { opacity: 1; color: var(--accent-strong); }
th.num .sort-btn { flex-direction: row-reverse; }
@media (max-width: 640px) { .filter-select, .search-field { flex: 1 1 100%; max-width: none; min-width: 0; } }
.clip { max-width: 220px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.next { max-width: 280px; }
.signal { font-weight: var(--fw-semibold); }
.actions-cell { white-space: nowrap; text-align: right; }
.actions-cell .p-button { margin-left: 4px; }
.answer-row td { background: var(--dm-surface-2); }
.answer { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
.answer .p-inputtext { flex: 1 1 260px; }
/* панель быстрого просмотра — тот же формат, что на странице пациента */
.preview { display: flex; flex-direction: column; gap: 16px; }
.p-section { display: flex; flex-direction: column; gap: 4px; padding-top: 14px; border-top: 1px solid var(--border-soft); }
.p-head { display: flex; align-items: center; gap: 10px; }
.p-title { margin: 0; font-size: var(--fs-xs); font-weight: var(--fw-bold); text-transform: uppercase; letter-spacing: 0.06em; color: var(--text-muted); }
.p-name { font-size: var(--fs-md); font-weight: var(--fw-bold); margin-top: 2px; }
.p-sub { font-size: var(--fs-sm); color: var(--text-secondary); }
.p-rows { margin-top: 6px; }
.p-text { margin: 2px 0 0; font-size: var(--fs-base); }
.p-why { margin: 2px 0 0; font-size: var(--fs-base-sm); color: var(--text-secondary); line-height: 1.5; }
.row-main { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
.strong { font-weight: var(--fw-bold); }
.danger { color: var(--danger-text); }
.todo-list { margin: 2px 0 0; padding-left: 20px; font-size: var(--fs-base); font-weight: var(--fw-semibold); line-height: 1.45; }
.alt-wait { display: flex; flex-direction: column; align-items: flex-end; gap: 2px; flex: none; }
.alt-label { font-size: var(--fs-sm); color: var(--text-muted); white-space: nowrap; }
.alt-days { font-weight: var(--fw-bold); color: var(--success-text); white-space: nowrap; }
.go-btn { width: 100%; }
</style>
