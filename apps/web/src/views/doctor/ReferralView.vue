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

/** Ассистент направления: форма одной колонкой слева, справа одно главное число с факторами; альтернативы таблицей
 * с дельтой к выбранной организации, причина — в строке таблицы. */
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
/** причина по коду выбранной организации — поле живёт в строке таблицы */
const reasons = ref<Record<string, string>>({})
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
const heroSub = computed(() => {
  const p = prediction.value
  if (!p) return ''
  const risk = p.refusalOrgInTraining === false ? refusalWords(p.pRefusal) : pct(p.pRefusal)
  return `${t('hero.nineOfTen', { days: days(p.p90Days) })} · ${t('hero.within30', { pct: pct(p.pWithin30Days) })} · ${t('hero.refusal', { value: risk })}`
})

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

async function predict() {
  if (!complete.value) return
  busy.value = true
  error.value = null
  fieldErrors.value = {}
  recorded.value = null
  decisionKey = ''
  try {
    ;[prediction.value, alternatives.value] = await Promise.all([queue.predict(form), queue.alternatives({ ...form, limit: 5, includeNeighbors: includeNeighbors.value })])
    decisionKey = crypto.randomUUID()
  } catch (e) {
    if (e instanceof ApiError && e.status === 422 && e.errors) {
      fieldErrors.value = Object.fromEntries(Object.entries(e.errors).map(([k, v]) => [k, v.join(', ')]))
    }
    error.value = e
    prediction.value = null
    alternatives.value = null
  } finally {
    busy.value = false
  }
}

/** Рекомендация системы: самая быстрая по медиане организация среди выбранной и альтернатив. */
function recommendedMo(): string {
  const fastest = alternatives.value?.items[0]
  return fastest && prediction.value && fastest.p50Days < prediction.value.p50Days ? fastest.mo.moCode : form.moCode
}

