<script setup lang="ts">
import Select from 'primevue/select'
import { useToast } from 'primevue/usetoast'
import { computed, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute, useRouter } from 'vue-router'
import { ApiError } from '@/api/client'
import { analytics, queue, refdata as refdataApi } from '@/api/endpoints'
import type { Anomaly, ForecastResponse, IndexItem, OrganizationItem, OrganizationSeries, OverloadedOrganization, PredictResponse, RouteBenchmark, Seasonality } from '@/api/types'
import AnomalyFeed from '@/components/AnomalyFeed.vue'
import ErrorBox from '@/components/ErrorBox.vue'
import OriginTag from '@/components/OriginTag.vue'
import QueueChart from '@/components/QueueChart.vue'
import SeriesChart from '@/components/SeriesChart.vue'
import AppCard from '@/components/ui/AppCard.vue'
import KpiRow from '@/components/ui/KpiRow.vue'
import KpiTile from '@/components/ui/KpiTile.vue'
import PageShell from '@/components/ui/PageShell.vue'
import SearchSelect from '@/components/ui/SearchSelect.vue'
import { useLocaleFormat } from '@/composables/useLocaleFormat'
import { days, pct, shortOrgName } from '@/lib/format'
import { dateShort } from '@/lib/route'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'

/** Регион (W-Region): подпись «индекс · место · профиль · данные на», четыре KPI (p50 и p90 по региону, за 30 дней,
 * в листе ожидания), слева очередь выбранной организации за 90 дней и прогноз потока, справа организации региона,
 * ориентиры и сигналы. Поток прогноза (3.1): у каждого свой второй ключ сущности и единица измерения. */
const STREAM_DEFS = [
  { value: 'admissions', streamId: 'admissions_monthly' },
  { value: 'er_visits', streamId: 'er_visits_daily' },
  { value: 'vac', streamId: 'vac_monthly' },
] as const
type StreamKind = (typeof STREAM_DEFS)[number]['value']
const TARGET_OCCUPANCY = 0.85
const ORG_ROWS = 6

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
const regionPrediction = ref<PredictResponse | null>(null)
const indexItem = ref<IndexItem | null>(null)
const indexTotal = ref(0)
const benchmarks = ref<RouteBenchmark[]>([])
const error = ref<unknown>(null)
const seriesError = ref<unknown>(null)

