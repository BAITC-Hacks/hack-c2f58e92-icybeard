<script setup lang="ts">
import Button from 'primevue/button'
import Checkbox from 'primevue/checkbox'
import InputText from 'primevue/inputtext'
import Textarea from 'primevue/textarea'
import Select from 'primevue/select'
import { useToast } from 'primevue/usetoast'
import { computed, onMounted, reactive, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute } from 'vue-router'
import { useForecastFactors } from '@/composables/useForecastFactors'
import { ApiError } from '@/api/client'
import { journal, queue } from '@/api/endpoints'
import type { AlternativesResponse, OrganizationItem, PredictResponse } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import OriginTag from '@/components/OriginTag.vue'
import PageShell from '@/components/ui/PageShell.vue'
import SearchSelect from '@/components/ui/SearchSelect.vue'
import Skeleton from '@/components/ui/Skeleton.vue'
import { referralSubjectId, SUBJECT_REFERRAL } from '@/lib/decision'
import { days, pct, refusalWords, shortOrgName } from '@/lib/format'
import { FINANCE_DEFAULT, PURPOSE_VALUES, TERRITORIAL_VALUES } from '@/lib/referralContract'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'

/** Ассистент направления (W-Referral): регион пилюлей в шапке, дальше одна карточка из четырёх разделов — «Параметры»
 * (профиль, цель, территория, МКБ-10, дополнительные — по ссылке), «Куда направить» (выбранная врачом организация и
 * альтернативы списком с выбором), «Прогноз для …» (четыре цифры, очередь, «Из чего сложился прогноз» простыми
 * словами) и «Решение» (причина и «Подтвердить»: выбор и причина уходят в журнал). Прогноз считается сам при полной форме. */
const { t } = useI18n()
const refdata = useRefdataStore()
const auth = useAuthStore()
const toast = useToast()
const route = useRoute()
const fromQuery = (name: string) => (typeof route.query[name] === 'string' && route.query[name] ? String(route.query[name]) : '')

// регион — из учётной записи врача; организация и профиль — только из перехода «открыть направление» (рабочий список,
// маршрут пациента), иначе врач выбирает сам; диагноз необязателен и не предзаполняется
const form = reactive({
  regionKato: auth.region ?? '',
  moCode: fromQuery('moCode'),
  profileCode: fromQuery('profileCode'),
  icd10: '',
  referralPurpose: PURPOSE_VALUES[0] as string,
  territorialType: TERRITORIAL_VALUES[0] as string,
  financeSource: FINANCE_DEFAULT,
  // пусто — сервис моделей берёт день после последних данных очереди: модель обучена на I квартале 2025
  registrationDate: '',
  // необязательно: если направление внутри своей же организации, модель получает признак same_mo
  referringMoCode: '',
})
const organizations = ref<OrganizationItem[]>([])
const referringOrganizations = ref<OrganizationItem[]>([])
const prediction = ref<PredictResponse | null>(null)
const alternatives = ref<AlternativesResponse | null>(null)
const includeNeighbors = ref(false)
const error = ref<unknown>(null)
const fieldErrors = ref<Record<string, string>>({})
const busy = ref(false)
/** выбор врача среди опций: выбранная организация или одна из альтернатив */
const chosen = ref('')
const reason = ref('')
const recorded = ref<string | null>(null)
const recording = ref(false)
// один ключ идемпотентности на расчёт: повторный клик по тому же прогнозу не создаёт вторую запись
let decisionKey = ''

