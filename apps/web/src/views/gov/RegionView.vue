<script setup lang="ts">
import IconField from 'primevue/iconfield'
import InputIcon from 'primevue/inputicon'
import InputText from 'primevue/inputtext'
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
import OriginLegend from '@/components/OriginLegend.vue'
import OverloadedTable from '@/components/OverloadedTable.vue'
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

/** Регион (W-Region): подпись «индекс · место · профиль · данные на» и одна легенда происхождения, четыре KPI
 * (подпись над числом), очередь выбранной больницы за 90 дней рядом с сигналами региона, перегруженные больницы с
 * поиском и листанием, прогноз потока с потребностью в койках сбоку, ориентиры таблицей. Поток прогноза (3.1): у каждого свой второй ключ сущности и единица измерения. */
const STREAM_DEFS = [
  { value: 'admissions', streamId: 'admissions_monthly' },
  { value: 'er_visits', streamId: 'er_visits_daily' },
  { value: 'vac', streamId: 'vac_monthly' },
] as const
type StreamKind = (typeof STREAM_DEFS)[number]['value']
const TARGET_OCCUPANCY = 0.85
const ORG_ROWS = 5

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
const orgSearch = ref('')
const shownOverloaded = computed(() => {
  const q = orgSearch.value.trim().toLowerCase()
  return q ? overloaded.value.filter((o) => `${o.name} ${o.moCode} ${refdata.profileName(o.profileCode)}`.toLowerCase().includes(q)) : overloaded.value
})
/** Единица ориентира из справочника (en: days, weeks, percent) — словами на языке интерфейса. */
const unitText = (unit: string) => (/^(days?|дн|дн\.|дней)$/i.test(unit) ? t('common.days') : /^weeks?$/i.test(unit) ? t('gov.region.unitWeeks') : unit === 'percent' ? '%' : unit)
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
      <div class="page-legend"><OriginLegend /></div>
    </template>
    <template #actions>
      <SearchSelect v-model="profile" :options="refdata.profiles" option-label="name" option-value="profileCode" size="small" class="w-profile" :aria-label="t('common.profile')" />
    </template>
    <ErrorBox :error="error" />

    <KpiRow>
      <KpiTile label-first :value="days(regionPrediction?.p50Days)" :unit="t('common.days')" :label="t('gov.region.kpiP50Label')" :hint="target ? t('gov.region.kpiP50Hint', { target: days(target.value) }) : undefined" />
      <KpiTile label-first :value="days(regionPrediction?.p90Days)" :unit="t('common.days')" :label="t('gov.region.kpiP90Label')" :hint="t('gov.region.kpiP90Hint')" />
      <KpiTile label-first :value="pct(regionPrediction?.pWithin30Days)" :label="t('gov.region.kpiWithin30Label')" :hint="t('gov.region.kpiWithin30Hint')" />
      <KpiTile label-first :value="num(queueTotal)" :label="t('gov.region.kpiQueueLabel')" :hint="t('gov.region.kpiQueueHint', { n: overloaded.length })" />
    </KpiRow>

    <div class="main-grid">
      <AppCard :title="t('gov.region.queueTitle')">
        <template #header>
          <SearchSelect v-model="moCode" :options="organizations" :option-label="orgLabel" option-value="moCode" :option-title="orgTitle" size="small" :placeholder="t('common.organization')" class="w-org" :aria-label="t('common.organization')" />
        </template>
        <p class="caption card-lead">{{ t('gov.region.queueLead') }}</p>
        <ErrorBox :error="seriesError" />
        <template v-if="series">
          <dl class="facts">
            <div><dt>{{ t('gov.region.factQueue') }}</dt><dd class="tabular">{{ series.days.at(-1)?.queueLen ?? '—' }}</dd></div>
            <div><dt>{{ t('gov.region.factPerWeek') }}</dt><dd class="tabular">{{ series.throughput?.throughputPerDay != null ? num(Math.round(series.throughput.throughputPerDay * 7)) : '—' }}</dd><span class="fact-sub">{{ t('gov.region.factPerWeekSub') }}</span></div>
            <div><dt>{{ t('gov.region.factWaitP90') }}</dt><dd class="tabular">{{ days(series.throughput?.waitP90Days) }} {{ t('common.days') }}</dd><span class="fact-sub">{{ t('gov.region.factWaitP50', { p50: days(series.throughput?.waitP50Days) }) }}</span></div>
            <div><dt>{{ t('gov.region.factRefusals') }}</dt><dd class="tabular">{{ pct(series.throughput?.refusalRate4w) }}</dd><span class="fact-sub">{{ t('gov.region.factRefusalsSub') }}</span></div>
          </dl>
          <QueueChart :days="series.days" bare />
        </template>
        <p v-else class="muted">{{ t('gov.region.noQueueSeries') }}</p>
        <div class="links">
          <RouterLink v-if="moCode" class="link-arrow small" :to="{ name: 'organization', params: { moCode }, query: { kato, profile } }">{{ t('gov.region.toOrganization') }}</RouterLink>
          <RouterLink v-if="auth.can('gov.simulator')" class="link-arrow small" :to="{ name: 'simulator', query: { region: kato, profile } }">{{ t('gov.region.toSimulator') }}</RouterLink>
        </div>
      </AppCard>

      <div class="side-slot">
        <AppCard :title="t('gov.region.signals')" origin="ml" class="side-card">
          <template #header><span class="caption">{{ t('gov.region.signalsCount', { n: anomalies.length }) }}</span></template>
          <p class="caption card-lead">{{ t('gov.region.signalsLead') }}</p>
          <div class="side-scroll">
            <AnomalyFeed :items="anomalies" compact="region" :can-ack="auth.canAny(['gov.map', 'org.cabinet'])" @ack="(id, c) => resolve(id, c, 'acknowledged')" @dismiss="(id, c) => resolve(id, c, 'dismissed')" />
          </div>
        </AppCard>
      </div>
    </div>

    <AppCard :title="t('gov.region.orgsTitle')" class="block">
      <p class="caption card-lead">{{ t('gov.region.orgsLead') }}</p>
      <div class="toolbar list-toolbar">
        <span class="list-count">{{ t('gov.region.orgsShown', { n: shownOverloaded.length }) }}</span>
        <span class="spacer" />
        <IconField class="search-field">
          <InputIcon class="pi pi-search" />
          <InputText v-model="orgSearch" :placeholder="t('gov.region.orgsSearch')" :aria-label="t('gov.region.orgsSearch')" />
        </IconField>
      </div>
      <OverloadedTable :items="shownOverloaded" :size="ORG_ROWS" @organization="toOrganization" @simulate="router.push({ name: 'simulator', query: { region: kato, profile: $event.profileCode } })" />
    </AppCard>

    <AppCard :title="t('gov.region.forecastTitle')" origin="ml" class="block">
      <template #header>
        <Select v-model="streamKind" :options="STREAMS" option-label="label" option-value="value" size="small" class="f-select" :aria-label="t('gov.region.forecastWhat')" />
        <SearchSelect v-if="streamKind === 'vac'" v-model="vaccinationPlan" :options="planOptions" option-label="plan" option-value="plan" size="small" :placeholder="t('gov.region.vaccinationPlan')" class="w-org" />
      </template>
      <p class="caption card-lead">{{ t(`gov.region.forecastLead.${streamKind}`) }}</p>
      <div class="forecast-grid" :class="{ single: streamKind !== 'admissions' }">
        <div class="forecast-main">
          <SeriesChart v-if="forecast" :history="forecast.history" :points="forecast.points" :title="forecastTitle" :unit="streamMeta.unit" bare />
          <p v-else-if="forecastHint" class="muted">{{ forecastHint }}</p>
          <p v-if="forecast" class="caption">
            {{ t('gov.region.accuracy', { model: pct(forecast.backtest.smape, 0), naive: pct(forecast.backtest.baselineSmape, 0) }) }}
            <template v-if="forecast.flat"> {{ t('gov.region.flatPlain') }}</template>
          </p>
          <p v-if="streamKind === 'admissions' && flatSeasonHint" class="caption">{{ t('gov.region.seasonPlain', { months: flatSeasonHint }) }}</p>
        </div>
        <aside v-if="streamKind === 'admissions'" class="forecast-side">
          <div class="side-block">
            <div class="side-title">{{ t('gov.region.bedDemand.title') }}</div>
            <div v-if="bedDemand.length" class="bed-row tabular">
              <div v-for="d in bedDemand" :key="d.period" class="bed"><span class="caption">{{ d.label }}</span><span class="bed-value">{{ d.beds }}</span><span class="caption">{{ t('gov.region.bedDemand.unit') }}</span></div>
            </div>
            <p v-else-if="bedForecastHint" class="muted small">{{ bedForecastHint }}</p>
            <p class="caption">{{ t('gov.region.bedDemand.plain') }}</p>
          </div>
          <div v-if="forecast && forecast.points.length" class="side-block">
            <div class="side-title">{{ t('gov.region.diagnosticsTitle') }}</div>
            <div class="bed-value tabular">≈ {{ num(Math.round((forecast.points.reduce((s, p) => s + p.yhat, 0) / forecast.points.length) * 1.5)) }}</div>
            <p class="caption">{{ t('gov.region.diagnosticsPlain') }}</p>
          </div>
        </aside>
      </div>
    </AppCard>

    <AppCard :title="t('gov.region.benchmarksTitle')" class="block">
      <p class="caption card-lead">{{ t('gov.region.benchmarksLead') }}</p>
      <div class="table-wrap">
        <table class="dense-table">
          <thead><tr><th>{{ t('gov.region.colBenchmark') }}</th><th>{{ t('gov.region.colSource') }}</th><th class="num">{{ t('gov.region.colValue') }}</th></tr></thead>
          <tbody>
            <tr v-if="regionPrediction" class="own-row"><td>{{ t('gov.region.ownRow', { region: refdata.regionName(kato), profile: refdata.profileName(profile).toLowerCase() }) }}</td><td class="muted">{{ t('gov.region.ownSource') }}</td><td class="num">{{ days(regionPrediction.p50Days) }} {{ t('common.days') }}</td></tr>
            <tr v-for="b in benchmarks" :key="b.code"><td>{{ b.title }}</td><td class="muted">{{ b.source }} · {{ dateShort(b.sourceDate) }}</td><td class="num">{{ b.unit === 'share' ? pct(b.value) : `${days(b.value)} ${unitText(b.unit)}` }}</td></tr>
          </tbody>
        </table>
      </div>
    </AppCard>
  </PageShell>
