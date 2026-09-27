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
import AppCard from '@/components/ui/AppCard.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import KpiRow from '@/components/ui/KpiRow.vue'
import KpiTile from '@/components/ui/KpiTile.vue'
import PageShell from '@/components/ui/PageShell.vue'
import PriorityBar from '@/components/ui/PriorityBar.vue'
import SidePanel from '@/components/ui/SidePanel.vue'
import Skeleton from '@/components/ui/Skeleton.vue'
import StatusTag from '@/components/ui/StatusTag.vue'
import { days, pct, refusalWords, shortOrgName } from '@/lib/format'
import { dateShort, nextActionKey } from '@/lib/route'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'

/** Рабочий список врача (W-Worklist): «Пациенты · регион», пилюли-фильтры по флагам, четыре KPI-карточки, карточка
 * списка со строками 48 px (пациент · профиль · организация · ждёт · приоритет · статус · «Открыть →»). Полный
 * список региона грузится один раз, фильтры и поиск считаются на клиенте; строки с запросом пациента — ответ прямо
 * в строке; клик по строке — панель с превью маршрута. */
const FLAGS = ['patient_signal', 'stuck_over_30', 'refusal_risk', 'faster_alternative'] as const
type Flag = (typeof FLAGS)[number]
const FLAG_TONES: Record<Flag, 'neutral' | 'danger' | 'accent'> = { stuck_over_30: 'neutral', refusal_risk: 'danger', faster_alternative: 'accent', patient_signal: 'accent' }
const STAGE_TONES: Record<string, 'neutral' | 'accent' | 'ok'> = { registered: 'neutral', waiting: 'accent', called: 'ok' }

const { t, te } = useI18n()
const toast = useToast()
const router = useRouter()
const refdata = useRefdataStore()
const auth = useAuthStore()
const items = ref<WorklistItem[]>([])
const modelBacked = ref(false)
const asOf = ref('')
const error = ref<unknown>(null)
const busy = ref(true)
const flag = ref<Flag | null>(null)
const search = ref('')
const sortBy = ref<'priority' | 'days'>('priority')
const sortOptions = computed(() => [
  { label: t('doctor.worklist.sortLabel', { by: t('doctor.worklist.priority').toLowerCase() }), value: 'priority' },
  { label: t('doctor.worklist.sortLabel', { by: t('doctor.worklist.daysShort').toLowerCase() }), value: 'days' },
])

const counts = computed(() => Object.fromEntries(FLAGS.map((f) => [f, items.value.filter((i) => i.riskFlags.includes(f)).length])) as Record<Flag, number>)
const maxPriority = computed(() => Math.max(1, ...items.value.map((i) => i.priority)))
const visible = computed(() => {
  const q = search.value.trim().toLowerCase()
  return items.value
    .filter((i) => !flag.value || i.riskFlags.includes(flag.value))
    .filter((i) => !q || i.patientRef.toLowerCase().includes(q))
    .sort((a, b) => (sortBy.value === 'priority' ? b.priority - a.priority : b.daysWaiting - a.daysWaiting))
})

