<script setup lang="ts">
import Select from 'primevue/select'
import { useToast } from 'primevue/usetoast'
import { computed, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute, useRouter } from 'vue-router'
import { ApiError } from '@/api/client'
import { analytics, queue, refdata as refdataApi } from '@/api/endpoints'
import type { Anomaly, ForecastResponse, OrganizationItem, OrganizationSeries, OverloadedOrganization, Seasonality } from '@/api/types'
import AnomalyFeed from '@/components/AnomalyFeed.vue'
import ErrorBox from '@/components/ErrorBox.vue'
import OriginTag from '@/components/OriginTag.vue'
import OverloadedTable from '@/components/OverloadedTable.vue'
import QueueChart from '@/components/QueueChart.vue'
import SeriesChart from '@/components/SeriesChart.vue'
import { days, pct } from '@/lib/format'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'
import { useLocaleFormat } from '@/composables/useLocaleFormat'
import PageShell from '@/components/ui/PageShell.vue'

/** Переключатель потока для прогноза справа (3.1): у каждого потока свой второй ключ сущности и единица измерения —
 * госпитализации по профилю, приёмный покой по конкретной организации региона (нужен entity.mo_key, не mo_code —
 * см. gold.anomalies/mo_registry.name_key), вакцинация по коду плана. */
const STREAM_DEFS = [
  { value: 'admissions', streamId: 'admissions_monthly' },
  { value: 'er_visits', streamId: 'er_visits_daily' },
  { value: 'vac', streamId: 'vac_monthly' },
] as const
type StreamKind = (typeof STREAM_DEFS)[number]['value']

const { t } = useI18n()
const { num } = useLocaleFormat()
const route = useRoute()
const router = useRouter()
const refdata = useRefdataStore()
const auth = useAuthStore()
const toast = useToast()

const kato = computed(() => String(route.params.kato))
const organizations = ref<OrganizationItem[]>([])
const moCode = ref<string | null>(null)
const profile = ref<string>('')
const streamKind = ref<StreamKind>('admissions')
const vaccinationPlans = ref<string[]>([])
const vaccinationPlan = ref<string | null>(null)
const series = ref<OrganizationSeries | null>(null)
const forecast = ref<ForecastResponse | null>(null)
const forecastHint = ref<string | null>(null)
const anomalies = ref<Anomaly[]>([])
const error = ref<unknown>(null)
const seriesError = ref<unknown>(null)
const seasonality = ref<Seasonality[]>([])
const overloaded = ref<OverloadedOrganization[]>([])

const STREAMS = computed(() => STREAM_DEFS.map((s) => ({ ...s, label: t(`gov.region.stream.${s.value}`), unit: t(`gov.region.streamUnit.${s.value}`) })))
const streamMeta = computed(() => STREAMS.value.find((s) => s.value === streamKind.value)!)
const selectedOrganization = computed(() => organizations.value.find((o) => o.moCode === moCode.value) ?? null)

const bedForecast = ref<ForecastResponse | null>(null)
const bedForecastHint = ref<string | null>(null)

/** Дни в месяце периода "YYYY-MM" (без новых зависимостей: следующий месяц минус один день). */
function daysInPeriod(period: string): number {
  const [y, m] = period.split('-').map(Number)
  return new Date(y, m, 0).getDate()
}

const TARGET_OCCUPANCY = 0.85

/** Потребность в койках (5.1): прогноз bed_days того же потока admissions_monthly (профильный срез региона),
 * переведённый в число коек по занятости TARGET_OCCUPANCY — формула поверх ML-прогноза, не отдельная модель. */
const bedDemand = computed(() => {
  if (!bedForecast.value) return []
  const short = t('gov.region.monthsShort').split(',')
  return bedForecast.value.points.map((p) => {
    const beds = Math.ceil(p.yhat / (daysInPeriod(p.period) * TARGET_OCCUPANCY))
    const m = Number(p.period.slice(5, 7))
    const y = p.period.slice(0, 4)
    return { period: p.period, label: `${short[m]} ${y}`, beds }
  })
})

async function loadBedForecast() {
  bedForecast.value = null
  bedForecastHint.value = null
  try {
    bedForecast.value = await analytics.forecast('bed_days_monthly', { region_kato: kato.value, profile_code: profile.value }, 3)
  } catch (e) {
    if (e instanceof ApiError && e.status === 404) {
      bedForecastHint.value = t('gov.region.forecastNotBuiltProfile')
      return
    }
    throw e
  }
}

/** Для плоского прогноза: месяцы горизонта с сезонным множителем NHS (форма плановых госпитализаций). Ориентир
 * подобран только для потока госпитализаций — для приёмного покоя и вакцинации сезонность другая. */