const STREAMS = computed(() => STREAM_DEFS.map((s) => ({ ...s, label: t(`gov.region.stream.${s.value}`), unit: t(`gov.region.streamUnit.${s.value}`) })))
const streamMeta = computed(() => STREAMS.value.find((s) => s.value === streamKind.value)!)
const selectedOrganization = computed(() => organizations.value.find((o) => o.moCode === moCode.value) ?? null)
const asOf = computed(() => series.value?.days.at(-1)?.day ?? regionPrediction.value?.model.trainedThrough ?? '')
const planOptions = computed(() => vaccinationPlans.value.map((plan) => ({ plan })))
const orgLabel = (o: OrganizationItem) => shortOrgName(o.name)
const orgTitle = (o: OrganizationItem) => o.name
const queueTotal = computed(() => overloaded.value.reduce((s, o) => s + o.queueLen, 0))
const target = computed(() => benchmarks.value.find((b) => b.code === 'moh_target_wait_days') ?? null)

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
    const [anomaliesPage, ov, prediction, index] = await Promise.all([
      analytics.anomalies({ regionKato: kato.value, status: 'open', size: 10 }),
      queue.overloaded(kato.value),
      queue.predict({ regionKato: kato.value, profileCode: profile.value }).catch(() => null),
      analytics.index(undefined, profile.value).catch(() => null),
    ])
    anomalies.value = anomaliesPage.items
    overloaded.value = ov.items
    regionPrediction.value = prediction
    indexItem.value = index?.items.find((i) => i.regionKato === kato.value) ?? null
    indexTotal.value = index?.items.length ?? 0
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
    const [season, standard] = await Promise.all([refdataApi.seasonality(), refdataApi.routeStandard()])
    seasonality.value = season.items
    benchmarks.value = standard.benchmarks
  } catch {
    seasonality.value = [] // подсказка сезонности и ориентиры опциональны
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
  <PageShell :title="refdata.regionName(kato)" :back="{ to: { name: 'gov' }, label: t('nav.gov') }">
    <template #subtitle>
      <template v-if="indexItem">{{ t('gov.region.subtitleIndex', { value: indexItem.indexValue.toFixed(0), rank: indexItem.rank, total: indexTotal }) }} · </template>{{ refdata.profileName(profile) }}<template v-if="asOf"> · {{ t('shell.asOf', { date: dateShort(asOf) }) }}</template>
    </template>
    <template #actions>
      <SearchSelect v-model="profile" :options="refdata.profiles" option-label="name" option-value="profileCode" size="small" class="w-profile" />
    </template>
    <ErrorBox :error="error" />

    <KpiRow>
      <KpiTile :value="days(regionPrediction?.p50Days)" :unit="t('common.days')" :label="target ? t('gov.region.kpiP50', { target: days(target.value) }) : t('hero.halfMedian')" origin="ml" />
      <KpiTile :value="days(regionPrediction?.p90Days)" :unit="t('common.days')" :label="t('gov.region.kpiP90')" origin="ml" />
      <KpiTile :value="pct(regionPrediction?.pWithin30Days)" :label="t('gov.org.within30')" origin="ml" />
      <KpiTile :value="num(queueTotal)" :label="t('gov.region.kpiQueue')" origin="formula" :hint="`${overloaded.length} ${t('gov.simulator.organisations')}`" />
    </KpiRow>

    <div class="main-grid">
      <div class="col">
        <AppCard :title="t('gov.region.queueTitle')" origin="formula">
          <template #header>
            <SearchSelect v-model="moCode" :options="organizations" :option-label="orgLabel" option-value="moCode" :option-title="orgTitle" size="small" :placeholder="t('common.organization')" class="w-org" />
          </template>
          <ErrorBox :error="seriesError" />
          <template v-if="series">
            <div class="facts-line caption">
              {{ t('gov.region.factHeader') }} · {{ t('gov.region.queueNow') }} <b class="ink">{{ series.days.at(-1)?.queueLen ?? '—' }}</b> · {{ t('gov.region.admissionsPerDay4w') }} <b class="ink">{{ days(series.throughput?.throughputPerDay, 1) }}</b> ·
              p50 / p90 <b class="ink">{{ days(series.throughput?.waitP50Days) }} / {{ days(series.throughput?.waitP90Days) }}</b> · {{ t('gov.region.refusals4w') }} <b class="ink">{{ pct(series.throughput?.refusalRate4w) }}</b>
            </div>
            <QueueChart :days="series.days" bare />
          </template>
          <p v-else class="muted">{{ t('gov.region.noQueueSeries') }}</p>
          <div class="links">
            <RouterLink v-if="moCode" class="link-arrow small" :to="{ name: 'organization', params: { moCode }, query: { kato, profile } }">{{ t('gov.region.toOrganization') }}</RouterLink>
            <RouterLink v-if="auth.hasRole('regulator')" class="link-arrow small" :to="{ name: 'simulator', query: { region: kato, profile } }">{{ t('nav.simulator') }}</RouterLink>
          </div>
        </AppCard>

        <AppCard :title="t('gov.region.tabForecast')" origin="ml">
          <template #header>
            <Select v-model="streamKind" :options="STREAMS" option-label="label" option-value="value" size="small" />
            <SearchSelect v-if="streamKind === 'vac'" v-model="vaccinationPlan" :options="planOptions" option-label="plan" option-value="plan" size="small" :placeholder="t('gov.region.vaccinationPlan')" class="w-org" />
          </template>
          <SeriesChart v-if="forecast" :history="forecast.history" :points="forecast.points" :title="forecastTitle" :unit="streamMeta.unit" bare />
          <p v-else-if="forecastHint" class="muted">{{ forecastHint }}</p>
          <p v-if="forecast" class="caption">
            {{ t('gov.map.backtest') }}: sMAPE {{ pct(forecast.backtest.smape, 1) }} {{ t('gov.map.vsNaive') }} {{ pct(forecast.backtest.baselineSmape, 1) }}, MASE {{ forecast.backtest.mase.toFixed(2) }}. {{ forecast.model.name }} {{ forecast.model.version }}.
            <span v-if="forecast.flat" class="synthetic" style="margin-left: 6px">{{ t('gov.region.flatForecastHint') }}</span>
          </p>
          <template v-if="streamKind === 'admissions'">
            <p v-if="flatSeasonHint" class="caption">{{ t('gov.region.seasonHint') }}: {{ flatSeasonHint }} {{ t('gov.region.seasonHintSuffix') }}</p>
            <!-- коэффициент и источник: refdata/external_benchmarks.yaml (diagnostics.dm01_tests_per_admission) -->
            <p v-if="forecast && forecast.points.length" class="caption">
              {{ t('gov.region.diagnosticsLoad') }}: ≈ {{ num(Math.round((forecast.points.reduce((s, p) => s + p.yhat, 0) / forecast.points.length) * 1.5)) }} {{ t('gov.region.diagnosticsLoadSuffix') }}
            </p>
            <div class="bed-block">
              <div class="bed-head"><span class="eyebrow">{{ t('gov.region.bedDemand.title') }}</span><OriginTag kind="formula" :note="t('gov.region.bedDemand.formula')" /></div>
              <div v-if="bedDemand.length" class="bed-row tabular">
                <span v-for="d in bedDemand" :key="d.period" class="bed"><span class="bed-value">{{ d.beds }}</span><span class="caption">{{ d.label }} · {{ t('gov.region.bedDemand.unit') }}</span></span>
              </div>
              <p v-else-if="bedForecastHint" class="muted small">{{ bedForecastHint }}</p>
              <p class="caption">{{ t('gov.region.bedDemand.formula') }}</p>
            </div>
          </template>
        </AppCard>
      </div>

      <div class="col">
        <AppCard :title="t('gov.region.orgsTitle')" origin="formula">
          <template #header><span class="caption">{{ refdata.profileName(profile) }}</span></template>
          <p v-if="!overloaded.length" class="muted">{{ t('overloadedTable.none') }}</p>
          <table v-else class="dense-table">
            <thead><tr><th>{{ t('common.organization') }}</th><th class="num">{{ t('overloadedTable.queue') }}</th><th class="num">p90</th><th class="num">{{ t('overloadedTable.refusals') }}</th></tr></thead>
            <tbody>
              <tr v-for="o in overloaded.slice(0, ORG_ROWS)" :key="o.moCode + o.profileCode" class="clickable" @click="toOrganization(o.moCode)">
                <td class="clip" :title="o.name">{{ shortOrgName(o.name) }} <span class="muted">· {{ o.moCode }}</span><div class="caption">{{ refdata.profileName(o.profileCode) }}</div></td>
                <td class="num">{{ o.queueLen }}</td>
                <td class="num" :class="{ 'delta-up': (o.queueAgeP90 ?? 0) > 60 }">{{ o.queueAgeP90?.toFixed(0) ?? '—' }}</td>
                <td class="num">{{ pct(o.refusalRate4w) }}</td>
              </tr>
            </tbody>
          </table>
        </AppCard>

        <AppCard :title="t('gov.region.benchmarksTitle')" origin="formula">
          <div class="rows">
            <div v-for="b in benchmarks" :key="b.code" class="row"><span class="row-main">{{ b.title }}<div class="caption">{{ b.source }} · {{ dateShort(b.sourceDate) }}</div></span><span class="row-value strong">{{ days(b.value) }} {{ b.unit }}</span></div>
            <div v-if="regionPrediction" class="row"><span class="row-main">{{ refdata.regionName(kato) }}, {{ refdata.profileName(profile).toLowerCase() }} p50</span><span class="row-value strong">{{ days(regionPrediction.p50Days) }} {{ t('common.days') }}</span></div>
          </div>
          <p class="caption" style="margin: 12px 0 0">{{ t('gov.region.benchmarksNote') }}</p>
        </AppCard>

        <AppCard :title="t('gov.region.signals')" origin="ml">
          <template #header><span class="caption">{{ anomalies.length }}</span></template>
          <AnomalyFeed :items="anomalies" :can-ack="auth.hasRole('chief', 'regulator')" @ack="(id, c) => resolve(id, c, 'acknowledged')" @dismiss="(id, c) => resolve(id, c, 'dismissed')" />
        </AppCard>
      </div>
    </div>
  </PageShell>
</template>

<style scoped>
.w-profile { min-width: 240px; }
.w-org { min-width: 240px; max-width: 100%; }
.main-grid { display: grid; grid-template-columns: minmax(0, 1.4fr) minmax(0, 1fr); gap: var(--dm-space-4); align-items: start; }
.col { display: flex; flex-direction: column; gap: var(--dm-space-4); min-width: 0; }
.facts-line { margin-bottom: 8px; }
.facts-line .ink { color: var(--dm-ink); font-weight: 500; }
.links { display: flex; gap: 20px; margin-top: 12px; flex-wrap: wrap; }
.bed-block { border-top: 1px solid var(--dm-hairline); margin-top: 12px; padding-top: 12px; display: flex; flex-direction: column; gap: 8px; }
.bed-head { display: flex; align-items: center; gap: 10px; }
.bed-row { display: flex; gap: 24px; flex-wrap: wrap; }
.bed { display: flex; flex-direction: column; gap: 2px; }
.bed-value { font-size: var(--dm-text-xl); font-weight: 500; letter-spacing: -0.01em; }
.clip { max-width: 280px; }
.strong { font-weight: 500; }
@media (max-width: 1000px) { .main-grid { grid-template-columns: 1fr; } }
</style>