</template>

<style scoped>
.w-profile { min-width: 240px; }
.w-org { min-width: 260px; max-width: 100%; }
.f-select { min-width: 200px; }
.page-legend { display: flex; margin-top: 8px; }
.card-lead { margin: -4px 0 14px; line-height: 1.5; }
.block { margin-top: var(--dm-space-4); }
.main-grid { display: grid; grid-template-columns: minmax(0, 1.6fr) minmax(0, 1fr); gap: var(--dm-space-4); align-items: stretch; }
.facts { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); margin: 0 0 16px; border-top: 1px solid var(--dm-hairline); border-bottom: 1px solid var(--dm-hairline); }
.facts div { padding: 12px 16px; display: flex; flex-direction: column; gap: 4px; }
.facts div + div { border-left: 1px solid var(--dm-hairline); }
.facts div:first-child { padding-left: 0; }
.facts dt { font-size: var(--dm-text-sm); color: var(--text-secondary); line-height: 1.3; }
.facts dd { margin: 0; font-size: var(--dm-text-xl); font-weight: var(--fw-bold); }
.fact-sub { font-size: var(--dm-text-sm); color: var(--text-secondary); line-height: 1.35; }
.side-slot { position: relative; min-height: 420px; }
.side-card { position: absolute; inset: 0; display: flex; flex-direction: column; }
.side-scroll { flex: 1; min-height: 0; overflow-y: auto; padding-right: 6px; }
.links { display: flex; gap: 20px; margin-top: 12px; flex-wrap: wrap; }
.list-toolbar { margin-bottom: 12px; row-gap: 8px; }
.list-count { color: var(--text-secondary); }
.spacer { flex: 1; }
.search-field { flex: 0 1 340px; min-width: 240px; }
.search-field :deep(.p-inputtext) { width: 100%; }
.forecast-grid { display: grid; grid-template-columns: minmax(0, 1fr) 300px; gap: var(--dm-space-4); align-items: start; }
.forecast-grid.single { grid-template-columns: minmax(0, 1fr); }
.forecast-side { display: flex; flex-direction: column; gap: 12px; }
.side-block { background: var(--surface-muted); border-radius: 12px; padding: 14px 16px; display: flex; flex-direction: column; gap: 8px; }
.side-block p { margin: 0; line-height: 1.45; }
.side-title { font-weight: var(--fw-bold); }
.bed-row { display: flex; gap: 20px; flex-wrap: wrap; }
.bed { display: flex; flex-direction: column; gap: 2px; }
.bed-value { font-size: var(--dm-text-xl); font-weight: var(--fw-extrabold); letter-spacing: -0.01em; }
.own-row td { font-weight: var(--fw-bold); }
@media (max-width: 1000px) {
  .main-grid, .forecast-grid { grid-template-columns: 1fr; }
  .facts { grid-template-columns: repeat(2, minmax(0, 1fr)); }
  .facts div + div { border-left: 0; }
  .facts div { padding-left: 0; }
  .side-slot { min-height: 0; }
  .side-card { position: static; }
  .side-scroll { max-height: 480px; }
}
</style>
