<script setup lang="ts">
import SelectButton from 'primevue/selectbutton'
import { useToast } from 'primevue/usetoast'
import { computed, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute } from 'vue-router'
import { ApiError } from '@/api/client'
import { admin, analytics, queue, refdata as refdataApi } from '@/api/endpoints'
import type { AdminDoctor, Anomaly, EquipmentOrganization, OrganizationItem, OrganizationSeries, PredictResponse } from '@/api/types'
import AnomalyFeed from '@/components/AnomalyFeed.vue'
import ErrorBox from '@/components/ErrorBox.vue'
import OriginLegend from '@/components/OriginLegend.vue'
import QueueChart from '@/components/QueueChart.vue'
import AppCard from '@/components/ui/AppCard.vue'
import ArrowPager from '@/components/ui/ArrowPager.vue'
import KpiRow from '@/components/ui/KpiRow.vue'
import KpiTile from '@/components/ui/KpiTile.vue'
import PageShell from '@/components/ui/PageShell.vue'
import SearchSelect from '@/components/ui/SearchSelect.vue'
import StatusTag from '@/components/ui/StatusTag.vue'
import { days, pct, shortOrgName } from '@/lib/format'
import { dateShort } from '@/lib/route'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'

/** Больница · обзор (W-Organization): H1 короткое имя · код, подпись «регион · профиль · данные на», четыре KPI
 * (в листе ожидания, p50 с подписью региона, отказы за 4 недели, госпитализаций в день), слева очередь за 90 дней
 * и ссылки «Направления и отказы» / «Симулятор», справа сигналы и «Сравнение с регионом» (факт организации за 4 недели
 * против прогноза модели по региону). */
const { t } = useI18n()
const route = useRoute()
const refdata = useRefdataStore()
const auth = useAuthStore()
const toast = useToast()

const moCode = computed(() => String(route.params.moCode))
/** Регион больницы: из ссылки, иначе из справочника организаций (страница открыта, например, из «Организаций»),
 * и только потом — регион пользователя. */
const foundKato = ref('')
const kato = computed(() => String(route.query.kato ?? '') || foundKato.value || auth.region || '')
async function resolveKato() {
  if (route.query.kato) return
  const found = await refdataApi.organizations(undefined, moCode.value, undefined, 5).catch(() => null)
  foundKato.value = found?.items.find((o) => o.moCode === moCode.value)?.regionKato ?? ''
}
const profile = ref<string>(String(route.query.profile ?? ''))
const organizations = ref<OrganizationItem[]>([])
const series = ref<OrganizationSeries | null>(null)
const regionPrediction = ref<PredictResponse | null>(null)
const anomalies = ref<Anomaly[]>([])
const equipment = ref<EquipmentOrganization | null>(null)
const error = ref<unknown>(null)

const fullName = computed(() => organizations.value.find((o) => o.moCode === moCode.value)?.name ?? refdata.organizationName(moCode.value))
const asOf = computed(() => series.value?.days.at(-1)?.day ?? '')
const queueNow = computed(() => series.value?.days.at(-1)?.queueLen ?? null)
/** Очередь две недели назад — для подписи «выше/ниже, чем две недели назад». */
const queueDelta = computed(() => {
  const d = series.value?.days
  if (!d || d.length < 15) return null
  const before = d[d.length - 15]!.queueLen
  return before ? ((d.at(-1)!.queueLen - before) / before) * 100 : null
})

/** «за 2 недели стало больше на 1 %» — словами, без знаков. */
const queueHint = computed(() => {
  if (queueDelta.value === null) return undefined
  const d = Math.round(Math.abs(queueDelta.value))
  return d === 0 ? t('gov.org.queueSame') : t(queueDelta.value > 0 ? 'gov.org.queueUp' : 'gov.org.queueDown', { d })
})

