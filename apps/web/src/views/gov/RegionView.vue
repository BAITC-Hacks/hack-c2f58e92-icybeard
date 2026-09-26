<script setup lang="ts">
import Select from 'primevue/select'
import Tab from 'primevue/tab'
import TabList from 'primevue/tablist'
import TabPanel from 'primevue/tabpanel'
import TabPanels from 'primevue/tabpanels'
import Tabs from 'primevue/tabs'
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
import KpiRow from '@/components/ui/KpiRow.vue'
import KpiTile from '@/components/ui/KpiTile.vue'
import PageShell from '@/components/ui/PageShell.vue'
import SearchSelect from '@/components/ui/SearchSelect.vue'
import { useLocaleFormat } from '@/composables/useLocaleFormat'
import { days, pct, shortOrgName } from '@/lib/format'
import { dateShort } from '@/lib/route'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'

/** Регион как сущность: шапка с профилем и периодом, вкладки Очередь · Прогноз · Сигналы · Организации.
 * Поток прогноза справа (3.1): у каждого потока свой второй ключ сущности и единица измерения. */
const STREAM_DEFS = [
  { value: 'admissions', streamId: 'admissions_monthly' },
  { value: 'er_visits', streamId: 'er_visits_daily' },
  { value: 'vac', streamId: 'vac_monthly' },
] as const
type StreamKind = (typeof STREAM_DEFS)[number]['value']
const TARGET_OCCUPANCY = 0.85

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
const bedForecast = ref<ForecastResponse | null>(null)
const bedForecastHint = ref<string | null>(null)
const anomalies = ref<Anomaly[]>([])
const overloaded = ref<OverloadedOrganization[]>([])
const seasonality = ref<Seasonality[]>([])
const error = ref<unknown>(null)
const seriesError = ref<unknown>(null)
const tab = ref('queue')

const STREAMS = computed(() => STREAM_DEFS.map((s) => ({ ...s, label: t(`gov.region.stream.${s.value}`), unit: t(`gov.region.streamUnit.${s.value}`) })))
const streamMeta = computed(() => STREAMS.value.find((s) => s.value === streamKind.value)!)
const selectedOrganization = computed(() => organizations.value.find((o) => o.moCode === moCode.value) ?? null)
const period = computed(() => (series.value?.days.length ? `${dateShort(series.value.days[0]!.day)} — ${dateShort(series.value.days.at(-1)!.day)}` : ''))
const planOptions = computed(() => vaccinationPlans.value.map((plan) => ({ plan })))
const orgLabel = (o: OrganizationItem) => shortOrgName(o.name)
const orgTitle = (o: OrganizationItem) => o.name

function daysInPeriod(period: string): number {
  const [y, m] = period.split('-').map(Number)
  return new Date(y!, m!, 0).getDate()
}

/** Потребность в койках (5.1): прогноз bed_days → койки по целевой занятости — формула поверх ML-прогноза. */
const bedDemand = computed(() => {
  if (!bedForecast.value) return []
  const short = t('gov.region.monthsShort').split(',')
  return bedForecast.value.points.map((p) => ({ period: p.period, label: `${short[Number(p.period.slice(5, 7))]} ${p.period.slice(0, 4)}`, beds: Math.ceil(p.yhat / (daysInPeriod(p.period) * TARGET_OCCUPANCY)) }))
})

/** Для плоского прогноза госпитализаций — месяцы горизонта с сезонным множителем NHS. */
const flatSeasonHint = computed(() => {
  if (streamKind.value !== 'admissions' || !forecast.value?.flat) return null
  const adm = new Map(seasonality.value.filter((s) => s.seriesId === 'rtt_admitted_per_day').map((s) => [s.month, s.multiplier]))
  if (adm.size !== 12) return null
  const short = t('gov.region.monthsShort').split(',')
  return forecast.value.points
    .map((p) => {
      const delta = (adm.get(Number(p.period.slice(5, 7)))! - 1) * 100
      return `${short[Number(p.period.slice(5, 7))]} ${delta > 0 ? '+' : '−'}${Math.abs(delta).toFixed(0)} %`
    })
    .join(', ')
})
const forecastTitle = computed(() => {
  if (streamKind.value === 'admissions') return `${t('gov.region.stream.admissions')}: ${refdata.profileName(profile.value)}`
  if (streamKind.value === 'er_visits') return `${t('gov.region.stream.er_visits')}: ${selectedOrganization.value ? shortOrgName(selectedOrganization.value.name) : ''}`
  return `${t('gov.region.stream.vac')}: ${vaccinationPlan.value ?? ''}`
})

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
    if (e instanceof ApiError && e.status === 404) forecastHint.value = t('gov.region.forecastNotBuilt')
    else throw e
  }
}

