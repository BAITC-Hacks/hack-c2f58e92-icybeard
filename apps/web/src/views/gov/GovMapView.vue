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
import PageShell from '@/components/ui/PageShell.vue'
import SearchSelect from '@/components/ui/SearchSelect.vue'
import Skeleton from '@/components/ui/Skeleton.vue'
import Sparkline from '@/components/ui/Sparkline.vue'
import { days, pct } from '@/lib/format'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'

/** Карта регионов: KPI со спарклайнами по месяцам индекса, карта и таблица в одной карточке с общей подсветкой,
 * лента сигналов с фильтром по статусу; остальные витрины по стране — свёрнутыми секциями. */
/** «Регионов ниже порога» — индекс ниже середины шкалы 0…100. */
const INDEX_THRESHOLD = 50
const HISTORY_MONTHS = 6
const SIGNAL_STATUSES = ['open', 'acknowledged', 'dismissed'] as const

const { t } = useI18n()
const refdata = useRefdataStore()
const auth = useAuthStore()
const router = useRouter()
const toast = useToast()

const month = ref<string | null>(null)
const profile = ref<string>('all')
const index = ref<IndexResponse | null>(null)
const history = ref<{ month: string; avgP90: number; shareOver30: number; below: number }[]>([])
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
  return {
    avgP90: mean(items.map((i) => i.p90Days)),
    shareOver30: mean(items.map((i) => i.shareOver30)),
    below: items.filter((i) => i.indexValue < INDEX_THRESHOLD).length,
  }
})
/** Открытые сигналы по периодам — спарклайн из самой ленты (отдельной истории у сигналов нет). */
const signalSpark = computed(() => {
  const counts = new Map<string, number>()
  for (const a of openAnomalies.value) counts.set(a.period, (counts.get(a.period) ?? 0) + 1)
  return [...counts.entries()].sort(([a], [b]) => (a < b ? -1 : 1)).map(([, n]) => n)
})

async function load() {
  loading.value = true
  error.value = null
  try {
    const [idx, ov] = await Promise.all([analytics.index(month.value ?? undefined, profileCode.value), queue.overloaded(undefined, profileCode.value)])
    index.value = idx
    if (month.value !== idx.month) settingMonth = true
    month.value = idx.month
    overloaded.value = ov.items
    await loadHistory(idx.months)
  } catch (e) {
    error.value = e
  } finally {
    loading.value = false
  }
}

/** История KPI по последним месяцам индекса — для спарклайнов. */
async function loadHistory(months: string[]) {
  const recent = months.slice(-HISTORY_MONTHS)
  const responses = await Promise.all(recent.map((m) => analytics.index(m, profileCode.value).catch(() => null)))
  history.value = responses.flatMap((r, i) =>
    r ? [{ month: recent[i]!, avgP90: mean(r.items.map((x) => x.p90Days)), shareOver30: mean(r.items.map((x) => x.shareOver30)), below: r.items.filter((x) => x.indexValue < INDEX_THRESHOLD).length }] : [],
  )
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
  <PageShell :title="t('gov.map.title')" :lead="t('gov.map.lead')" :as-of="index?.month">
    <template #actions>
      <Select v-model="month" :options="index?.months ?? []" :placeholder="t('common.month')" size="small" />
      <SearchSelect v-model="profile" :options="profileOptions" option-label="name" option-value="profileCode" size="small" class="profile-select" />
      <Button :label="t('gov.map.reportPdf')" icon="pi pi-file-pdf" size="small" severity="secondary" outlined :loading="downloading" @click="report('pdf')" />
      <Button label="Excel" icon="pi pi-file-excel" size="small" severity="secondary" outlined :loading="downloading" @click="report('xlsx')" />
    </template>
    <ErrorBox :error="error" />

    <div class="kpi" data-testid="gov-kpis">
      <div class="item">
        <div class="kpi-top"><span class="value">{{ days(kpis.avgP90) }}</span><Sparkline :values="history.map((h) => h.avgP90)" /></div>
        <div class="label">{{ t('gov.map.kpiAvgP90') }}</div>
      </div>
      <div class="item">
        <div class="kpi-top"><span class="value">{{ pct(kpis.shareOver30) }}</span><Sparkline :values="history.map((h) => h.shareOver30)" /></div>
        <div class="label">{{ t('gov.map.kpiShareOver30') }}</div>
      </div>
      <div class="item">
        <div class="kpi-top"><span class="value">{{ openTotal }}</span><Sparkline :values="signalSpark" /></div>
        <div class="label">{{ t('gov.map.openSignals') }}</div>
      </div>
      <div class="item">
        <div class="kpi-top"><span class="value">{{ index ? kpis.below : '—' }}</span><Sparkline :values="history.map((h) => h.below)" /></div>
        <div class="label">{{ t('gov.map.kpiBelow', { threshold: INDEX_THRESHOLD }) }}</div>
      </div>
    </div>

    <AppCard :title="`${t('gov.map.indexFor')} ${index?.month ?? '…'}`" origin="formula" style="margin-top: 16px">
      <template #header><span class="muted small">{{ loading ? t('common.loading') : t('gov.map.hoverHint') }}</span></template>
      <div class="map-grid">
        <RegionMap :regions="refdata.regions" :index="index?.items ?? []" :highlight="hovered" @select="toRegion" @hover="hovered = $event" />
        <Skeleton v-if="loading && !index" kind="table" :lines="8" />
        <IndexTable v-else :items="index?.items ?? []" :highlight="hovered" @select="toRegion" @hover="hovered = $event" />
      </div>
      <p class="muted small" style="margin: 12px 0 0">{{ index?.method }}</p>
      <!-- значения и правило применения: refdata/external_benchmarks.yaml -->
      <p class="muted small" style="margin: 4px 0 0">{{ t('gov.map.benchmark') }}</p>
    </AppCard>

    <AppCard :title="t('gov.map.signals')" origin="formula" style="margin-top: 16px" data-testid="signals">
      <template #header>
        <div class="chips">
          <button v-for="s in SIGNAL_STATUSES" :key="s" type="button" class="chip-filter" :class="{ active: signalStatus === s }" @click="signalStatus = s">
            {{ t('anomaly.status.' + s) }} <span v-if="s === 'open'" class="count">{{ openTotal }}</span>
          </button>
        </div>
      </template>
      <AnomalyFeed :items="anomalies" :can-ack="auth.hasRole('chief', 'regulator')" @ack="(id, c) => resolve(id, c, 'acknowledged')" @dismiss="(id, c) => resolve(id, c, 'dismissed')" />
    </AppCard>

    <div class="extras">
      <CollapsibleSection :title="t('gov.map.overloaded')" origin="formula" :summary="String(overloaded.length)">
        <OverloadedTable :items="overloaded" @organization="router.push({ name: 'organization', params: { moCode: $event } })" @simulate="router.push({ name: 'simulator', query: { region: $event.regionKato, profile: $event.profileCode } })" />
      </CollapsibleSection>
      <CountryExtras />
    </div>
  </PageShell>
</template>

<style scoped>
.profile-select { min-width: 260px; }
.kpi-top { display: flex; align-items: flex-end; justify-content: space-between; gap: 8px; }
.map-grid { display: grid; grid-template-columns: 1.2fr 1fr; gap: var(--dm-space-4); align-items: start; }
.extras { display: flex; flex-direction: column; gap: var(--dm-space-3); margin-top: 16px; }
@media (max-width: 1000px) { .map-grid { grid-template-columns: 1fr; } }
</style>
