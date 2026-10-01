<script setup lang="ts">
import Button from 'primevue/button'
import IconField from 'primevue/iconfield'
import InputIcon from 'primevue/inputicon'
import InputText from 'primevue/inputtext'
import Select from 'primevue/select'
import { useToast } from 'primevue/usetoast'
import { computed, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRouter } from 'vue-router'
import { analytics, insight, queue } from '@/api/endpoints'
import type { Anomaly, IndexResponse, OverloadedOrganization } from '@/api/types'
import AnomalyFeed from '@/components/AnomalyFeed.vue'
import ErrorBox from '@/components/ErrorBox.vue'
import OriginLegend from '@/components/OriginLegend.vue'
import CountryExtras from '@/components/gov/CountryExtras.vue'
import IndexTable from '@/components/IndexTable.vue'
import OverloadedTable from '@/components/OverloadedTable.vue'
import RegionMap from '@/components/RegionMap.vue'
import AppCard from '@/components/ui/AppCard.vue'
import CollapsibleSection from '@/components/ui/CollapsibleSection.vue'
import KpiRow from '@/components/ui/KpiRow.vue'
import KpiTile from '@/components/ui/KpiTile.vue'
import PageShell from '@/components/ui/PageShell.vue'
import SearchSelect from '@/components/ui/SearchSelect.vue'
import Skeleton from '@/components/ui/Skeleton.vue'
import { anomalySentence, describeEntity, streamTitle, type EntityNames } from '@/lib/anomaly'
import { days, INDEX_SCALE_STEPS, num, pct, shortOrgName } from '@/lib/format'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'

/** Карта регионов (W-Gov): четыре KPI-карточки, слева карта со шкалой пяти синих и коралловыми точками аномалий,
 * справа список аномалий и перегруженные организации; ниже рейтинг регионов, лента сигналов с подтверждением и
 * остальные витрины по стране — свёрнутыми секциями. */
/** «Регионов ниже порога» — индекс ниже середины шкалы 0…100. */
const INDEX_THRESHOLD = 50
const ANOMALY_ROWS = 30
const OVERLOADED_ROWS = 5
const SIGNAL_STATUSES = ['open', 'acknowledged', 'dismissed'] as const

const { t } = useI18n()
const refdata = useRefdataStore()
const auth = useAuthStore()
const router = useRouter()
const toast = useToast()

const month = ref<string | null>(null)
const profile = ref<string>('all')
const index = ref<IndexResponse | null>(null)
const openAnomalies = ref<Anomaly[]>([])
const openTotal = ref(0)
const anomalies = ref<Anomaly[]>([])
const signalStatus = ref<(typeof SIGNAL_STATUSES)[number]>('open')
const signalSearch = ref('')
const signalStatusOptions = computed(() => SIGNAL_STATUSES.map((s) => ({ value: s, label: t('gov.map.signalStatus.' + s) })))
/** Поиск по уже загруженным сигналам: регион, больница, профиль, поток. */
const shownAnomalies = computed(() => {
  const q = signalSearch.value.trim().toLowerCase()
  return q ? anomalies.value.filter((a) => [describeEntity(a.entity, a.regionKato, names).join(' '), streamTitle(a.streamId)].join(' ').toLowerCase().includes(q)) : anomalies.value
})
const overloaded = ref<OverloadedOrganization[]>([])
const hovered = ref<string | null>(null)
const error = ref<unknown>(null)
const loading = ref(false)
const downloading = ref(false)

