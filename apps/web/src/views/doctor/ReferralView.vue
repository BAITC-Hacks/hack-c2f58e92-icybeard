<script setup lang="ts">
import Button from 'primevue/button'
import Checkbox from 'primevue/checkbox'
import InputText from 'primevue/inputtext'
import Select from 'primevue/select'
import { useToast } from 'primevue/usetoast'
import { computed, onMounted, reactive, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute } from 'vue-router'
import { ApiError } from '@/api/client'
import { analytics, journal, queue } from '@/api/endpoints'
import type { AlternativesResponse, OrganizationItem, PredictResponse, QualitySplit } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import AppCard from '@/components/ui/AppCard.vue'
import CollapsibleSection from '@/components/ui/CollapsibleSection.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import HeroNumber from '@/components/ui/HeroNumber.vue'
import PageShell from '@/components/ui/PageShell.vue'
import SearchSelect from '@/components/ui/SearchSelect.vue'
import Skeleton from '@/components/ui/Skeleton.vue'
import { referralSubjectId, SUBJECT_REFERRAL } from '@/lib/decision'
import { days, pct, refusalWords, shortOrgName, signed } from '@/lib/format'
import { FINANCE_DEFAULT, PURPOSE_VALUES, TERRITORIAL_VALUES } from '@/lib/referralContract'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'