const flatSeasonHint = computed(() => {
  if (streamKind.value !== 'admissions' || !forecast.value?.flat) return null
  const adm = new Map(seasonality.value.filter((s) => s.seriesId === 'rtt_admitted_per_day').map((s) => [s.month, s.multiplier]))
  if (adm.size !== 12) return null
  const short = t('gov.region.monthsShort').split(',')
  return forecast.value.points
    .map((p) => {
      const m = Number(p.period.slice(5, 7))
      const delta = (adm.get(m)! - 1) * 100
      return `${short[m]} ${delta > 0 ? '+' : '−'}${Math.abs(delta).toFixed(0)} %`
    })
    .join(', ')
})

/** Сущность для выбранного потока — null, если для неё ещё не выбран нужный второй ключ (организация/план). */
function forecastEntity(): Record<string, string> | null {
  if (streamKind.value === 'admissions') return { region_kato: kato.value, profile_code: profile.value }
  if (streamKind.value === 'er_visits') return selectedOrganization.value?.moKey ? { region_kato: kato.value, mo_key: selectedOrganization.value.moKey } : null
  return vaccinationPlan.value ? { region_kato: kato.value, vaccination_plan: vaccinationPlan.value } : null
}

async function loadForecast() {
  forecast.value = null
  forecastHint.value = null
  const entity = forecastEntity()
  if (!entity) {
    forecastHint.value = streamKind.value === 'er_visits' ? t('gov.region.pickOrganization') : t('gov.region.pickVaccinationPlan')
    return
  }
  try {
    forecast.value = await analytics.forecast(streamMeta.value.streamId, entity, 3)
  } catch (e) {
    if (e instanceof ApiError && e.status === 404) {
      forecastHint.value = t('gov.region.forecastNotBuilt')
      return
    }
    throw e
  }
}

async function loadRegion() {
  error.value = null
  try {
    organizations.value = await refdata.organizationsOf(kato.value, profile.value)
    moCode.value = organizations.value[0]?.moCode ?? null
    anomalies.value = (await analytics.anomalies({ regionKato: kato.value, status: 'open', size: 10 })).items
    overloaded.value = (await queue.overloaded(kato.value)).items
    await loadForecast()
    await loadBedForecast()
  } catch (e) {
    error.value = e
  }
}

function goToOrganization(code: string) {
  router.push({ name: 'organization', params: { moCode: code }, query: { kato: kato.value, profile: profile.value } })
}

function goToSimulator(item: OverloadedOrganization) {
  router.push({ name: 'simulator', query: { region: item.regionKato, profile: item.profileCode } })
}

async function loadSeries() {
  series.value = null
  seriesError.value = null
  if (!moCode.value) return
  try {
    series.value = await queue.organization(moCode.value, profile.value, 90)
  } catch (e) {
    if (e instanceof ApiError && e.status === 404) return
    seriesError.value = e
  }
}

async function loadVaccinationPlans() {
  try {
    vaccinationPlans.value = (await refdataApi.vaccinationPlans(kato.value)).items
    vaccinationPlan.value = vaccinationPlans.value[0] ?? null
  } catch {
    vaccinationPlans.value = [] // витрина ещё не опубликована
  }
}

async function ack(id: string, comment: string) {
  try {
    await analytics.ack(id, comment)
    anomalies.value = anomalies.value.filter((a) => a.id !== id)
    toast.add({ severity: 'success', summary: t('gov.map.ackToast'), life: 2500 })
  } catch (e) {
    error.value = e
  }
}

async function dismiss(id: string, comment: string) {
  try {
    await analytics.ack(id, comment, 'dismissed')
    anomalies.value = anomalies.value.filter((a) => a.id !== id)
    toast.add({ severity: 'info', summary: t('gov.map.dismissToast'), life: 2500 })
  } catch (e) {
    error.value = e
  }
}

onMounted(async () => {
  await refdata.load()
  if (!profile.value) profile.value = refdata.topProfileCode() // профиль с наибольшим числом направлений, не зашитый код
  await loadVaccinationPlans()
  await loadRegion()
  await loadSeries()
  try {
    seasonality.value = (await refdataApi.seasonality()).items
  } catch {
    seasonality.value = [] // подсказка сезонности опциональна
  }
})
watch(kato, async () => {
  await loadVaccinationPlans()
  await loadRegion()
  await loadSeries()
})
watch(profile, async () => {
  await loadRegion()
  await loadSeries()
})
watch(moCode, loadSeries)
watch(streamKind, loadForecast)
watch(vaccinationPlan, () => {
  if (streamKind.value === 'vac') loadForecast()
})
</script>