const profileCode = computed(() => (profile.value === 'all' ? undefined : profile.value))
const profileOptions = computed(() => [{ profileCode: 'all', name: t('common.all') }, ...refdata.profiles])
const mean = (values: number[]) => (values.length ? values.reduce((s, v) => s + v, 0) / values.length : NaN)
const kpis = computed(() => {
  const items = index.value?.items ?? []
  return { avgP90: mean(items.map((i) => i.p90Days)), shareOver30: mean(items.map((i) => i.shareOver30)), below: items.filter((i) => i.indexValue < INDEX_THRESHOLD).length }
})
const anomalyRegions = computed(() => new Set(openAnomalies.value.map((a) => a.regionKato).filter((k): k is string => !!k)))
/** Подписи ступеней легенды из тех же порогов, что красят карту (indexStep): «60 и выше», «50–59», …, «ниже 30». */
const legendSteps = computed(() => {
  const edges = INDEX_SCALE_STEPS
  return [
    t('gov.map.legend.atLeast', { n: edges[0] }),
    ...edges.slice(1).map((edge, i) => t('gov.map.legend.range', { from: edge, to: edges[i] - 1 })),
    t('gov.map.legend.below', { n: edges[edges.length - 1] }),
  ]
})
/** Регион для ссылки «Открыть …»: наведённый, иначе первый по рейтингу. */
const focusRegion = computed(() => hovered.value ?? index.value?.items[0]?.regionKato ?? null)
const names: EntityNames = {
  region: (kato) => refdata.regionName(kato),
  profile: (code) => refdata.profileName(code),
  organization: (moCode) => shortOrgName(refdata.organizationName(moCode)),
}

async function load() {
  loading.value = true
  error.value = null
  try {
    const [idx, ov] = await Promise.all([analytics.index(month.value ?? undefined, profileCode.value), queue.overloaded(undefined, profileCode.value)])
    index.value = idx
    if (month.value !== idx.month) settingMonth = true
    month.value = idx.month
    overloaded.value = ov.items
  } catch (e) {
    error.value = e
  } finally {
    loading.value = false
  }
}

async function loadSignals() {
  try {
    const page = await analytics.anomalies({ status: signalStatus.value, size: 50 })
    anomalies.value = page.items
    if (signalStatus.value === 'open') {
      openAnomalies.value = page.items
      openTotal.value = page.total
    }
  } catch (e) {
    error.value = e
  }
}

async function report(format: 'pdf' | 'xlsx') {
  downloading.value = true
  try {
    await insight.report(format, month.value ?? undefined, profileCode.value)
  } catch (e) {
    error.value = e
  } finally {
    downloading.value = false
  }
}

async function resolve(id: string, comment: string, status: 'acknowledged' | 'dismissed') {
  try {
    await analytics.ack(id, comment, status)
    anomalies.value = anomalies.value.filter((a) => a.id !== id)
    openAnomalies.value = openAnomalies.value.filter((a) => a.id !== id)
    openTotal.value = Math.max(0, openTotal.value - 1)
    toast.add({ severity: status === 'acknowledged' ? 'success' : 'info', summary: t(status === 'acknowledged' ? 'gov.map.ackToast' : 'gov.map.dismissToast'), life: 2500 })
  } catch (e) {
    error.value = e
  }
}

const toRegion = (kato: string) => router.push({ name: 'region', params: { kato } })

onMounted(async () => {
  await refdata.load()
  await Promise.all([load(), loadSignals()])
})
let settingMonth = false // месяц, подставленный из ответа, не должен запускать повторную загрузку
watch([month, profile], () => {
  if (settingMonth) {
    settingMonth = false
    return
  }
  load()
})
watch(signalStatus, loadSignals)
</script>