async function record(chosen: string) {
  if (recorded.value || recording.value || !decisionKey) return
  recording.value = true
  try {
    const created = await journal.record(
      {
        subject: SUBJECT_REFERRAL,
        subjectId: referralSubjectId(form.regionKato, form.moCode, form.profileCode, form.registrationDate || new Date().toISOString().slice(0, 10)),
        recommended: { moCode: recommendedMo() },
        chosen: { moCode: chosen },
        reason: reasons.value[chosen] ?? '',
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
watch(() => [form.regionKato, form.profileCode], loadOrganizations)
watch(() => form.regionKato, loadReferringOrganizations)
</script>

<template>
  <PageShell :title="t('doctor.referral.title')" :lead="t('doctor.referral.lead')">
    <div class="split">
      <AppCard class="sticky form-card">
        <div class="group">
          <div class="group-title">{{ t('doctor.referral.groupWhere') }}</div>
          <div class="form-col">
            <div class="field"><label>{{ t('common.region') }}</label><SearchSelect v-model="form.regionKato" :options="refdata.regions" option-label="name" option-value="regionKato" :placeholder="t('common.region')" /><span class="error">{{ fieldErrors.regionKato }}</span></div>
            <div class="field"><label>{{ t('common.profile') }}</label><SearchSelect v-model="form.profileCode" :options="refdata.profiles" option-label="name" option-value="profileCode" :placeholder="t('common.profile')" /><span class="error">{{ fieldErrors.profileCode }}</span></div>
            <div class="field"><label>{{ t('common.organization') }}</label><SearchSelect v-model="form.moCode" :options="organizations" :option-label="orgLabel" option-value="moCode" :option-title="orgTitle" :placeholder="t('common.organization')" :disabled="organizations.length === 0" /></div>
          </div>
        </div>
        <div class="group">
          <div class="group-title">{{ t('doctor.referral.groupReferral') }}</div>
          <div class="form-col">
            <div class="pair">
              <div class="field"><label>{{ t('doctor.referral.purposeLabel') }}</label><Select v-model="form.referralPurpose" :options="purposes" option-label="label" option-value="value" /></div>
              <div class="field"><label>{{ t('doctor.referral.territorialLabel') }}</label><Select v-model="form.territorialType" :options="territorial" option-label="label" option-value="value" /></div>
            </div>
            <div class="field"><label>{{ t('doctor.referral.icd10') }} <span class="muted">({{ t('doctor.referral.icdOptional') }})</span></label><InputText v-model="form.icd10" placeholder="H25.1" /></div>
            <div class="field"><label>{{ t('doctor.referral.registrationDate') }}</label><InputText v-model="form.registrationDate" :placeholder="t('doctor.referral.registrationDatePlaceholder')" /><span class="error">{{ fieldErrors.registrationDate }}</span></div>
            <div class="field"><label>{{ t('doctor.referral.referringOrg') }}</label><SearchSelect v-model="form.referringMoCode" :options="referringOrganizations" :option-label="orgLabel" option-value="moCode" :option-title="orgTitle" show-clear :placeholder="t('doctor.referral.notSpecified')" /></div>
            <div class="field checkbox"><Checkbox v-model="includeNeighbors" binary input-id="includeNeighbors" /><label for="includeNeighbors">{{ t('doctor.referral.includeNeighbors') }}</label></div>
          </div>
        </div>
        <div class="actions"><Button :label="t('common.apply')" icon="pi pi-calculator" :loading="busy" :disabled="!complete" data-testid="referral-predict" @click="predict" /></div>
        <ErrorBox :error="error" />
      </AppCard>

      <div>
        <AppCard v-if="busy && !prediction"><Skeleton kind="kpi" /><Skeleton :lines="4" style="margin-top: 12px" /></AppCard>
        <AppCard v-else-if="!prediction"><EmptyState :title="t('doctor.referral.fillForm')" icon="pi pi-calculator" /></AppCard>
        <template v-else>
          <AppCard :title="`${t('doctor.referral.forecastFor')} ${selectedName}`" origin="ml" data-testid="referral-result">
            <template #header><span v-if="selectedOrg" class="muted small" :title="selectedOrg.name">{{ selectedOrg.moCode }}</span></template>
            <HeroNumber :value="days(prediction.p50Days)" :unit="t('common.days')" :label="t('hero.halfMedian')" :sub="heroSub" />
            <p v-if="prediction.refusalOrgInTraining === false" class="muted small">{{ t('doctor.referral.unseenOrgHint') }}</p>
            <p v-if="prediction.queue" class="muted small">{{ t('doctor.referral.queueInfo', { len: prediction.queue.len, age: days(prediction.queue.ageP50), throughput: prediction.queue.throughputPerDay.toFixed(1) }) }}</p>
            <h3 class="why-title">{{ t('explanationCard.title') }}</h3>
            <p class="muted small">{{ prediction.explanation.summary }}</p>
            <div v-for="factor in prediction.explanation.factors" :key="factor.name" class="factor">
              <span>{{ factor.text }}</span>
              <span class="contribution" :class="factor.contribution >= 0 ? 'plus' : 'minus'">{{ signed(factor.contribution) }} {{ t('common.days') }}</span>
            </div>
            <p class="muted small" style="margin: 8px 0 0">
              {{ t('explanationCard.model', { name: prediction.model.name, version: prediction.model.version, through: prediction.model.trainedThrough }) }}
              <template v-if="waitQuality">
                · {{ t('doctor.referral.qualityNote', {
                  p50: waitQuality.pinball_p50.toFixed(2), base: waitQuality.pinball_p50_baseline.toFixed(2),
                  pct: ((1 - waitQuality.pinball_p50 / waitQuality.pinball_p50_baseline) * 100).toFixed(0),
                  auc: waitQuality.auc_refusal.toFixed(2), aucBase: waitQuality.auc_refusal_baseline.toFixed(2),
                }) }}
              </template>
            </p>
          </AppCard>

          <AppCard v-if="alternatives" :title="t('doctor.referral.alternativesTitle')" origin="ml" style="margin-top: 16px">
            <p v-if="alternatives.items.length === 0" class="muted">{{ t('doctor.referral.noAlternatives') }}</p>
            <div v-else class="table-wrap">
              <table class="dense-table">
                <thead>
                  <tr>
                    <th>{{ t('common.organization') }}</th><th class="num">p50, {{ t('common.days') }}</th><th class="num">Δ</th><th class="num">p90</th>
                    <th class="num">{{ t('doctor.referral.refusalShort') }}</th><th class="num">{{ t('doctor.referral.distance') }}</th><th>{{ t('doctor.referral.reasonShort') }}</th><th></th>
                  </tr>
                </thead>
                <tbody>
                  <tr v-for="a in alternatives.items" :key="a.mo.moCode">
                    <td :title="a.mo.name">
                      {{ shortOrgName(a.mo.name) }} <span class="mono muted">{{ a.mo.moCode }}</span>
                      <div v-if="a.isNeighborRegion" class="muted small">{{ t('doctor.referral.neighborRegion', { region: refdata.regionName(a.mo.regionKato) }) }}</div>
                    </td>
                    <td class="num">{{ days(a.p50Days) }}</td>
                    <td class="num" :class="a.p50Days - prediction.p50Days < 0 ? 'delta-down' : 'delta-up'">{{ signed(a.p50Days - prediction.p50Days, 0) }}</td>
                    <td class="num">{{ days(a.p90Days) }}</td>
                    <td class="num">{{ pct(a.pRefusal) }}</td>
                    <td class="num muted">{{ a.distanceKm > 0 ? `${a.distanceKm.toFixed(0)} ${t('doctor.referral.km')}` : '—' }}</td>
                    <td class="reason-cell"><InputText v-model="reasons[a.mo.moCode]" size="small" :placeholder="t('doctor.referral.reasonShort')" :disabled="!!recorded" /></td>
                    <td><Button :label="t('route.referHereShort')" size="small" severity="secondary" :disabled="!!recorded" :loading="recording" @click="record(a.mo.moCode)" /></td>
                  </tr>
                  <tr class="keep-row">
                    <td colspan="6"><b>{{ selectedName }}</b> <span class="muted small">· {{ t('doctor.referral.keepSelected') }}</span></td>
                    <td class="reason-cell"><InputText v-model="reasons[form.moCode]" size="small" :placeholder="t('doctor.referral.reasonShort')" :disabled="!!recorded" /></td>
                    <td><Button :label="t('doctor.referral.keepShort')" size="small" icon="pi pi-check" :disabled="!!recorded" :loading="recording" @click="record(form.moCode)" /></td>
                  </tr>
                </tbody>
              </table>
            </div>
            <p v-if="recorded" class="muted small" style="margin-top: 8px">{{ t('doctor.referral.recorded') }}: <span class="mono">{{ recorded }}</span> · <RouterLink :to="{ name: 'decisions' }">{{ t('nav.decisions') }}</RouterLink></p>
          </AppCard>
        </template>
      </div>
    </div>
  </PageShell>
</template>

<style scoped>
.form-card { display: flex; flex-direction: column; gap: var(--dm-space-4); }
.group-title { font-size: 0.8rem; text-transform: uppercase; letter-spacing: 0.06em; color: var(--dm-muted); margin-bottom: 8px; }
.pair { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; }
.checkbox { flex-direction: row; align-items: center; gap: 8px; }
.checkbox label { color: var(--dm-ink); font-size: 0.9rem; }
.form-card .actions { margin-top: 0; }
.why-title { font-size: 0.95rem; margin: 16px 0 4px; }
.reason-cell { min-width: 180px; }
.keep-row td { background: var(--dm-surface-2); }
</style>