const complete = computed(() => !!form.regionKato && !!form.moCode && !!form.profileCode)
const purposes = computed(() => PURPOSE_VALUES.map((value, i) => ({ value, label: t(`doctor.referral.purpose.${i}`) })))
const territorial = computed(() => TERRITORIAL_VALUES.map((value, i) => ({ value, label: t(`doctor.referral.territorial.${i}`) })))
const selectedOrg = computed(() => organizations.value.find((o) => o.moCode === form.moCode) ?? null)
const selectedName = computed(() => (selectedOrg.value ? shortOrgName(selectedOrg.value.name) : form.moCode))
const orgLabel = (o: OrganizationItem) => shortOrgName(o.name)
const orgTitle = (o: OrganizationItem) => o.name
const chosenName = computed(() => {
  const alt = alternatives.value?.items.find((a) => a.mo.moCode === chosen.value)
  return alt ? shortOrgName(alt.mo.name) : selectedName.value
})
const riskText = (p: number, inTraining?: boolean) => (inTraining === false ? refusalWords(p) : pct(p))
const baseFactors = useForecastFactors(computed(() => prediction.value?.explanation.factors), computed(() => (form.profileCode ? refdata.profileName(form.profileCode) : null)))
/** Направляющая организация не указана — модель считает направление «со стороны»; говорим это прямо и подсказываем, что изменить. */
const factors = computed(() =>
  baseFactors.value.map((f) => (f.name === 'same_mo' && !form.referringMoCode ? { ...f, label: t('doctor.referral.referringUnset'), hint: t('doctor.referral.referringUnsetHint') } : f)),
)

async function loadOrganizations() {
  if (!form.regionKato || !form.profileCode) {
    organizations.value = []
    return
  }
  organizations.value = await refdata.organizationsOf(form.regionKato, form.profileCode)
  if (form.moCode && !organizations.value.some((o) => o.moCode === form.moCode)) form.moCode = ''
}

async function loadReferringOrganizations() {
  if (!form.regionKato) {
    referringOrganizations.value = []
    return
  }
  referringOrganizations.value = await refdata.organizationsOf(form.regionKato)
  if (form.referringMoCode && !referringOrganizations.value.some((o) => o.moCode === form.referringMoCode)) form.referringMoCode = ''
}

let runId = 0
async function predict() {
  if (!complete.value) {
    prediction.value = null
    alternatives.value = null
    return
  }
  const id = ++runId
  busy.value = true
  error.value = null
  fieldErrors.value = {}
  recorded.value = null
  decisionKey = ''
  try {
    const [p, a] = await Promise.all([queue.predict(form), queue.alternatives({ ...form, limit: 5, includeNeighbors: includeNeighbors.value })])
    if (id !== runId) return
    prediction.value = p
    alternatives.value = a
    chosen.value = form.moCode
    decisionKey = crypto.randomUUID()
  } catch (e) {
    if (id !== runId) return
    if (e instanceof ApiError && e.status === 422 && e.errors) {
      fieldErrors.value = Object.fromEntries(Object.entries(e.errors).map(([k, v]) => [k, v.join(', ')]))
    }
    error.value = e
    prediction.value = null
    alternatives.value = null
  } finally {
    if (id === runId) busy.value = false
  }
}

/** Рекомендация системы: самая быстрая по медиане организация среди выбранной и альтернатив. */
function recommendedMo(): string {
  const fastest = alternatives.value?.items[0]
  return fastest && prediction.value && fastest.p50Days < prediction.value.p50Days ? fastest.mo.moCode : form.moCode
}

async function record() {
  if (recorded.value || recording.value || !decisionKey || !chosen.value) return
  recording.value = true
  try {
    const created = await journal.record(
      {
        subject: SUBJECT_REFERRAL,
        subjectId: referralSubjectId(form.regionKato, form.moCode, form.profileCode, form.registrationDate || new Date().toISOString().slice(0, 10)),
        recommended: { moCode: recommendedMo() },
        chosen: { moCode: chosen.value },
        reason: reason.value.trim(),
      },
      decisionKey,
    )
    recorded.value = created.decisionId
    toast.add({ severity: 'success', summary: t('doctor.referral.decisionRecorded'), detail: t('doctor.referral.toJournal'), life: 4000 })
  } catch (e) {
    error.value = e
  } finally {
    recording.value = false
  }
}