async function loadBedForecast() {
  bedForecast.value = null
  bedForecastHint.value = null
  try {
    bedForecast.value = await analytics.forecast('bed_days_monthly', { region_kato: kato.value, profile_code: profile.value }, 3)
  } catch (e) {
    if (e instanceof ApiError && e.status === 404) bedForecastHint.value = t('gov.region.forecastNotBuiltProfile')
    else throw e
  }
}

async function loadRegion() {
  error.value = null
  try {
    organizations.value = await refdata.organizationsOf(kato.value, profile.value)
    silentMo = true // первая организация подставляется без повторной загрузки рядов: loadSeries вызывается явно
    moCode.value = organizations.value[0]?.moCode ?? null
    anomalies.value = (await analytics.anomalies({ regionKato: kato.value, status: 'open', size: 10 })).items
    overloaded.value = (await queue.overloaded(kato.value)).items
    await loadForecast()
    await loadBedForecast()
  } catch (e) {
    error.value = e
  }
}

async function loadSeries() {
  series.value = null
  seriesError.value = null
  if (!moCode.value) return
  try {
    series.value = await queue.organization(moCode.value, profile.value, 90)
  } catch (e) {
    if (!(e instanceof ApiError && e.status === 404)) seriesError.value = e
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

async function resolve(id: string, comment: string, status: 'acknowledged' | 'dismissed') {
  try {
    await analytics.ack(id, comment, status)
    anomalies.value = anomalies.value.filter((a) => a.id !== id)
    toast.add({ severity: status === 'acknowledged' ? 'success' : 'info', summary: t(status === 'acknowledged' ? 'gov.map.ackToast' : 'gov.map.dismissToast'), life: 2500 })
  } catch (e) {
    error.value = e
  }
}

const toOrganization = (code: string) => router.push({ name: 'organization', params: { moCode: code }, query: { kato: kato.value, profile: profile.value } })

onMounted(async () => {
  await refdata.load()
  if (!profile.value) {
    silentProfile = true
    profile.value = refdata.topProfileCode() // профиль с наибольшим числом направлений, не зашитый код
  }
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
let silentProfile = false
let silentMo = false
watch(profile, async () => {
  if (silentProfile) {
    silentProfile = false
    return
  }
  await loadRegion()
  await loadSeries()
})
watch(moCode, () => {
  if (silentMo) {
    silentMo = false
    return
  }
  loadSeries()
})
watch(streamKind, loadForecast)
watch(vaccinationPlan, () => {
  if (streamKind.value === 'vac') loadForecast()
})
</script>

<template>
  <PageShell :title="refdata.regionName(kato)" :back="{ to: { name: 'gov' }, label: t('nav.short.gov') }" :lead="t('gov.region.lead')">
    <template #subtitle>{{ refdata.profileName(profile) }}<template v-if="period"> · {{ period }}</template></template>
    <template #actions>
      <SearchSelect v-model="profile" :options="refdata.profiles" option-label="name" option-value="profileCode" size="small" class="w-profile" />
      <SearchSelect v-model="moCode" :options="organizations" :option-label="orgLabel" option-value="moCode" :option-title="orgTitle" size="small" :placeholder="t('common.organization')" class="w-org" />
      <RouterLink v-if="moCode" :to="{ name: 'organization', params: { moCode }, query: { kato, profile } }" class="small">{{ t('gov.region.toOrganization') }} →</RouterLink>
    </template>
    <ErrorBox :error="error" />

    <Tabs v-model:value="tab" class="region-tabs">
      <TabList>
        <Tab value="queue">{{ t('gov.region.tabQueue') }}</Tab>
        <Tab value="forecast">{{ t('gov.region.tabForecast') }}</Tab>
        <Tab value="signals">{{ t('gov.region.signals') }} <span class="muted">· {{ anomalies.length }}</span></Tab>
        <Tab value="organizations">{{ t('gov.region.tabOrganizations') }} <span class="muted">· {{ overloaded.length }}</span></Tab>
      </TabList>
      <TabPanels>
        <TabPanel value="queue">
          <ErrorBox :error="seriesError" />
          <template v-if="series">
            <p class="muted small" :title="selectedOrganization?.name">{{ selectedOrganization ? shortOrgName(selectedOrganization.name) : moCode }} · {{ t('gov.region.factHeader') }} <OriginTag kind="formula" /></p>
            <KpiRow>
              <KpiTile :value="series.days.at(-1)?.queueLen ?? '—'" :label="t('gov.region.queueNow')" />
              <KpiTile :value="days(series.throughput?.throughputPerDay, 1)" :label="t('gov.region.admissionsPerDay4w')" />
              <KpiTile :value="`${days(series.throughput?.waitP50Days)} / ${days(series.throughput?.waitP90Days)}`" :label="t('gov.region.factP50P90')" />
              <KpiTile :value="pct(series.throughput?.refusalRate4w)" :label="t('gov.region.refusals4w')" />
            </KpiRow>
            <div style="margin-top: 16px"><QueueChart :days="series.days" :title="t('gov.region.queueChartTitle')" /></div>
          </template>
          <p v-else class="muted">{{ t('gov.region.noQueueSeries') }}</p>
        </TabPanel>

        <TabPanel value="forecast">
          <div class="toolbar">
            <Select v-model="streamKind" :options="STREAMS" option-label="label" option-value="value" size="small" style="min-width: 220px" />
            <SearchSelect v-if="streamKind === 'vac'" v-model="vaccinationPlan" :options="planOptions" option-label="plan" option-value="plan" size="small" :placeholder="t('gov.region.vaccinationPlan')" class="w-org" />
          </div>
          <SeriesChart v-if="forecast" :history="forecast.history" :points="forecast.points" :title="forecastTitle" :unit="streamMeta.unit" />
          <p v-else-if="forecastHint" class="muted">{{ forecastHint }}</p>
          <p v-if="forecast" class="muted small">
            {{ t('gov.map.backtest') }}: sMAPE {{ pct(forecast.backtest.smape, 1) }} {{ t('gov.map.vsNaive') }} {{ pct(forecast.backtest.baselineSmape, 1) }}, MASE {{ forecast.backtest.mase.toFixed(2) }}.
            {{ forecast.model.name }} {{ forecast.model.version }}. <OriginTag kind="ml" />
            <span v-if="forecast.flat" class="synthetic" style="margin-left: 6px">{{ t('gov.region.flatForecastHint') }}</span>
          </p>
          <template v-if="streamKind === 'admissions'">
            <p v-if="flatSeasonHint" class="muted small">{{ t('gov.region.seasonHint') }}: {{ flatSeasonHint }} {{ t('gov.region.seasonHintSuffix') }}</p>
            <!-- коэффициент и источник: refdata/external_benchmarks.yaml (diagnostics.dm01_tests_per_admission) -->
            <p v-if="forecast && forecast.points.length" class="muted small">
              {{ t('gov.region.diagnosticsLoad') }}: ≈ {{ num(Math.round((forecast.points.reduce((s, p) => s + p.yhat, 0) / forecast.points.length) * 1.5)) }} {{ t('gov.region.diagnosticsLoadSuffix') }}
            </p>
            <div class="card bed-card">
              <h2>{{ t('gov.region.bedDemand.title') }}: {{ refdata.profileName(profile) }} <OriginTag kind="formula" :note="t('gov.region.bedDemand.formula')" /></h2>
              <div v-if="bedDemand.length" class="kpi">
                <div v-for="d in bedDemand" :key="d.period" class="item"><div class="value">{{ d.beds }}</div><div class="label">{{ d.label }} · {{ t('gov.region.bedDemand.unit') }}</div></div>
              </div>
              <p v-else-if="bedForecastHint" class="muted">{{ bedForecastHint }}</p>
              <p class="muted small">{{ t('gov.region.bedDemand.formula') }}</p>
            </div>
          </template>
        </TabPanel>

        <TabPanel value="signals">
          <AnomalyFeed :items="anomalies" :can-ack="auth.hasRole('chief', 'regulator')" @ack="(id, c) => resolve(id, c, 'acknowledged')" @dismiss="(id, c) => resolve(id, c, 'dismissed')" />
        </TabPanel>

        <TabPanel value="organizations">
          <p class="muted small">{{ t('gov.map.overloaded') }} <OriginTag kind="formula" /></p>
          <OverloadedTable :items="overloaded" @organization="toOrganization" @simulate="router.push({ name: 'simulator', query: { region: $event.regionKato, profile: $event.profileCode } })" />
        </TabPanel>
      </TabPanels>
    </Tabs>
  </PageShell>
</template>

<style scoped>
.w-profile { min-width: 240px; }
.w-org { min-width: 280px; max-width: 100%; }
.region-tabs :deep(.p-tabpanels) { padding: var(--dm-space-4) 0 0; background: transparent; }
.bed-card { margin-top: 16px; }
</style>
