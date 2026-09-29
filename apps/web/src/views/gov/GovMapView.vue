<script setup lang="ts">
import Button from 'primevue/button'
import Select from 'primevue/select'
import { useToast } from 'primevue/usetoast'
import { computed, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRouter } from 'vue-router'
import { analytics, insight, queue } from '@/api/endpoints'
import type { Anomaly, IndexResponse, OverloadedOrganization } from '@/api/types'
import AnomalyFeed from '@/components/AnomalyFeed.vue'
import ErrorBox from '@/components/ErrorBox.vue'
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
import { describeEntity, streamTitle, type EntityNames } from '@/lib/anomaly'
import { days, num, pct, shortOrgName } from '@/lib/format'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'

/** Карта регионов (W-Gov): четыре KPI-карточки, слева карта со шкалой пяти синих и коралловыми точками аномалий,
 * справа список аномалий и перегруженные организации; ниже рейтинг регионов, лента сигналов с подтверждением и
 * остальные витрины по стране — свёрнутыми секциями. */
/** «Регионов ниже порога» — индекс ниже середины шкалы 0…100. */
const INDEX_THRESHOLD = 50
const ANOMALY_ROWS = 5
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
    </template>
    <template #actions>
      <SearchSelect v-model="profile" :options="profileOptions" option-label="name" option-value="profileCode" size="small" class="profile-select" />
      <Select v-model="month" :options="index?.months ?? []" :placeholder="t('common.month')" size="small" />
      <Button :label="t('gov.map.reportPdf')" icon="pi pi-file-pdf" size="small" severity="secondary" :loading="downloading" @click="report('pdf')" />
      <Button label="Excel" icon="pi pi-file-excel" size="small" severity="secondary" :loading="downloading" @click="report('xlsx')" />
    </template>
    <ErrorBox :error="error" />

    <KpiRow data-testid="gov-kpis">
      <KpiTile :value="days(kpis.avgP90)" :unit="t('common.days')" :label="t('gov.map.kpiAvgP90')" origin="formula" :loading="loading && !index" />
      <KpiTile :value="pct(kpis.shareOver30)" :label="t('gov.map.kpiShareOver30')" tone="warn" origin="formula" :loading="loading && !index" />
      <KpiTile :value="index ? kpis.below : '—'" :label="t('gov.map.kpiBelow', { threshold: INDEX_THRESHOLD })" origin="formula" :loading="loading && !index" />
      <KpiTile :value="overloaded.length" :label="t('gov.map.kpiOverloaded')" tone="danger" :chip="openTotal ? t('gov.map.signalsChip', { n: openTotal }) : undefined" origin="formula" :loading="loading && !index" />
    </KpiRow>

    <div class="main-grid">
      <AppCard :title="t('gov.map.indexByRegion')" origin="formula">
        <RegionMap :regions="refdata.regions" :index="index?.items ?? []" :highlight="hovered" :anomalies="anomalyRegions" @select="toRegion" @hover="hovered = $event" />
        <div class="legend caption">
          <span class="legend-item"><span class="swatch" :style="{ background: 'var(--scale-good)' }" />{{ t('gov.map.legend.good') }}</span>
          <span class="legend-item"><span class="swatch" :style="{ background: 'var(--scale-mid)' }" />{{ t('gov.map.legend.mid') }}</span>
          <span class="legend-item"><span class="swatch" :style="{ background: 'var(--scale-bad)' }" />{{ t('gov.map.legend.bad') }}</span>
          <span class="legend-item"><span class="swatch dot" />{{ t('gov.map.legend.anomaly') }}</span>
          <span>· {{ t('gov.map.legend.higherBetter') }}</span>
          <RouterLink v-if="focusRegion" class="link-arrow small legend-open" :to="{ name: 'region', params: { kato: focusRegion } }">{{ t('gov.map.openRegion', { name: refdata.regionName(focusRegion) }) }}</RouterLink>
        </div>
        <p class="caption" style="margin: 8px 0 0">{{ index?.method }}</p>
      </AppCard>

      <div class="col">
        <AppCard :title="t('gov.map.anomaliesTitle')" origin="ml" data-testid="signals">
          <template #header><span class="caption">{{ index?.month ?? '' }}</span></template>
          <Skeleton v-if="loading && openAnomalies.length === 0" :lines="4" />
          <p v-else-if="openAnomalies.length === 0" class="muted">{{ t('anomalyFeed.empty') }}</p>
          <div v-else class="rows">
            <RouterLink v-for="a in openAnomalies.slice(0, ANOMALY_ROWS)" :key="a.id" class="row anomaly-row" :to="a.regionKato ? { name: 'region', params: { kato: a.regionKato } } : { name: 'gov' }">
              <span class="anomaly-dot" :class="{ idle: a.severity !== 'critical' }" aria-hidden="true" />
              <span class="row-main">
                <span class="anomaly-title">{{ describeEntity(a.entity, a.regionKato, names).join(' · ') }} · {{ streamTitle(a.streamId) }}</span>
                <span class="row-sub">{{ a.period }} · {{ t('anomalyFeed.observed') }} {{ num(a.observed) }} {{ t('anomalyFeed.atExpected') }} {{ num(a.expected) }}</span>
              </span>
            </RouterLink>
          </div>
          <a v-if="openTotal > ANOMALY_ROWS" class="link-arrow small" href="#signals-feed" style="margin-top: 12px">{{ t('gov.map.allSignals') }} · {{ openTotal }}</a>
        </AppCard>

        <AppCard :title="t('gov.map.overloaded')" origin="formula">
          <template #header><RouterLink class="link-arrow small" :to="{ name: 'simulator' }">{{ t('nav.simulator') }}</RouterLink></template>
          <Skeleton v-if="loading && overloaded.length === 0" kind="table" :lines="3" />
          <OverloadedTable v-else :items="overloaded" :limit="OVERLOADED_ROWS" @organization="router.push({ name: 'organization', params: { moCode: $event } })" @simulate="router.push({ name: 'simulator', query: { region: $event.regionKato, profile: $event.profileCode } })" />
        </AppCard>
      </div>
    </div>

    <CollapsibleSection :title="t('gov.map.ranking')" origin="formula" :summary="index ? `${index.items.length}` : ''">
      <Skeleton v-if="loading && !index" kind="table" :lines="8" />
      <IndexTable v-else :items="index?.items ?? []" :highlight="hovered" @select="toRegion" @hover="hovered = $event" />
      <!-- значения и правило применения: refdata/external_benchmarks.yaml -->
      <p class="caption" style="margin: 12px 0 0">{{ t('gov.map.benchmark') }}</p>
    </CollapsibleSection>

    <CollapsibleSection id="signals-feed" :title="t('gov.map.signals')" origin="ml" :summary="String(openTotal)">
      <div class="chips" style="margin-bottom: 12px">
        <button v-for="s in SIGNAL_STATUSES" :key="s" type="button" class="chip-filter" :class="{ active: signalStatus === s }" @click="signalStatus = s">
          {{ t('anomaly.status.' + s) }} <span v-if="s === 'open'" class="count">{{ openTotal }}</span>
        </button>
      </div>
      <AnomalyFeed :items="anomalies" :can-ack="auth.canAny(['gov.map', 'org.cabinet'])" @ack="(id, c) => resolve(id, c, 'acknowledged')" @dismiss="(id, c) => resolve(id, c, 'dismissed')" />
    </CollapsibleSection>

    <div class="extras"><CountryExtras /></div>
  </PageShell>
</template>

<style scoped>
.profile-select { min-width: 220px; }
.main-grid { display: grid; grid-template-columns: minmax(0, 1.5fr) minmax(0, 1fr); gap: var(--dm-space-4); align-items: start; }
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
@media (max-width: 1000px) { .main-grid { grid-template-columns: 1fr; } }
</style>