/** Ассистент направления (W-Referral): регион пилюлей в шапке; слева карточка формы — профиль и цель · территория,
 * организации карточками-опциями (выбранная врачом + альтернативы с дельтой к выбранной), МКБ-10 и причина; справа
 * «Прогноз для выбранной» (hero, строки p90 / за 30 дней / риск отказа, очередь), «Подтвердить» записывает выбор и
 * причину в журнал. Прогноз считается сам при полной форме. */
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
const waitQuality = ref<QualitySplit | null>(null)

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
  try {
    waitQuality.value = (await analytics.quality()).wait?.test_time ?? null
  } catch {
    waitQuality.value = null // страница работает и без отчёта качества
  }
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
    <template #subtitle>{{ refdata.regionName(form.regionKato) }} · {{ t('doctor.referral.leadShort') }}<template v-if="prediction"> · {{ t('shell.asOf', { date: prediction.model.trainedThrough }) }}</template></template>
    <template #actions>
      <label class="pill-select">
        <span class="pill-label">{{ t('common.region') }}</span>
        <SearchSelect v-model="form.regionKato" :options="refdata.regions" option-label="name" option-value="regionKato" :placeholder="t('common.region')" />
      </label>
    </template>
    <ErrorBox :error="error" />

    <div class="main-grid">
      <AppCard class="form-card">
        <div class="pair">
          <div class="field"><label>{{ t('common.profile') }}</label><SearchSelect v-model="form.profileCode" :options="refdata.profiles" option-label="name" option-value="profileCode" :placeholder="t('common.profile')" /><span v-if="fieldErrors.profileCode" class="error">{{ fieldErrors.profileCode }}</span></div>
          <div class="field">
            <label>{{ t('doctor.referral.purposeTerritory') }}</label>
            <div class="pair tight">
              <Select v-model="form.referralPurpose" :options="purposes" option-label="label" option-value="value" />
              <Select v-model="form.territorialType" :options="territorial" option-label="label" option-value="value" />
            </div>
          </div>
        </div>

        <div class="field">
          <div class="org-head"><label>{{ t('common.organization') }}</label><span class="caption">{{ t('doctor.referral.orgHint') }}</span></div>
          <SearchSelect v-if="!form.moCode || !prediction" v-model="form.moCode" :options="organizations" :option-label="orgLabel" option-value="moCode" :option-title="orgTitle" :placeholder="t('common.organization')" :disabled="organizations.length === 0" />
          <div v-else class="options" data-testid="referral-options">
            <button type="button" class="option" :class="{ selected: chosen === form.moCode }" :disabled="!!recorded" @click="chosen = form.moCode">
              <span class="radio" aria-hidden="true"><span v-if="chosen === form.moCode" class="radio-dot" /></span>
              <span class="option-text">
                <span class="option-title" :title="selectedOrg?.name">{{ selectedName }}</span>
                <span class="caption">{{ form.moCode }} · {{ t('doctor.referral.chosenByDoctor') }}<template v-if="prediction.queue"> · {{ t('doctor.referral.inQueue', { n: prediction.queue.len }) }}</template></span>
              </span>
              <span class="option-wait tabular">{{ days(prediction.p50Days) }} {{ t('common.days') }}</span>
              <span class="option-risk tabular">{{ riskText(prediction.pRefusal, prediction.refusalOrgInTraining) }}</span>
            </button>
            <button v-for="a in alternatives?.items ?? []" :key="a.mo.moCode" type="button" class="option" :class="{ selected: chosen === a.mo.moCode }" :disabled="!!recorded" @click="chosen = a.mo.moCode">
              <span class="radio" aria-hidden="true"><span v-if="chosen === a.mo.moCode" class="radio-dot" /></span>
              <span class="option-text">
                <span class="option-title" :title="a.mo.name">{{ shortOrgName(a.mo.name) }}</span>
                <span class="caption">{{ a.mo.moCode }} · <span :class="a.p50Days < prediction.p50Days ? 'delta-down' : 'delta-up'">{{ t('doctor.referral.deltaToChosen', { delta: signed(a.p50Days - prediction.p50Days, 0) }) }}</span><template v-if="a.isNeighborRegion"> · {{ t('doctor.referral.neighborRegion', { region: refdata.regionName(a.mo.regionKato) }) }}</template></span>
              </span>
              <span class="option-wait tabular">{{ days(a.p50Days) }} {{ t('common.days') }}</span>
              <span class="option-risk tabular">{{ pct(a.pRefusal) }}</span>
            </button>
            <button type="button" class="link-arrow small change" :disabled="!!recorded" @click="form.moCode = ''">{{ t('doctor.referral.changeOrg') }}</button>
          </div>
        </div>

        <div class="pair icd-reason">
          <div class="field"><label>{{ t('doctor.referral.icd10') }}</label><InputText v-model="form.icd10" placeholder="H25.1" /></div>
          <div class="field"><label>{{ t('doctor.referral.reasonLabelShort') }}</label><InputText v-model="reason" :placeholder="t('doctor.referral.reasonPlaceholder')" :disabled="!!recorded" data-testid="referral-reason" /></div>
        </div>

        <CollapsibleSection :title="t('doctor.referral.more')" class="more">
          <div class="form-col">
            <div class="field"><label>{{ t('doctor.referral.registrationDate') }}</label><InputText v-model="form.registrationDate" :placeholder="t('doctor.referral.registrationDatePlaceholder')" /><span v-if="fieldErrors.registrationDate" class="error">{{ fieldErrors.registrationDate }}</span></div>
            <div class="field"><label>{{ t('doctor.referral.referringOrg') }}</label><SearchSelect v-model="form.referringMoCode" :options="referringOrganizations" :option-label="orgLabel" option-value="moCode" :option-title="orgTitle" show-clear :placeholder="t('doctor.referral.notSpecified')" /></div>
            <div class="field checkbox"><Checkbox v-model="includeNeighbors" binary input-id="includeNeighbors" /><label for="includeNeighbors">{{ t('doctor.referral.includeNeighbors') }}</label></div>
          </div>
        </CollapsibleSection>
      </AppCard>

      <div class="col">
        <AppCard v-if="busy && !prediction"><Skeleton kind="kpi" /><Skeleton :lines="4" style="margin-top: 12px" /></AppCard>
        <AppCard v-else-if="!prediction"><EmptyState :title="t('doctor.referral.fillForm')" icon="pi pi-compass" /></AppCard>
        <AppCard v-else :title="t('doctor.referral.forecastChosen')" label origin="ml" data-testid="referral-result">
          <div class="org-line" :title="selectedOrg?.name">{{ selectedName }} <span class="caption">{{ form.moCode }}</span></div>
          <HeroNumber :value="days(prediction.p50Days)" :unit="`${t('common.days')} — ${t('hero.half')}`" label="" compact class="hero-line" />
          <div class="rows">
            <div class="row"><span class="row-main muted">{{ t('citizen.wait.p90Label') }}</span><span class="row-value strong">{{ days(prediction.p90Days) }} {{ t('common.days') }}</span></div>
            <div class="row"><span class="row-main muted">{{ t('doctor.referral.within30Row') }}</span><span class="row-value strong">{{ pct(prediction.pWithin30Days) }}</span></div>
            <div class="row"><span class="row-main muted">{{ t('doctor.referral.refusalRow') }}</span><span class="row-value strong">{{ riskText(prediction.pRefusal, prediction.refusalOrgInTraining) }}</span></div>
          </div>
          <p v-if="prediction.refusalOrgInTraining === false" class="muted small">{{ t('doctor.referral.unseenOrgHint') }}</p>
          <p v-if="prediction.queue" class="caption" style="margin: 8px 0 0">{{ t('doctor.referral.queueInfo', { len: prediction.queue.len, age: days(prediction.queue.ageP50), throughput: prediction.queue.throughputPerDay.toFixed(1) }) }}</p>
          <CollapsibleSection :title="t('explanationCard.title')" :summary="`${prediction.explanation.factors.length}`" class="why">
            <p class="muted small">{{ prediction.explanation.summary }}</p>
            <div v-for="factor in prediction.explanation.factors" :key="factor.name" class="factor small">
              <span>{{ factor.text }}</span>
              <span class="contribution" :class="factor.contribution >= 0 ? 'plus' : 'minus'">{{ signed(factor.contribution) }} {{ t('common.days') }}</span>
            </div>
            <p class="caption" style="margin: 8px 0 0">
              {{ t('explanationCard.model', { name: prediction.model.name, version: prediction.model.version, through: prediction.model.trainedThrough }) }}
              <template v-if="waitQuality">
                · {{ t('doctor.referral.qualityNote', {
                  p50: waitQuality.pinball_p50.toFixed(2), base: waitQuality.pinball_p50_baseline.toFixed(2),
                  pct: ((1 - waitQuality.pinball_p50 / waitQuality.pinball_p50_baseline) * 100).toFixed(0),
                  auc: waitQuality.auc_refusal.toFixed(2), aucBase: waitQuality.auc_refusal_baseline.toFixed(2),
                }) }}
              </template>
            </p>
          </CollapsibleSection>
          <p class="human-note">{{ t('doctor.referral.humanNote') }}</p>
        </AppCard>

        <div v-if="prediction" class="confirm-row">
          <Button :label="recorded ? t('doctor.referral.recorded') : t('common.confirm')" :disabled="!!recorded" :loading="recording" data-testid="referral-confirm" @click="record" />
          <span v-if="!recorded" class="muted small">{{ chosenName }}</span>
          <RouterLink v-else class="link-arrow small" :to="{ name: 'decisions' }">{{ t('nav.decisions') }}</RouterLink>
          <span class="spacer" />
          <RouterLink class="link-arrow small" :to="{ name: 'worklist' }">{{ t('doctor.referral.toWorklist') }}</RouterLink>
        </div>
      </div>
    </div>
  </PageShell>