interface Pair { key: string; org: number | null | undefined; region: number | null | undefined; format: (v: number | null | undefined) => string; delta: (o: number, r: number) => string }
/** Парные показатели: факт организации против прогноза региона; дельта в днях или процентных пунктах. */
const pairs = computed<Pair[]>(() => {
  const th = series.value?.throughput
  const rp = regionPrediction.value
  // разница словами: «на 19 дн. меньше» / «на 1 % больше» — без знаков и процентных пунктов
  const say = (diff: number, unit: string) => (Math.round(Math.abs(diff)) === 0 ? t('gov.org.diffSame') : t(diff < 0 ? 'gov.org.diffLess' : 'gov.org.diffMore', { n: Math.round(Math.abs(diff)), unit }))
  const dDays = (o: number, r: number) => say(o - r, t('common.days'))
  const dPoints = (o: number, r: number) => say((o - r) * 100, '%')
  return [
    { key: 'p50', org: th?.waitP50Days, region: rp?.p50Days, format: (v) => days(v), delta: dDays },
    { key: 'p90', org: th?.waitP90Days, region: rp?.p90Days, format: (v) => days(v), delta: dDays },
    { key: 'refusal', org: th?.refusalRate4w, region: rp?.pRefusal, format: (v) => pct(v), delta: dPoints },
  ]
})
const worse = computed(() => (series.value?.throughput?.waitP50Days ?? 0) > (regionPrediction.value?.p50Days ?? Infinity))

/** Нагрузка врачей больницы: направления каждого врача за 90 дней — таблицей с оценкой словами относительно среднего
 * по больнице (цветом — только «выше обычного» и «очень высокая»), сортировка и листание по 8 строк. */
const LOAD_PAGE = 5
const LOAD_TONES = { veryHigh: 'danger', high: 'warn', normal: 'ok', low: 'neutral' } as const
const doctors = ref<AdminDoctor[]>([])
const loadSort = ref<'more' | 'less' | 'name'>('more')
const loadPage = ref(0)
const loadSortOptions = computed(() => (['more', 'less', 'name'] as const).map((v) => ({ value: v, label: t('gov.org.loadSort.' + v) })))
const withLoad = computed(() => doctors.value.filter((d) => d.referrals !== null))
const doctorsAvg = computed(() => (withLoad.value.length ? withLoad.value.reduce((a, d) => a + (d.referrals ?? 0), 0) / withLoad.value.length : 0))
function loadLevel(n: number): 'veryHigh' | 'high' | 'normal' | 'low' {
  if (withLoad.value.length < 2 || doctorsAvg.value === 0) return 'normal'
  const k = n / doctorsAvg.value
  return k >= 1.75 ? 'veryHigh' : k >= 1.25 ? 'high' : k <= 0.5 ? 'low' : 'normal'
}
const loadRows = computed(() => [...withLoad.value].sort((a, b) =>
  loadSort.value === 'name' ? (a.displayName ?? '').localeCompare(b.displayName ?? '', 'ru')
    : loadSort.value === 'less' ? (a.referrals ?? 0) - (b.referrals ?? 0) : (b.referrals ?? 0) - (a.referrals ?? 0)))
const loadPageRows = computed(() => loadRows.value.slice(loadPage.value * LOAD_PAGE, (loadPage.value + 1) * LOAD_PAGE))
const overloaded = computed(() => withLoad.value.filter((d) => loadLevel(d.referrals ?? 0) === 'veryHigh').map((d) => d.displayName ?? '—'))
watch(loadSort, () => (loadPage.value = 0))
async function loadDoctors() {
  if (!auth.can('admin.users')) return
  try {
    doctors.value = (await admin.doctors({ moCode: moCode.value, page: 1, size: 100 })).items
  } catch {
    doctors.value = [] // нагрузка — дополнительный блок, страница работает и без него
  }
}