<template>
  <PageShell :title="refdata.regionName(kato)" :lead="t('gov.region.lead')">
    <div class="actions" style="margin: 0 0 12px">
      <Select v-model="profile" :options="refdata.profiles" option-label="name" option-value="profileCode" filter size="small" style="min-width: 280px" />
      <Select v-model="moCode" :options="organizations" option-label="name" option-value="moCode" filter size="small" :placeholder="t('common.organization')" style="min-width: 360px; max-width: 100%" />
      <RouterLink v-if="moCode" :to="{ name: 'organization', params: { moCode }, query: { kato, profile } }">{{ t('gov.region.toOrganization') }} →</RouterLink>
    </div>
    <ErrorBox :error="error" />
    <div class="grid cols-2">
      <div>
        <ErrorBox :error="seriesError" />
        <div v-if="series" class="kpi" style="margin-bottom: 12px">
          <div class="item"><div class="value">{{ series.days.at(-1)?.queueLen ?? '—' }}</div><div class="label">{{ t('gov.region.queueNow') }}</div></div>
          <div class="item"><div class="value">{{ days(series.throughput?.throughputPerDay, 1) }}</div><div class="label">{{ t('gov.region.admissionsPerDay4w') }}</div></div>
          <div class="item"><div class="value">{{ days(series.throughput?.waitP50Days) }} / {{ days(series.throughput?.waitP90Days) }}</div><div class="label">{{ t('gov.region.factP50P90') }}</div></div>
          <div class="item"><div class="value">{{ pct(series.throughput?.refusalRate4w) }}</div><div class="label">{{ t('gov.region.refusals4w') }}</div></div>
        </div>
        <QueueChart v-if="series" :days="series.days" :title="t('gov.region.queueChartTitle')" />
        <p v-else class="muted">{{ t('gov.region.noQueueSeries') }}</p>
      </div>
      <div>
        <div class="actions" style="margin: 0 0 8px">
          <Select v-model="streamKind" :options="STREAMS" option-label="label" option-value="value" size="small" style="min-width: 220px" />
          <Select
            v-if="streamKind === 'vac'"
            v-model="vaccinationPlan"
            :options="vaccinationPlans"
            filter
            size="small"
            :placeholder="t('gov.region.vaccinationPlan')"
            style="min-width: 240px"
          />
        </div>
        <SeriesChart
          v-if="forecast"
          :history="forecast.history"
          :points="forecast.points"
          :title="streamKind === 'admissions' ? `${t('gov.region.stream.admissions')}: ${refdata.profileName(profile)}` : streamKind === 'er_visits' ? `${t('gov.region.stream.er_visits')}: ${selectedOrganization?.name ?? ''}` : `${t('gov.region.stream.vac')}: ${vaccinationPlan ?? ''}`"
          :unit="streamMeta.unit"
        />
        <p v-else-if="forecastHint" class="muted">{{ forecastHint }}</p>
        <p v-if="forecast" class="muted">
          {{ t('gov.map.backtest') }}: sMAPE {{ pct(forecast.backtest.smape, 1) }} {{ t('gov.map.vsNaive') }} {{ pct(forecast.backtest.baselineSmape, 1) }}, MASE {{ forecast.backtest.mase.toFixed(2) }}.
          {{ forecast.model.name }} {{ forecast.model.version }}. <OriginTag kind="ml" />
          <span v-if="forecast.flat" class="synthetic" style="margin-left: 6px">{{ t('gov.region.flatForecastHint') }}</span>
        </p>
        <template v-if="streamKind === 'admissions'">
          <p v-if="flatSeasonHint" class="muted">{{ t('gov.region.seasonHint') }}: {{ flatSeasonHint }} {{ t('gov.region.seasonHintSuffix') }}</p>
          <!-- коэффициент и источник: refdata/external_benchmarks.yaml (diagnostics.dm01_tests_per_admission) -->
          <p v-if="forecast && forecast.points.length" class="muted">
            {{ t('gov.region.diagnosticsLoad') }}: ≈ {{ num(Math.round((forecast.points.reduce((s, p) => s + p.yhat, 0) / forecast.points.length) * 1.5)) }}
            {{ t('gov.region.diagnosticsLoadSuffix') }}
          </p>
          <p v-else-if="!forecast && !forecastHint" class="muted">{{ t('gov.region.forecastNotBuiltProfile') }}</p>
        </template>
      </div>
    </div>
    <div class="grid cols-2" style="margin-top: 16px">
      <div class="card">
        <h2>{{ t('gov.region.signals') }} <OriginTag kind="formula" /></h2>
        <AnomalyFeed :items="anomalies" :can-ack="auth.hasRole('chief', 'regulator')" @ack="ack" @dismiss="dismiss" />
      </div>
      <div class="card">
        <h2>{{ t('gov.map.overloaded') }} <OriginTag kind="formula" /></h2>
        <OverloadedTable :items="overloaded" @organization="goToOrganization" @simulate="goToSimulator" />
      </div>
      <div class="card">
        <h2>{{ t('gov.region.bedDemand.title') }}: {{ refdata.profileName(profile) }} <OriginTag kind="ml" /> <OriginTag kind="formula" /></h2>
        <ul v-if="bedDemand.length" class="muted">
          <li v-for="d in bedDemand" :key="d.period">{{ d.label }}: {{ d.beds }} {{ t('gov.region.bedDemand.unit') }}</li>
        </ul>
        <p v-else-if="bedForecastHint" class="muted">{{ bedForecastHint }}</p>
        <p class="muted">{{ t('gov.region.bedDemand.formula') }}</p>
      </div>
    </div>
  </PageShell>
</template>