const flagLabel = (f: string) => (te(`route.flags.${f}`) ? t(`route.flags.${f}`) : f)
function stageLabel(item: WorklistItem): string {
  const key = `doctor.worklist.stageCode.${item.stageCode}`
  return te(key) ? t(key) : item.stage
}
/** Главный чип строки: запрос пациента, иначе риск отказа, иначе первый флаг, иначе этап. */
function primaryFlag(item: WorklistItem): { label: string; tone: 'neutral' | 'danger' | 'accent' | 'ok' } {
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
    error.value = e
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

async function load() {
  error.value = null
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
      {{ t('doctor.worklist.subtitle') }}<template v-if="asOf"> · {{ t('shell.asOf', { date: dateShort(asOf) }) }}</template> · {{ t('doctor.worklist.syntheticShort') }}
    </template>
    <template #actions>
      <IconField>
        <InputIcon class="pi pi-search" />
        <InputText v-model="search" size="small" :placeholder="t('doctor.worklist.searchRef')" data-testid="worklist-search" />
      </IconField>
      <Select v-model="sortBy" :options="sortOptions" option-label="label" option-value="value" size="small" />
    </template>
    <p v-if="!busy && !modelBacked" class="lead synthetic">{{ t('doctor.worklist.noteFallback') }}</p>

    <div class="chips" role="group" :aria-label="t('doctor.worklist.flags')">
      <button type="button" class="chip-filter" :class="{ active: flag === null }" @click="flag = null">{{ t('common.allShort') }} · {{ items.length }}</button>
      <button v-for="f in FLAGS" :key="f" type="button" class="chip-filter" :class="{ active: flag === f }" :data-testid="`flag-${f}`" @click="flag = flag === f ? null : f">{{ flagLabel(f) }} · {{ counts[f] }}</button>
    </div>
    <ErrorBox :error="error" />

    <KpiRow>
      <KpiTile :value="items.length" :label="t('doctor.worklist.kpiTotal')" :loading="busy && items.length === 0" />
      <KpiTile :value="counts.stuck_over_30" :label="t('doctor.worklist.kpiStuck')" :loading="busy && items.length === 0" />
      <KpiTile :value="counts.refusal_risk" :label="t('doctor.worklist.kpiRisk')" :origin="modelBacked ? 'ml' : 'formula'" :loading="busy && items.length === 0" />
      <KpiTile :value="counts.faster_alternative" :label="t('doctor.worklist.kpiFaster')" :origin="modelBacked ? 'ml' : 'formula'" :loading="busy && items.length === 0" />
    </KpiRow>

    <AppCard :title="t('doctor.worklist.title')" :origin="modelBacked ? 'ml' : 'formula'" :origin-note="modelBacked ? t('doctor.worklist.note') : t('doctor.worklist.noteFallback')">
      <template #header><span class="caption">{{ t('doctor.worklist.shown', { shown: visible.length, total: items.length }) }}</span></template>
      <Skeleton v-if="busy && items.length === 0" kind="table" :lines="8" />
      <EmptyState v-else-if="visible.length === 0" :title="t('doctor.worklist.empty')" :text="flag || search ? t('doctor.worklist.emptyFilter') : undefined" />
      <div v-else class="table-wrap">
        <table class="dense-table" data-testid="worklist-table">
          <thead>
            <tr>
              <th>{{ t('doctor.worklist.patient') }}</th><th>{{ t('common.profile') }}</th><th>{{ t('common.organization') }}</th>
              <th class="num">{{ t('doctor.worklist.daysWaiting') }}</th><th class="num">{{ t('doctor.worklist.priority') }}</th><th>{{ t('doctor.worklist.status') }}</th>
              <th>{{ t('doctor.worklist.nextStep') }}</th><th></th>
            </tr>
          </thead>
          <tbody>
            <template v-for="item in visible" :key="item.patientRef">
              <tr class="clickable" :class="{ accent: item.patientSignal, selected: selected?.patientRef === item.patientRef && panelOpen }" @click="openPanel(item)">
                <td class="ref"><RouterLink :to="{ name: 'patient-route', params: { patientRef: item.patientRef } }" class="ref-link" data-testid="worklist-patient" @click.stop>{{ item.patientRef }}</RouterLink></td>
                <td class="clip">{{ refdata.profileName(item.profileCode) }}</td>
                <td class="clip muted" :title="item.moName">{{ shortOrgName(item.moName) }}</td>
                <td class="num">{{ item.daysWaiting }}</td>
                <td class="num"><PriorityBar :value="item.priority" :max="maxPriority" /></td>
                <td><StatusTag :value="primaryFlag(item).label" :tone="primaryFlag(item).tone" /></td>
                <td class="next">
                  <div v-if="item.patientSignal" class="signal" data-testid="worklist-signal" :title="item.patientSignal.toMoName ?? ''">
                    {{ t('route.patientSignal.' + item.patientSignal.kind, { name: shortOrgName(item.patientSignal.toMoName) }) }}<span v-if="item.patientSignal.comment" class="muted"> — «{{ item.patientSignal.comment }}»</span>
                  </div>
                  <span class="muted">{{ nextAction(item) }}</span>
                </td>
                <td class="actions-cell" @click.stop>
                  <template v-if="item.patientSignal">
                    <Button v-if="item.patientSignal.toMoCode" :label="t('route.referHereShort')" size="small" :disabled="sending !== null" @click="startAnswer(item, 'redirect')" />
                    <Button :label="t('route.keepHere')" size="small" severity="secondary" :disabled="sending !== null" @click="startAnswer(item, 'keep')" />
                  </template>
                  <RouterLink v-else :to="{ name: 'patient-route', params: { patientRef: item.patientRef } }" class="link-arrow small">{{ t('shell.open') }}</RouterLink>
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
    </AppCard>

    <SidePanel v-model:visible="panelOpen" :title="selected?.patientRef ?? ''" :subtitle="selected ? `${refdata.profileName(selected.profileCode)} · ${shortOrgName(selected.moName)}` : ''">
      <ErrorBox :error="previewError" />
      <Skeleton v-if="previewBusy" :lines="6" />
      <template v-else-if="preview && preview.doctor">
        <div class="chips" style="margin-bottom: 12px">
          <StatusTag :value="t('route.stage.' + preview.stage)" tone="accent" />
          <StatusTag v-for="f in preview.doctor.riskFlags" :key="f" :value="flagLabel(f)" :tone="FLAG_TONES[f as Flag] ?? 'neutral'" />
        </div>
        <div class="rows">
          <div class="row"><span class="row-main muted">{{ t('route.p50') }}</span><span class="row-value">{{ days(preview.forecast.p50Days) }}</span></div>
          <div class="row"><span class="row-main muted">{{ t('route.p90') }}</span><span class="row-value">{{ days(preview.forecast.p90Days) }}</span></div>
          <div class="row"><span class="row-main muted">{{ t('route.refusal') }}</span><span class="row-value">{{ preview.doctor.refusalOrgInTraining ? pct(preview.doctor.pRefusal) : refusalWords(preview.doctor.pRefusal) }}</span></div>
          <div class="row"><span class="row-main muted">{{ t('route.nextAction') }}</span><span class="row-value wrap">{{ nextActionKey(preview.doctor.nextActionCode) ? t(nextActionKey(preview.doctor.nextActionCode)!) : preview.doctor.nextAction }}</span></div>
          <div class="row"><span class="row-main muted">{{ t('route.dates.registered') }}</span><span class="row-value">{{ dateShort(preview.dates.registeredAt) }} · {{ t('route.daysWaitingShort', { days: preview.daysWaiting }) }}</span></div>
          <div class="row"><span class="row-main muted">{{ t('route.dates.expected') }}</span><span class="row-value">{{ dateShort(preview.dates.expectedAt) }}</span></div>
          <div class="row"><span class="row-main muted">{{ t('route.checklist') }}</span><span class="row-value">{{ t('route.checklistSummary', { expired: preview.checklist.filter((c) => c.status === 'expired').length, valid: preview.checklist.filter((c) => c.status !== 'expired').length }) }}</span></div>
          <div class="row"><span class="row-main muted">{{ t('route.whereFaster') }}</span><span class="row-value wrap">{{ preview.alternatives.length ? `${shortOrgName(preview.alternatives[0]!.mo.name)} · ≈ ${days(preview.alternatives[0]!.p50Days)} ${t('common.days')}` : '—' }}</span></div>
        </div>
        <p class="muted small" style="margin-top: 12px">{{ preview.doctor.explanation }}</p>
      </template>
      <template #footer>
        <Button :label="t('shell.open')" icon="pi pi-arrow-right" icon-pos="right" :disabled="!selected" @click="selected && router.push({ name: 'patient-route', params: { patientRef: selected.patientRef } })" />
      </template>
    </SidePanel>
  </PageShell>
</template>

<style scoped>
.ref { font-weight: 500; white-space: nowrap; }
.ref-link { text-decoration: none; }
.clip { max-width: 220px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.next { max-width: 280px; }
.signal { font-weight: 500; }
.actions-cell { white-space: nowrap; text-align: right; }
.actions-cell .p-button { margin-left: 4px; }
.answer-row td { background: var(--dm-surface-2); }
.answer { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
.answer .p-inputtext { flex: 1 1 260px; }
.row-value.wrap { white-space: normal; text-align: right; }
</style>
