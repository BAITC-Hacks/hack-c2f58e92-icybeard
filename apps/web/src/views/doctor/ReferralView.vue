<script setup lang="ts">
import Button from 'primevue/button'
import Checkbox from 'primevue/checkbox'
import InputText from 'primevue/inputtext'
import Select from 'primevue/select'
import Textarea from 'primevue/textarea'
import { useToast } from 'primevue/usetoast'
import { computed, onMounted, reactive, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute } from 'vue-router'
import { ApiError } from '@/api/client'
import { analytics, journal, queue } from '@/api/endpoints'
import type { AlternativesResponse, OrganizationItem, PredictResponse, QualitySplit } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import ExplanationCard from '@/components/ExplanationCard.vue'
import AppCard from '@/components/ui/AppCard.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import KpiRow from '@/components/ui/KpiRow.vue'
import KpiTile from '@/components/ui/KpiTile.vue'
import PageShell from '@/components/ui/PageShell.vue'
import Section from '@/components/ui/Section.vue'
import Skeleton from '@/components/ui/Skeleton.vue'
import { referralSubjectId, SUBJECT_REFERRAL } from '@/lib/decision'
import { days, pct, refusalWords } from '@/lib/format'
import { FINANCE_DEFAULT, PURPOSE_VALUES, TERRITORIAL_VALUES } from '@/lib/referralContract'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'

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
  // пусто — сервис моделей берёт день после последних данных очереди: модель обучена на I квартале 2025,
  // сегодняшняя дата вывела бы признаки календаря за пределы обучения
  registrationDate: '',
  // необязательно: если направление внутри своей же организации, модель получает признак same_mo
  referringMoCode: '',
})
const organizations = ref<OrganizationItem[]>([])
// список для «направляющей организации» — все организации региона, не только те, что лечат по этому профилю
const referringOrganizations = ref<OrganizationItem[]>([])
const prediction = ref<PredictResponse | null>(null)
const alternatives = ref<AlternativesResponse | null>(null)
const includeNeighbors = ref(false)
const error = ref<unknown>(null)
const fieldErrors = ref<Record<string, string>>({})
const busy = ref(false)
const reason = ref('')
const recorded = ref<string | null>(null)
const recording = ref(false)
// один ключ идемпотентности на расчёт: повторный клик по тому же прогнозу не создаёт вторую запись
let decisionKey = ''
// метрики модели против baseline из отчёта обучения — та же цифра, что на странице качества (§7.4)
const waitQuality = ref<QualitySplit | null>(null)

const complete = computed(() => !!form.regionKato && !!form.moCode && !!form.profileCode)
const purposes = computed(() => PURPOSE_VALUES.map((value, i) => ({ value, label: t(`doctor.referral.purpose.${i}`) })))
const territorial = computed(() => TERRITORIAL_VALUES.map((value, i) => ({ value, label: t(`doctor.referral.territorial.${i}`) })))
const selectedName = computed(() => organizations.value.find((o) => o.moCode === form.moCode)?.name ?? form.moCode)

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
  if (form.referringMoCode && !referringOrganizations.value.some((o) => o.moCode === form.referringMoCode)) {
    form.referringMoCode = ''
  }
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
        reason: reason.value,
      },
      decisionKey,
    )
    recorded.value = created.decisionId
    toast.add({ severity: 'success', summary: t('doctor.referral.decisionRecorded'), detail: created.decisionId, life: 3000 })
  } catch (e) {
    error.value = e
  } finally {
    recording.value = false
  }
}