onMounted(async () => {
  await refdata.load()
  await Promise.all([loadOrganizations(), loadReferringOrganizations()])
  if (complete.value) await predict()
})
watch(() => [form.regionKato, form.profileCode], async () => {
  await loadOrganizations()
  await predict()
})
watch(() => form.regionKato, loadReferringOrganizations)
watch(() => [form.moCode, form.referralPurpose, form.territorialType, form.icd10, form.registrationDate, form.referringMoCode, includeNeighbors.value], predict)
</script>

<template>
  <PageShell :title="t('doctor.referral.titleShort')">
    <template #subtitle>{{ t('doctor.referral.purposeLead') }}<template v-if="prediction"> · {{ t('shell.asOf', { date: prediction.model.trainedThrough }) }}</template></template>
    <ErrorBox :error="error" />

    <div class="layout">
    <section class="card referral">
      <!-- 1. параметры направления -->
      <div class="sec">
        <h2 class="sec-title">{{ t('doctor.referral.secParams') }}</h2>
        <div class="params">
          <div class="field wide"><label>{{ t('common.region') }}</label><SearchSelect v-model="form.regionKato" :options="refdata.regions" option-label="name" option-value="regionKato" :placeholder="t('common.region')" /></div>
          <div class="field wide"><label>{{ t('common.profile') }}</label><SearchSelect v-model="form.profileCode" :options="refdata.profiles" option-label="name" option-value="profileCode" :placeholder="t('common.profile')" /><span v-if="fieldErrors.profileCode" class="error">{{ fieldErrors.profileCode }}</span></div>
          <div class="field"><label>{{ t('doctor.referral.purposeLabel') }}</label><Select v-model="form.referralPurpose" :options="purposes" option-label="label" option-value="value" /></div>
          <div class="field"><label>{{ t('doctor.referral.territoryLabel') }}</label><Select v-model="form.territorialType" :options="territorial" option-label="label" option-value="value" /></div>
          <div class="field"><label>{{ t('doctor.referral.icd10') }}</label><InputText v-model="form.icd10" placeholder="H25.1" /></div>
        </div>
        <details class="more">
          <summary>{{ t('doctor.referral.more') }} <i class="pi pi-chevron-down" aria-hidden="true" /></summary>
          <div class="params more-body">
            <div class="field"><label>{{ t('doctor.referral.registrationDate') }}</label><InputText v-model="form.registrationDate" :placeholder="t('doctor.referral.registrationDatePlaceholder')" /><span v-if="fieldErrors.registrationDate" class="error">{{ fieldErrors.registrationDate }}</span></div>
            <div class="field wide"><label>{{ t('doctor.referral.referringOrg') }}</label><SearchSelect v-model="form.referringMoCode" :options="referringOrganizations" :option-label="orgLabel" option-value="moCode" :option-title="orgTitle" show-clear :placeholder="t('doctor.referral.notSpecified')" /></div>
            <label class="check wide"><Checkbox v-model="includeNeighbors" binary input-id="includeNeighbors" /> <span>{{ t('doctor.referral.includeNeighbors') }}</span></label>
          </div>
        </details>
      </div>

      <!-- 2. куда направить -->
      <div class="sec">
        <div class="sec-head">
          <h2 class="sec-title">{{ t('doctor.referral.secWhere') }}</h2>
          <OriginTag v-if="prediction" kind="ml" />
          <span class="spacer" />
          <button v-if="form.moCode && prediction" type="button" class="link-arrow small" :disabled="!!recorded" @click="form.moCode = ''">{{ t('doctor.referral.changeOrg') }}</button>
        </div>
        <SearchSelect v-if="!form.moCode || !prediction" v-model="form.moCode" :options="organizations" :option-label="orgLabel" option-value="moCode" :option-title="orgTitle" :placeholder="t('doctor.referral.pickOrg')" :disabled="organizations.length === 0" />
        <div v-else class="options" role="radiogroup" data-testid="referral-options">
          <label class="option" :class="{ on: chosen === form.moCode }">
            <input v-model="chosen" type="radio" name="referral-org" :value="form.moCode" :disabled="!!recorded" />
            <span class="opt-main">
              <span class="opt-name" :title="selectedOrg?.name">{{ selectedName }}</span>
              <span class="opt-sub">{{ form.moCode }} · {{ t('doctor.referral.chosenByDoctor') }}<template v-if="prediction.queue"> · {{ t('doctor.referral.inQueue', { n: prediction.queue.len }) }}</template> · <span :class="{ risk: prediction.pRefusal > 0.2 }">{{ t('route.doctorView.altRefusal', { pct: riskText(prediction.pRefusal, prediction.refusalOrgInTraining) }) }}</span></span>
            </span>
            <span class="opt-wait"><span class="opt-wait-label">{{ t('route.doctorView.halfShort') }}</span><span class="opt-days">≈ {{ days(prediction.p50Days) }} {{ t('common.days') }}</span></span>
          </label>
          <label v-for="a in alternatives?.items ?? []" :key="a.mo.moCode" class="option" :class="{ on: chosen === a.mo.moCode }">
            <input v-model="chosen" type="radio" name="referral-org" :value="a.mo.moCode" :disabled="!!recorded" />
            <span class="opt-main">
              <span class="opt-name" :title="a.mo.name">{{ shortOrgName(a.mo.name) }}</span>
              <span class="opt-sub">{{ a.mo.moCode }}<template v-if="a.isNeighborRegion"> · {{ t('doctor.referral.neighborRegion', { region: refdata.regionName(a.mo.regionKato) }) }}</template> · <span :class="a.p50Days < prediction.p50Days ? 'faster' : 'slower'">{{ a.p50Days < prediction.p50Days ? t('doctor.referral.fasterBy', { n: Math.round(prediction.p50Days - a.p50Days) }) : t('doctor.referral.slowerBy', { n: Math.round(a.p50Days - prediction.p50Days) }) }}</span> · <span :class="{ risk: a.pRefusal > 0.2 }">{{ t('route.doctorView.altRefusal', { pct: pct(a.pRefusal) }) }}</span></span>
            </span>
            <span class="opt-wait"><span class="opt-wait-label">{{ t('route.doctorView.halfShort') }}</span><span class="opt-days" :class="{ faster: a.p50Days < prediction.p50Days }">≈ {{ days(a.p50Days) }} {{ t('common.days') }}</span></span>
          </label>
        </div>
      </div>

    </section>

    <section class="card referral result-col">
      <!-- 3. прогноз для выбранной врачом организации -->
      <div v-if="busy && !prediction" class="sec"><Skeleton :lines="4" /></div>
      <div v-else-if="!prediction" class="sec"><EmptyState :title="t('doctor.referral.fillForm')" icon="pi pi-compass" /></div>
      <div v-else class="sec" data-testid="referral-result">
        <h2 class="sec-title">{{ t('doctor.referral.secForecast', { name: selectedName }) }}</h2>
        <dl class="stats">
          <div class="stat"><dt>{{ t('route.doctorView.half') }}</dt><dd>≈ {{ days(prediction.p50Days) }} <small>{{ t('common.days') }}</small></dd></div>
          <div class="stat"><dt>{{ t('route.doctorView.ninety') }}</dt><dd>≈ {{ days(prediction.p90Days) }} <small>{{ t('common.days') }}</small></dd></div>
          <div class="stat"><dt>{{ t('doctor.referral.within30Row') }}</dt><dd>{{ pct(prediction.pWithin30Days) }}</dd></div>
          <div class="stat"><dt>{{ t('route.doctorView.refusal') }}</dt><dd :class="{ danger: prediction.pRefusal > 0.2 }">{{ riskText(prediction.pRefusal, prediction.refusalOrgInTraining) }}</dd></div>
        </dl>
        <p v-if="prediction.queue" class="note">{{ t('doctor.referral.queueInfo', { len: prediction.queue.len, age: days(prediction.queue.ageP50), throughput: prediction.queue.throughputPerDay.toFixed(1) }) }}</p>
        <p v-if="prediction.refusalOrgInTraining === false" class="note">{{ t('doctor.referral.unseenOrgHint') }}</p>
        <details v-if="factors.length" class="more">
          <summary>{{ t('route.doctorView.whyTitle') }} <i class="pi pi-chevron-down" aria-hidden="true" /></summary>
          <p class="more-lead">{{ t('route.doctorView.whyLead') }}</p>
          <div class="rows">
            <div v-for="f in factors" :key="f.name" class="row">
              <span class="row-main"><span>{{ f.label }}</span><span v-if="f.hint" class="row-sub">{{ f.hint }}</span></span>
              <span class="row-value factor-effect" :class="f.dir">{{ f.effect }}</span>
            </div>
          </div>
        </details>
      </div>

      <!-- 4. решение -->
      <div v-if="prediction" class="sec">
        <h2 class="sec-title">{{ t('doctor.referral.secDecision') }}</h2>
        <dl class="summary" data-testid="referral-summary">
          <div><dt>{{ t('doctor.referral.sumWhere') }}</dt><dd>{{ chosenName }}<span v-if="chosen !== form.moCode" class="muted"> · {{ t('doctor.referral.sumInsteadOf', { name: selectedName }) }}</span></dd></div>
          <div><dt>{{ t('doctor.referral.sumWhat') }}</dt><dd>{{ refdata.profileName(form.profileCode) }} · {{ purposes.find((p) => p.value === form.referralPurpose)?.label }}<template v-if="form.icd10"> · {{ form.icd10 }}</template></dd></div>

        </dl>
        <div class="field">
          <label for="referral-reason">{{ t('doctor.referral.reasonLabelShort') }}</label>
          <Textarea id="referral-reason" v-model="reason" rows="2" auto-resize :placeholder="t('doctor.referral.reasonExample')" :disabled="!!recorded" data-testid="referral-reason" />
        </div>
        <div class="confirm-row">
          <span class="muted small">{{ t('doctor.referral.saveNote') }}</span>
          <span class="spacer" />
          <RouterLink v-if="recorded" class="link-arrow small" :to="{ name: 'decisions' }">{{ t('nav.decisions') }}</RouterLink>
          <RouterLink class="link-arrow small" :to="{ name: 'worklist' }">{{ t('doctor.referral.toWorklist') }}</RouterLink>
          <Button :label="recorded ? t('doctor.referral.recorded') : t('doctor.referral.saveChoice')" size="small" :disabled="!!recorded" :loading="recording" data-testid="referral-confirm" @click="record" />
        </div>
      </div>
    </section>
    </div>
  </PageShell>