</template>

<style scoped>
.pill-select { display: inline-flex; align-items: center; gap: 4px; background: var(--dm-surface); border-radius: var(--dm-radius-pill); padding: 0 6px 0 16px; min-height: 36px; }
.pill-label { font-size: var(--dm-text-sm); color: var(--dm-muted); white-space: nowrap; }
.pill-select :deep(.p-select) { background: transparent; min-height: 32px; min-width: 180px; font-weight: 500; font-size: var(--dm-text-sm); }
.main-grid { display: grid; grid-template-columns: minmax(0, 1.15fr) minmax(0, 1fr); gap: var(--dm-space-4); align-items: start; }
.col { display: flex; flex-direction: column; gap: var(--dm-space-4); min-width: 0; }
.form-card { display: flex; flex-direction: column; gap: var(--dm-space-4); }
.pair { display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); gap: 12px; }
.pair.tight { gap: 8px; }
.pair.tight :deep(.p-select) { width: 100%; min-width: 0; }
.icd-reason { grid-template-columns: 160px minmax(0, 1fr); }
.org-head { display: flex; align-items: center; gap: 10px; justify-content: space-between; }
.options { display: flex; flex-direction: column; gap: 8px; }
.option { display: flex; align-items: center; gap: 12px; border: 0; border-radius: var(--dm-radius-md); background: var(--dm-surface-2); padding: 14px 16px; text-align: left; color: var(--dm-ink); font: inherit; cursor: pointer; }
.option.selected { box-shadow: inset 0 0 0 2px var(--dm-ink); }
.option:disabled { cursor: default; opacity: 0.8; }
.radio { width: 18px; height: 18px; border-radius: 50%; border: 2px solid var(--dm-muted); box-sizing: border-box; flex: none; display: grid; place-items: center; }
.option.selected .radio { border-color: var(--dm-ink); }
.radio-dot { width: 8px; height: 8px; border-radius: 50%; background: var(--dm-ink); }
.option-text { display: flex; flex-direction: column; gap: 2px; flex: 1; min-width: 0; }
.option-title { font-size: var(--dm-text-md); font-weight: 500; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.option-wait { font-size: var(--dm-text-base); font-weight: 500; white-space: nowrap; }
.option-risk { font-size: var(--dm-text-sm); color: var(--dm-muted); width: 64px; text-align: right; }
.change { align-self: flex-start; margin-top: 4px; }
.more { background: var(--dm-surface-2); }
.more :deep(.head) { padding: 12px 16px; }
.more :deep(.head-title) { font-size: var(--dm-text-md); }
.checkbox { flex-direction: row; align-items: center; gap: 8px; }
.org-line { font-size: var(--dm-text-lg); font-weight: 500; letter-spacing: -0.01em; display: flex; align-items: baseline; gap: 8px; }
.hero-line { margin: 8px 0 4px; }
.hero-line :deep(.hero-label) { display: none; }
.strong { font-weight: 500; }
.why { margin-top: 12px; background: var(--dm-surface-2); }
.why :deep(.head) { padding: 12px 16px; }
.why :deep(.head-title) { font-size: var(--dm-text-md); }
.human-note { border-top: 1px solid var(--dm-hairline); margin: 12px 0 0; padding-top: 12px; font-size: 13px; color: var(--dm-faint); }
.confirm-row { display: flex; align-items: center; gap: 12px; flex-wrap: wrap; }
.spacer { flex: 1; }
@media (max-width: 900px) { .main-grid { grid-template-columns: 1fr; } .pair, .icd-reason { grid-template-columns: 1fr; } }
</style>