onMounted(async () => {
  await refdata.load()
  await Promise.all([loadOrganizations(), loadReferringOrganizations()])
  // прогноз на монтировании — только когда форма уже заполнена переходом со списка; иначе врач заполняет сам
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
    <Section :cols="2">
      <AppCard :title="t('doctor.referral.formTitle')">
        <div class="form-grid">
          <div class="field"><label>{{ t('common.region') }}</label><Select v-model="form.regionKato" :options="refdata.regions" option-label="name" option-value="regionKato" filter :placeholder="t('common.region')" /><span class="error">{{ fieldErrors.regionKato }}</span></div>
          <div class="field"><label>{{ t('common.profile') }}</label><Select v-model="form.profileCode" :options="refdata.profiles" option-label="name" option-value="profileCode" filter :placeholder="t('common.profile')" /><span class="error">{{ fieldErrors.profileCode }}</span></div>
          <div class="field"><label>{{ t('common.organization') }}</label><Select v-model="form.moCode" :options="organizations" option-label="name" option-value="moCode" filter :placeholder="t('common.organization')" :disabled="organizations.length === 0" /></div>
          <div class="field"><label>{{ t('doctor.referral.icd10') }} <span class="muted">({{ t('doctor.referral.icdOptional') }})</span></label><InputText v-model="form.icd10" placeholder="H25.1" /></div>
          <div class="field">
            <label>{{ t('doctor.referral.referringOrg') }}</label>
            <Select v-model="form.referringMoCode" :options="referringOrganizations" option-label="name" option-value="moCode" filter show-clear :placeholder="t('doctor.referral.notSpecified')" />
          </div>
          <div class="field"><label>{{ t('doctor.referral.purposeLabel') }}</label><Select v-model="form.referralPurpose" :options="purposes" option-label="label" option-value="value" /></div>
          <div class="field"><label>{{ t('doctor.referral.territorialLabel') }}</label><Select v-model="form.territorialType" :options="territorial" option-label="label" option-value="value" /></div>
          <div class="field"><label>{{ t('doctor.referral.registrationDate') }}</label><InputText v-model="form.registrationDate" :placeholder="t('doctor.referral.registrationDatePlaceholder')" /><span class="error">{{ fieldErrors.registrationDate }}</span></div>
        </div>
        <div class="field" style="display: flex; align-items: center; gap: 8px">
          <Checkbox v-model="includeNeighbors" binary input-id="includeNeighbors" />
          <label for="includeNeighbors">{{ t('doctor.referral.includeNeighbors') }}</label>
        </div>
        <div class="actions"><Button :label="t('common.apply')" icon="pi pi-calculator" :loading="busy" :disabled="!complete" data-testid="referral-predict" @click="predict" /></div>
        <ErrorBox :error="error" />
      </AppCard>
      <div>
        <AppCard v-if="busy && !prediction"><Skeleton kind="kpi" /><Skeleton :lines="4" style="margin-top: 12px" /></AppCard>
        <AppCard v-else-if="!prediction"><EmptyState :title="t('doctor.referral.fillForm')" icon="pi pi-calculator" /></AppCard>
        <template v-else>
          <AppCard :title="`${t('doctor.referral.forecastFor')} ${selectedName}`" origin="ml">
            <KpiRow>
              <KpiTile :value="days(prediction.p50Days)" :label="t('doctor.referral.medianWait')" />
              <KpiTile :value="days(prediction.p90Days)" :label="`p90, ${t('common.days')}`" />
              <KpiTile :value="pct(prediction.pWithin30Days)" :label="t('doctor.referral.within30')" />
              <KpiTile :value="prediction.refusalOrgInTraining === false ? refusalWords(prediction.pRefusal) : pct(prediction.pRefusal)" :label="t('doctor.referral.refusalRisk')" />
            </KpiRow>
            <p v-if="prediction.refusalOrgInTraining === false" class="muted" style="margin-top: 8px">{{ t('doctor.referral.unseenOrgHint') }}</p>
            <p v-if="prediction.queue" class="muted" style="margin-top: 8px">
              {{ t('doctor.referral.queueInfo', { len: prediction.queue.len, age: days(prediction.queue.ageP50), throughput: prediction.queue.throughputPerDay.toFixed(1) }) }}
            </p>
          </AppCard>
          <ExplanationCard :explanation="prediction.explanation" :model="prediction.model" :unit="t('common.days')" style="margin-top: 16px" />
          <p v-if="waitQuality" class="muted" style="margin-top: 8px">
            {{ t('doctor.referral.qualityNote', {
              p50: waitQuality.pinball_p50.toFixed(2), base: waitQuality.pinball_p50_baseline.toFixed(2),
              pct: ((1 - waitQuality.pinball_p50 / waitQuality.pinball_p50_baseline) * 100).toFixed(0),
              auc: waitQuality.auc_refusal.toFixed(2), aucBase: waitQuality.auc_refusal_baseline.toFixed(2),
            }) }}
          </p>
        </template>
      </div>
    </Section>
    <Section v-if="alternatives" :cols="1">
      <AppCard :title="t('doctor.referral.alternativesTitle')" origin="ml">
        <p v-if="alternatives.items.length === 0" class="muted">{{ t('doctor.referral.noAlternatives') }}</p>
        <table v-else class="plain">
          <thead><tr class="muted"><th>{{ t('common.organization') }}</th><th>p50, {{ t('common.days') }}</th><th>p90, {{ t('common.days') }}</th><th>{{ t('doctor.referral.refusalShort') }}</th><th>{{ t('doctor.referral.distance') }}</th><th></th></tr></thead>
          <tbody>
            <tr v-for="a in alternatives.items" :key="a.mo.moCode">
              <td>
                {{ a.mo.name }} <span class="muted">({{ a.mo.moCode }})</span>
                <span v-if="a.isNeighborRegion" class="muted">— {{ t('doctor.referral.neighborRegion', { region: refdata.regionName(a.mo.regionKato) }) }}</span>
              </td>
              <td class="tabular">{{ days(a.p50Days) }}</td>
              <td class="tabular">{{ days(a.p90Days) }}</td>
              <td class="tabular">{{ pct(a.pRefusal) }}</td>
              <td class="muted">{{ a.distanceKm > 0 ? `${a.distanceKm.toFixed(0)} ${t('doctor.referral.km')}` : t('doctor.referral.noCoordinates') }}</td>
              <td><Button :label="t('doctor.referral.referHere')" size="small" severity="secondary" :disabled="!!recorded" :loading="recording" @click="record(a.mo.moCode)" /></td>
            </tr>
          </tbody>
        </table>
        <div class="field" style="margin-top: 12px"><label>{{ t('doctor.referral.reasonLabel') }}</label><Textarea v-model="reason" rows="2" auto-resize /></div>
        <div class="actions">
          <Button :label="t('doctor.referral.keepSelected')" icon="pi pi-check" :disabled="!!recorded" :loading="recording" @click="record(form.moCode)" />
          <span v-if="recorded" class="muted">{{ t('doctor.referral.recorded') }}: {{ recorded }}</span>
        </div>
      </AppCard>
    </Section>
  </PageShell>
</template>

<style scoped>
table.plain { width: 100%; border-collapse: collapse; }
table.plain th { text-align: left; font-weight: 500; }
table.plain td { padding: 8px 4px; border-top: 1px solid var(--dm-hairline); }
</style>