</template>

<style scoped>
.layout { display: grid; grid-template-columns: minmax(0, 1.1fr) minmax(0, 1fr); gap: var(--gap-cabinet); align-items: start; }
.referral { padding: 0; min-width: 0; }
.result-col { position: sticky; top: 16px; }
.sec { padding: 18px 24px; display: flex; flex-direction: column; gap: 10px; }
.sec + .sec { border-top: 1px solid var(--border-soft); }
.sec-head { display: flex; align-items: center; gap: 10px; }
.sec-title { margin: 0; font-size: var(--fs-xs); font-weight: var(--fw-bold); letter-spacing: 0.06em; text-transform: uppercase; color: var(--text-muted); }
.spacer { flex: 1; }
.params { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 12px 14px; }
.params .wide { grid-column: 1 / -1; }
.params .field { min-width: 0; }
.params :deep(.p-select), .params :deep(.p-inputtext) { width: 100%; min-width: 0; }
.more-body { margin-top: 10px; }
.more-body .check { grid-column: 1 / -1; }
.check { display: flex; align-items: center; gap: 8px; font-size: var(--fs-base-sm); }
.more summary { display: inline-flex; align-items: center; gap: 6px; font-size: var(--fs-base-sm); font-weight: var(--fw-bold); color: var(--link); cursor: pointer; list-style: none; }
.more summary::-webkit-details-marker { display: none; }
.more summary i { font-size: 0.6rem; transition: transform .15s; }
.more[open] summary i { transform: rotate(180deg); }
.more-lead { margin: 8px 0 4px; font-size: var(--fs-base-sm); color: var(--text-secondary); line-height: 1.5; }
.options { display: flex; flex-direction: column; }
.option { display: flex; align-items: center; gap: 12px; padding: 10px 12px; box-shadow: inset 0 -1px 0 var(--border-soft); cursor: pointer; }
.option:last-child { box-shadow: none; }
.option:hover { background: var(--surface-hover); }
.option.on { background: var(--accent-subtle); }
.option input { appearance: none; -webkit-appearance: none; width: 18px; height: 18px; flex: none; margin: 0; border: 2px solid var(--border); border-radius: 50%; background: var(--surface); box-sizing: border-box; cursor: pointer; }
.option input:checked { border-color: var(--accent); box-shadow: inset 0 0 0 3px var(--surface), inset 0 0 0 9px var(--accent); }
.option input:focus { outline: none; }
.option input:disabled { cursor: default; }
.opt-main { display: flex; flex-direction: column; gap: 2px; min-width: 0; flex: 1; }
.opt-name { font-size: var(--fs-base); font-weight: var(--fw-semibold); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.opt-sub { font-size: var(--fs-sm); color: var(--text-muted); }
.opt-sub .risk { color: var(--danger-text); }
.opt-sub .faster { color: var(--success-text); }
.opt-wait { display: flex; flex-direction: column; align-items: flex-end; gap: 2px; flex: none; }
.opt-wait-label { font-size: var(--fs-sm); color: var(--text-muted); white-space: nowrap; }
.opt-days { font-weight: var(--fw-bold); white-space: nowrap; }
.opt-days.faster { color: var(--success-text); }
.stats { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); margin: 0; }
.stat { display: flex; flex-direction: column; gap: 4px; padding: 0 16px; border-left: 1px solid var(--border-soft); min-width: 0; }
.stat:first-child { border-left: 0; padding-left: 0; }
.stat dt { font-size: var(--fs-sm); color: var(--text-muted); line-height: 1.35; }
.stat dd { margin: 0; font-size: var(--fs-xl); font-weight: var(--fw-extrabold); font-variant-numeric: tabular-nums; }
.stat dd small { font-size: var(--fs-base-sm); font-weight: var(--fw-bold); color: var(--text-muted); }
.stat dd.danger { color: var(--danger-text); }
.note { margin: 0; font-size: var(--fs-base-sm); color: var(--text-secondary); line-height: 1.5; }
.row-main { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
.factor-effect { font-weight: var(--fw-bold); white-space: nowrap; }
.factor-effect.plus { color: var(--danger-text); }
.factor-effect.minus { color: var(--success-text); }
.factor-effect.zero { color: var(--text-muted); }
.field :deep(.p-textarea) { width: 100%; }
.summary { display: flex; flex-direction: column; margin: 0; border-top: 1px solid var(--border-soft); }
.summary > div { display: flex; gap: 12px; padding: 8px 0; border-bottom: 1px solid var(--border-soft); font-size: var(--fs-base-sm); }
.summary dt { flex: none; width: 110px; color: var(--text-muted); }
.summary dd { margin: 0; font-weight: var(--fw-semibold); min-width: 0; }
.confirm-row { display: flex; align-items: center; gap: 14px; flex-wrap: wrap; }
@media (max-width: 1100px) { .layout { grid-template-columns: 1fr; } .result-col { position: static; } }
@media (max-width: 1400px) { .stats { grid-template-columns: repeat(2, minmax(0, 1fr)); row-gap: 14px; } .stat:nth-child(3) { border-left: 0; padding-left: 0; } }
@media (max-width: 640px) { .params, .more-body { grid-template-columns: 1fr; } .sec { padding: 16px; } .confirm-row :deep(.p-button) { width: 100%; } }
</style>