async function load() {
  error.value = null
  series.value = null
  regionPrediction.value = null
  try {
    await resolveKato()
    organizations.value = kato.value ? await refdata.organizationsOf(kato.value, undefined) : []
    if (!organizations.value.some((o) => o.moCode === moCode.value)) await refdata.resolveOrganizations([moCode.value]).catch(() => undefined)
    try {
      series.value = await queue.organization(moCode.value, profile.value, 90)
    } catch (e) {
      if (!(e instanceof ApiError && e.status === 404)) throw e
    }
    if (kato.value) regionPrediction.value = await queue.predict({ regionKato: kato.value, profileCode: profile.value })
    anomalies.value = (await analytics.anomalies({ regionKato: kato.value || undefined, moCode: moCode.value, status: 'open', size: 50 })).items
  } catch (e) {
    error.value = e
  }
  try {
    equipment.value = await analytics.equipmentForOrganization(moCode.value)
  } catch {
    equipment.value = null
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

/** Профиль по умолчанию: первый по числу направлений в стране, по которому организация есть в очередях своего
 * региона (главврач без ?profile= сразу видит данные, а не прочерки); если ни один из первых восьми не подошёл —
 * самый частый профиль, как раньше. */
async function profileWithData(): Promise<string> {
  if (!kato.value) return refdata.topProfileCode()
  const candidates = [...refdata.profiles].sort((a, b) => b.referrals - a.referrals).slice(0, 8)
  for (const candidate of candidates) {
    const orgs = await refdata.organizationsOf(kato.value, candidate.profileCode).catch(() => [] as OrganizationItem[])
    if (orgs.some((o) => o.moCode === moCode.value)) return candidate.profileCode
  }
  return refdata.topProfileCode()
}

onMounted(async () => {
  await refdata.load()
  if (!profile.value) {
    silentProfile = true
    profile.value = await profileWithData()
  }
  loadDoctors()
  await load()
})
watch(moCode, loadDoctors)
let silentProfile = false
watch([moCode, profile], () => {
  if (silentProfile) {
    silentProfile = false
    return
  }
  load()
})
</script>

<template>
  <PageShell :title="shortOrgName(fullName)" :back="kato && auth.can('gov.map') ? { to: `/gov/regions/${kato}`, label: refdata.regionName(kato) } : undefined">
    <template #subtitle>
      <span class="sub-line"><span v-if="kato" :title="fullName">{{ refdata.regionName(kato) }}</span><span>{{ t('gov.org.codeLabel', { code: moCode }) }}</span><span>{{ refdata.profileName(profile) }}</span><span v-if="asOf">{{ t('shell.asOf', { date: dateShort(asOf) }) }}</span></span>
      <div class="page-legend"><OriginLegend /></div>
    </template>
    <template #actions>
      <RouterLink v-if="auth.can('gov.simulator')" class="p-button p-button-secondary p-button-sm action-link" :to="{ name: 'simulator', query: { region: kato, profile } }"><i class="pi pi-chart-line" aria-hidden="true" />{{ t('gov.org.toSimulatorShort') }}</RouterLink>
      <SearchSelect v-model="profile" :options="refdata.profiles" option-label="name" option-value="profileCode" size="small" class="w-profile" />
    </template>
    <ErrorBox :error="error" />

    <KpiRow data-testid="org-kpis">
      <KpiTile label-first :value="queueNow ?? '—'" :label="t('gov.org.kpiQueueLabel')" :hint="queueHint" />
      <KpiTile label-first :value="days(series?.throughput?.waitP50Days)" :unit="t('common.days')" :label="t('gov.org.kpiWaitLabel')" :hint="regionPrediction ? t('gov.org.regionHint', { p50: days(regionPrediction.p50Days), p90: days(series?.throughput?.waitP90Days) }) : undefined" />
      <KpiTile label-first :value="pct(series?.throughput?.refusalRate4w)" :label="t('gov.org.kpiRefusalLabel')" :hint="t('gov.org.kpiRefusalHint')" :tone="series?.throughput?.refusalRate4w != null && regionPrediction && series.throughput.refusalRate4w > regionPrediction.pRefusal ? 'danger' : undefined" />
      <KpiTile label-first :value="days(series?.throughput?.throughputPerDay, 0)" :label="t('gov.org.kpiAdmissionsLabel')" :hint="series?.throughput?.throughputPerDay != null ? t('gov.org.kpiAdmissionsHint', { week: days(series.throughput.throughputPerDay * 7, 0) }) : undefined" />
    </KpiRow>

    <div class="main-grid">
      <div class="col">
        <AppCard :title="t('gov.org.queueChart90')">
          <template #header><span v-if="series" class="caption">{{ dateShort(series.days[0]!.day) }} — {{ dateShort(series.days.at(-1)!.day) }}</span></template>
          <p class="caption chart-note">{{ t('gov.org.queueChartNote') }}</p>
          <QueueChart v-if="series" :days="series.days" bare :height="400" />
          <p v-else class="muted">{{ t('gov.org.noQueueSeries') }}</p>
        </AppCard>

        <AppCard :title="t('gov.org.vsRegion')" origin="ml" :origin-note="t('gov.org.vsRegionNote')" data-testid="org-vs-region">
          <p class="caption chart-note">{{ t('gov.org.vsRegionLead') }}</p>
          <p v-if="!series" class="muted">{{ t('gov.org.noQueueSeries') }}</p>
          <table v-else-if="regionPrediction" class="dense-table">
            <thead><tr><th>{{ t('gov.org.colIndicator') }}</th><th class="num">{{ t('gov.org.colOurs') }}</th><th class="num">{{ t('gov.org.colRegion') }}</th><th class="num">{{ t('gov.org.colDiff') }}</th></tr></thead>
            <tbody>
              <tr v-for="p in pairs" :key="p.key">
                <td>{{ t('gov.org.pair.' + p.key) }}</td>
                <td class="num strong">{{ p.format(p.org) }}</td>
                <td class="num">{{ p.format(p.region) }}</td>
                <td class="num" :class="p.org != null && p.region != null ? (p.org > p.region ? 'delta-up' : 'delta-down') : ''">{{ p.org != null && p.region != null ? p.delta(p.org, p.region) : '—' }}</td>
              </tr>
            </tbody>
          </table>
          <p v-else class="muted">{{ t('gov.org.regionForecastUnavailable') }}</p>
          <p v-if="series && regionPrediction" class="verdict small" :class="worse ? 'delta-up' : 'delta-down'">{{ worse ? t('gov.org.worseThanRegion') : t('gov.org.notWorseThanRegion') }}</p>
                  </AppCard>
      </div>

      <div class="col">
        <AppCard v-if="auth.can('admin.users')" :title="t('gov.org.loadTitle')" data-testid="org-doctor-load">
          <template #header><SelectButton v-model="loadSort" :options="loadSortOptions" option-label="label" option-value="value" size="small" :allow-empty="false" /></template>
          <p v-if="!loadRows.length" class="muted small">{{ t('gov.org.loadEmpty') }}</p>
          <template v-else>
            <p class="load-summary">{{ t('gov.org.loadSummary', { n: days(doctorsAvg, 0) }) }} {{ overloaded.length ? t('gov.org.loadOver', { names: overloaded.join(', ') }) : t('gov.org.loadNoOver') }}</p>
            <div :class="{ 'paged-box': loadRows.length > LOAD_PAGE }"><table class="dense-table load-table">
              <thead><tr><th>{{ t('gov.org.loadColDoctor') }}</th><th class="num">{{ t('gov.org.loadColReferrals') }}</th><th>{{ t('gov.org.loadColLevel') }}</th></tr></thead>
              <tbody>
                <tr v-for="d in loadPageRows" :key="d.id">
                  <td :title="d.specialty ?? ''">{{ d.displayName ?? '—' }}</td>
                  <td class="num tabular">{{ d.referrals }}</td>
                  <td><StatusTag :value="t('gov.org.loadLevel.' + loadLevel(d.referrals ?? 0))" :tone="LOAD_TONES[loadLevel(d.referrals ?? 0)]" /></td>
                </tr>
              </tbody>
            </table></div>
            <ArrowPager v-model:page="loadPage" :total="loadRows.length" :size="LOAD_PAGE" />
          </template>
        </AppCard>
        <AppCard :title="t('gov.org.signals')" origin="ml" class="signals-card">
          <template #header><span class="caption">{{ t('gov.org.signalsCount', { n: anomalies.length }) }}</span></template>
          <p class="caption chart-note">{{ t('gov.org.signalsNote') }}</p>
          <div class="signals-scroll">
            <AnomalyFeed :items="anomalies" compact :can-ack="auth.canAny(['gov.map', 'org.cabinet'])" @ack="(id, c) => resolve(id, c, 'acknowledged')" @dismiss="(id, c) => resolve(id, c, 'dismissed')" />
          </div>
        </AppCard>
      </div>
    </div>
  </PageShell>
</template>

<style scoped>
.sub-line { display: inline-flex; flex-wrap: wrap; gap: 4px 0; }
.sub-line > span + span::before { content: '·'; margin: 0 8px; color: var(--text-muted); }
.page-legend { display: flex; margin-top: 8px; }
.footnote { margin-top: var(--dm-space-4); }
.w-profile { min-width: 240px; }
.main-grid { display: grid; grid-template-columns: minmax(0, 1.5fr) minmax(0, 1fr); gap: var(--dm-space-4); align-items: start; }
.col { display: flex; flex-direction: column; gap: var(--dm-space-4); min-width: 0; }
.action-link { gap: 8px; text-decoration: none; }
.chart-note { margin: -4px 0 12px; line-height: 1.45; }
.load-summary { margin: 0 0 6px; line-height: 1.5; }
.load-table td { height: 44px; }
.paged-box { min-height: 268px; }
.signals-scroll { max-height: 720px; overflow-y: auto; margin-right: -8px; padding-right: 8px; }
.strong { font-weight: var(--fw-bold); }
.verdict { margin: 12px 0 0; font-weight: var(--fw-bold); }
@media (max-width: 1000px) { .main-grid { grid-template-columns: 1fr; } }
</style>