<template>
  <PageShell :title="t('gov.map.title')">
    <template #subtitle>
      {{ t('gov.map.subtitle') }}<template v-if="index"> · {{ t('gov.map.indexFor') }} {{ index.month }}</template><template v-if="refdata.referralsTotal"> · {{ num(Math.round(refdata.referralsTotal / 1000)) }} {{ t('home.thousand') }} {{ t('home.factReferrals') }}</template>
      <div class="page-legend"><OriginLegend /></div>
    </template>
    <template #actions>
      <SearchSelect v-model="profile" :options="profileOptions" option-label="name" option-value="profileCode" size="small" class="profile-select" />
      <Select v-model="month" :options="index?.months ?? []" :placeholder="t('common.month')" size="small" />
      <Button :label="t('gov.map.reportPdf')" icon="pi pi-file-pdf" size="small" severity="secondary" :loading="downloading" @click="report('pdf')" />
      <Button label="Excel" icon="pi pi-file-excel" size="small" severity="secondary" :loading="downloading" @click="report('xlsx')" />
    </template>
    <ErrorBox :error="error" />

    <KpiRow data-testid="gov-kpis">
      <KpiTile label-first :value="days(kpis.avgP90)" :unit="t('common.days')" :label="t('gov.map.kpiP90Label')" :hint="t('gov.map.kpiP90Hint')" :loading="loading && !index" />
      <KpiTile label-first :value="pct(kpis.shareOver30)" :label="t('gov.map.kpiOver30Label')" :hint="t('gov.map.kpiOver30Hint')" tone="warn" :loading="loading && !index" />
      <KpiTile label-first :value="index ? kpis.below : '—'" :label="t('gov.map.kpiBelowLabel')" :hint="t('gov.map.kpiBelowHint', { threshold: INDEX_THRESHOLD, total: index?.items.length ?? 0 })" :loading="loading && !index" />
      <KpiTile label-first :value="overloaded.length" :label="t('gov.map.kpiOverloadedLabel')" :hint="t('gov.map.kpiOverloadedHint')" tone="danger" :loading="loading && !index" />
    </KpiRow>

    <div class="main-grid">
      <AppCard :title="t('gov.map.indexByRegion')">
        <p class="caption card-lead">{{ t('gov.map.indexLead') }}</p>
        <RegionMap :regions="refdata.regions" :index="index?.items ?? []" :highlight="hovered" :anomalies="anomalyRegions" @select="toRegion" @hover="hovered = $event" />
        <div class="legend caption">
          <span class="legend-title">{{ t('gov.map.legend.title') }}</span>
          <span v-for="(label, i) in legendSteps" :key="i" class="legend-item"><span class="swatch" :style="{ background: `var(--dm-map-${i + 1})` }" />{{ label }}</span>
          <span class="legend-item"><span class="swatch dot" />{{ t('gov.map.legend.anomaly') }}</span>
          <RouterLink v-if="focusRegion" class="link-arrow small legend-open" :to="{ name: 'region', params: { kato: focusRegion } }">{{ t('gov.map.openRegion', { name: refdata.regionName(focusRegion) }) }}</RouterLink>
        </div>
        <p class="caption" style="margin: 8px 0 0">{{ t('gov.map.indexMethodPlain') }}</p>
      </AppCard>

      <div class="side-slot">
        <AppCard :title="t('gov.map.anomaliesTitle')" origin="ml" data-testid="signals" class="side-card">
          <template #header><span class="caption">{{ t('gov.map.signalsSummary', { n: openTotal }) }}</span></template>
          <p class="caption card-lead">{{ t('gov.map.anomaliesLead') }}</p>
          <Skeleton v-if="loading && openAnomalies.length === 0" :lines="4" />
          <p v-else-if="openAnomalies.length === 0" class="muted">{{ t('anomalyFeed.empty') }}</p>
          <div v-else class="rows side-scroll">
            <RouterLink v-for="a in openAnomalies.slice(0, ANOMALY_ROWS)" :key="a.id" class="row anomaly-row" :to="a.regionKato ? { name: 'region', params: { kato: a.regionKato } } : { name: 'gov' }">
              <span class="anomaly-dot" :class="{ idle: a.severity !== 'critical' }" aria-hidden="true" />
              <span class="row-main">
                <span class="anomaly-title">{{ describeEntity(a.entity, a.regionKato, names).join(' · ') }}</span>
                <span class="row-sub">{{ streamTitle(a.streamId) }} · {{ anomalySentence(a, num) }}</span>
              </span>
            </RouterLink>
          </div>
          <a v-if="openTotal > 0" class="link-arrow small side-more" href="#signals-feed">{{ t('gov.map.allSignals') }} · {{ openTotal }}</a>
        </AppCard>
      </div>
    </div>

    <AppCard :title="t('gov.map.overloaded')" class="overloaded-card">
      <template #header><span class="caption">{{ t('gov.map.overloadedCount', { n: overloaded.length }) }}</span></template>
      <p class="caption card-lead">{{ t('gov.map.overloadedLead') }}</p>
      <Skeleton v-if="loading && overloaded.length === 0" kind="table" :lines="3" />
      <OverloadedTable v-else :items="overloaded" :size="OVERLOADED_ROWS" @organization="router.push({ name: 'organization', params: { moCode: $event } })" @simulate="router.push({ name: 'simulator', query: { region: $event.regionKato, profile: $event.profileCode } })" />
    </AppCard>

    <CollapsibleSection :title="t('gov.map.ranking')" :summary="index ? t('gov.map.rankingSummary', { n: index.items.length }) : ''">
      <Skeleton v-if="loading && !index" kind="table" :lines="8" />
      <IndexTable v-else :items="index?.items ?? []" :highlight="hovered" @select="toRegion" @hover="hovered = $event" />
      <!-- значения и правило применения: refdata/external_benchmarks.yaml -->
      <p class="caption" style="margin: 12px 0 0">{{ t('gov.map.benchmark') }}</p>
    </CollapsibleSection>

    <CollapsibleSection id="signals-feed" :title="t('gov.map.signals')" origin="ml" :summary="t('gov.map.signalsSummary', { n: openTotal })" :lead="t('gov.map.signalsLead')">
      <div class="toolbar list-toolbar">
        <span class="list-count">{{ t('gov.map.signalsShown', { n: shownAnomalies.length }) }}</span>
        <span class="spacer" />
        <Select v-model="signalStatus" :options="signalStatusOptions" option-label="label" option-value="value" class="f-select" :aria-label="t('gov.map.signals')" />
        <IconField class="search-field">
          <InputIcon class="pi pi-search" />
          <InputText v-model="signalSearch" :placeholder="t('gov.map.signalsSearch')" :aria-label="t('gov.map.signalsSearch')" />
        </IconField>
      </div>
      <div class="feed-box"><AnomalyFeed :items="shownAnomalies" :can-ack="auth.canAny(['gov.map', 'org.cabinet'])" @ack="(id, c) => resolve(id, c, 'acknowledged')" @dismiss="(id, c) => resolve(id, c, 'dismissed')" /></div>
    </CollapsibleSection>

    <div class="extras"><CountryExtras /></div>
  </PageShell>
</template>

<style scoped>
.profile-select { min-width: 220px; }
.page-legend { display: flex; margin-top: 8px; }
.card-lead { margin: -4px 0 12px; line-height: 1.5; }
.overloaded-card { margin-top: var(--dm-space-4); }
.list-toolbar { margin-bottom: 12px; row-gap: 8px; }
.list-count { color: var(--text-secondary); }
.spacer { flex: 1; }
.f-select { min-width: 200px; }
.search-field { flex: 0 1 340px; min-width: 240px; }
.feed-box { max-height: 640px; overflow-y: auto; padding-right: 8px; border-top: 1px solid var(--dm-hairline); }
.side-slot { position: relative; min-height: 420px; }
.side-card { position: absolute; inset: 0; display: flex; flex-direction: column; }
.side-scroll { flex: 1; min-height: 0; overflow-y: auto; padding-right: 6px; }
.side-scroll > * { flex-shrink: 0; }
.side-more { margin-top: 12px; }
.legend-title { color: var(--text); font-weight: var(--fw-bold); }
.search-field :deep(.p-inputtext) { width: 100%; }
.row-sub { display: block; }
.main-grid { display: grid; grid-template-columns: minmax(0, 1.5fr) minmax(0, 1fr); gap: var(--dm-space-4); align-items: stretch; }
.col { display: flex; flex-direction: column; gap: var(--dm-space-4); min-width: 0; }
.legend { display: flex; gap: 14px; align-items: center; flex-wrap: wrap; margin-top: 12px; }
.legend-open { margin-left: auto; }
.legend-item { display: inline-flex; align-items: center; gap: 6px; }
.swatch { width: 12px; height: 12px; border-radius: 3px; display: inline-block; }
.swatch.dot { border-radius: 50%; background: var(--dm-warn-strong); width: 10px; height: 10px; }
.anomaly-row { text-decoration: none; color: inherit; justify-content: flex-start; align-items: flex-start; gap: 12px; }
.anomaly-row:hover .anomaly-title { color: var(--dm-accent-hover); }
.anomaly-dot { width: 8px; height: 8px; border-radius: 50%; background: var(--dm-warn-strong); flex: none; margin-top: 7px; }
.anomaly-dot.idle { background: var(--dm-dot-idle); }
.anomaly-title { font-size: var(--dm-text-md); line-height: 1.35; }
.extras { display: flex; flex-direction: column; gap: var(--dm-space-3); }
@media (max-width: 1000px) {
  .main-grid { grid-template-columns: 1fr; }
  .side-slot { min-height: 0; }
  .side-card { position: static; }
  .side-scroll { max-height: 480px; }
}
</style>
