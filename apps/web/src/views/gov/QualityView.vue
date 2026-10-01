<script setup lang="ts">
import IconField from 'primevue/iconfield'
import InputIcon from 'primevue/inputicon'
import InputText from 'primevue/inputtext'
import Select from 'primevue/select'
import SelectButton from 'primevue/selectbutton'
import { computed, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { analytics, refdata as refdataApi } from '@/api/endpoints'
import type { QualityBreakdownRow, QualityReport, VaccinationBenchmark } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import OriginLegend from '@/components/OriginLegend.vue'
import OriginTag from '@/components/OriginTag.vue'
import AppCard from '@/components/ui/AppCard.vue'
import ArrowPager from '@/components/ui/ArrowPager.vue'
import CollapsibleSection from '@/components/ui/CollapsibleSection.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import KpiRow from '@/components/ui/KpiRow.vue'
import KpiTile from '@/components/ui/KpiTile.vue'
import PageShell from '@/components/ui/PageShell.vue'
import Skeleton from '@/components/ui/Skeleton.vue'
import StatusTag from '@/components/ui/StatusTag.vue'
import type { StatusTone } from '@/components/ui/tones'
import { useLocaleFormat } from '@/composables/useLocaleFormat'
import { pct } from '@/lib/format'
import { useRefdataStore } from '@/stores/refdata'

/** Качество моделей простыми словами (W-Quality): «насколько можно доверять прогнозам». Четыре KPI (подпись над
 * числом, ориентир — простое правило), таблица «Модели в системе» (точность понятными единицами и сравнение
 * с правилом цветной меткой), «Где модель ошибается чаще» — регионы/профили с фильтром, поиском и листанием,
 * прогнозы потоков и сигналы; технические метрики и оговорки — в свёрнутом «Подробности для аналитиков». */
type Unit = 'days' | 'score' | 'ratio' | 'share'
interface ModelRow { key: string; model: number | null; baseline: number | null; lowerIsBetter: boolean; unit: Unit; metric: string; status: 'prod' | 'check' | 'draft' }
const STREAM_IDS = ['admissions_monthly', 'er_visits_daily', 'rx_weekly', 'vac_monthly', 'onco_monthly', 'lab_estimate_monthly']
const STATUS_TONES = { prod: 'ok', check: 'warn', draft: 'neutral' } as const
const SLICE_PAGE = 8

const { t } = useI18n()
const { num } = useLocaleFormat()
const refdata = useRefdataStore()
const report = ref<QualityReport | null>(null)
const vaccination = ref<VaccinationBenchmark[]>([])
const error = ref<unknown>(null)
const loading = ref(true)

const fmt = (v: number, digits = 1) => v.toLocaleString(undefined, { minimumFractionDigits: digits, maximumFractionDigits: digits })
const streamTitle = (id: string) => (STREAM_IDS.includes(id) ? t(`gov.quality.stream.${id}`) : id)
const through = computed(() => report.value?.wait?.trainedThrough?.slice(0, 10) ?? '')
const tt = computed(() => report.value?.wait?.test_time ?? null)

/** Выигрыш к правилу в процентах (положительный — модель лучше). */
function gainPct(model: number | null, baseline: number | null, lowerIsBetter = true): number | null {
  if (model === null || baseline === null || !baseline) return null
  return Math.round((lowerIsBetter ? 1 - model / baseline : model / baseline - 1) * 100)
}
function compare(model: number | null, baseline: number | null, lowerIsBetter = true): { text: string; tone: StatusTone } {
  const g = gainPct(model, baseline, lowerIsBetter)
  if (g === null) return { text: t('gov.quality.cmpNone'), tone: 'neutral' }
  if (g === 0) return { text: t('gov.quality.cmpSame'), tone: 'neutral' }
  return g > 0 ? { text: t('gov.quality.cmpBetter', { pct: g }), tone: 'ok' } : { text: t('gov.quality.cmpWorse', { pct: -g }), tone: 'danger' }
}
/** Значение метрики понятными единицами: дни — «± 3,2 дн.», AUC/C-index — «78 из 100», MASE — «0,82». */
function valueText(v: number | null, unit: Unit): string {
  if (v === null) return '—'
  if (unit === 'days') return t('gov.quality.unitDays', { v: fmt(v) })
  if (unit === 'score') return t('gov.quality.unitScore', { v: Math.round(v * 100) })
  if (unit === 'share') return pct(v)
  return fmt(v, 2)
}

const models = computed<ModelRow[]>(() => {
  const r = report.value
  if (!r) return []
  const w = tt.value
  const surv = r.survival?.splits?.test_time
  const status = (m: number | null, b: number | null, lower = true): ModelRow['status'] => (m === null || b === null ? 'check' : (lower ? m <= b : m >= b) ? 'prod' : 'check')
  const rows: ModelRow[] = [
    { key: 'wait', model: w?.mae_p50 ?? null, baseline: w?.mae_p50_baseline ?? null, lowerIsBetter: true, unit: 'days', metric: t('gov.quality.metric.mae'), status: status(w?.mae_p50 ?? null, w?.mae_p50_baseline ?? null) },
    { key: 'refusal', model: w?.auc_refusal ?? null, baseline: w?.auc_refusal_baseline ?? null, lowerIsBetter: false, unit: 'score', metric: t('gov.quality.metric.auc'), status: status(w?.auc_refusal ?? null, w?.auc_refusal_baseline ?? null, false) },
    { key: 'los', model: r.los?.mae ?? null, baseline: r.los?.mae_baseline ?? null, lowerIsBetter: true, unit: 'days', metric: t('gov.quality.metric.mae'), status: status(r.los?.mae ?? null, r.los?.mae_baseline ?? null) },
    { key: 'survival', model: surv?.c_index ?? null, baseline: surv?.c_index_baseline ?? null, lowerIsBetter: false, unit: 'score', metric: t('gov.quality.metric.cindex'), status: status(surv?.c_index ?? null, surv?.c_index_baseline ?? null, false) },
  ]
  for (const [id, f] of Object.entries(r.forecasts)) {
    const m = f.models && f.chosen ? (f.models[f.chosen]?.mase ?? null) : null
    const b = f.models && f.baseline ? (f.models[f.baseline]?.mase ?? null) : null
    rows.push({ key: `forecast:${id}`, model: m, baseline: b, lowerIsBetter: true, unit: 'ratio', metric: t('gov.quality.metric.mase'), status: status(m, b) })
  }
  const recall = Object.values(r.anomalies).map((a) => a.recall_at_threshold).filter((v): v is number => v !== undefined)
  rows.push({ key: 'anomaly', model: recall.length ? recall.reduce((s, v) => s + v, 0) / recall.length : null, baseline: null, lowerIsBetter: false, unit: 'share', metric: t('gov.quality.metric.recall'), status: 'check' })
  rows.push({ key: 'scribe', model: null, baseline: null, lowerIsBetter: false, unit: 'ratio', metric: t('gov.quality.metric.manual'), status: 'draft' })
  return rows
})
const baseKey = (key: string) => (key.startsWith('forecast:') ? 'forecast' : key)
const modelName = (key: string) => (key.startsWith('forecast:') ? `${t('gov.quality.model.forecast')}: ${streamTitle(key.slice(9)).toLowerCase()}` : t(`gov.quality.model.${key}`))
const accuracyText = (m: ModelRow) => (m.model === null ? t('gov.quality.notMeasured') : m.unit === 'days' ? t('gov.quality.accDays', { v: fmt(m.model) }) : m.unit === 'score' ? t('gov.quality.accScore', { v: Math.round(m.model * 100) }) : m.unit === 'share' ? t('gov.quality.accShare', { v: pct(m.model) }) : t('gov.quality.accRatio', { v: fmt(m.model, 2) }))

/* «Где модель ошибается чаще»: регионы или профили, фильтр «только хуже правила», поиск, листание. */
const sliceBy = ref<'region' | 'profile'>('region')
const sliceOptions = computed(() => [{ value: 'region', label: t('gov.quality.sliceRegions') }, { value: 'profile', label: t('gov.quality.sliceProfiles') }])
const sliceFilter = ref<'all' | 'worse'>('all')
const sliceFilterOptions = computed(() => [{ value: 'all', label: t('gov.quality.filterAll') }, { value: 'worse', label: t('gov.quality.filterWorse') }])
const sliceSearch = ref('')
const slicePage = ref(0)
const rowName = (row: QualityBreakdownRow) => (row.region_kato ? refdata.regionName(row.region_kato) : row.profile_code ? refdata.profileName(row.profile_code) : '—')
const worse = (row: QualityBreakdownRow) => row.mae_p50 > row.mae_p50_baseline
const sliceAll = computed(() => (sliceBy.value === 'region' ? report.value?.wait?.by_region : report.value?.wait?.by_profile) ?? [])
const sliceRows = computed(() => {
  const q = sliceSearch.value.trim().toLowerCase()
  return sliceAll.value
    .filter((r) => sliceFilter.value === 'all' || worse(r))
    .filter((r) => !q || rowName(r).toLowerCase().includes(q))
    .sort((a, b) => b.n - a.n)
})
const slicePaged = computed(() => sliceRows.value.slice(slicePage.value * SLICE_PAGE, (slicePage.value + 1) * SLICE_PAGE))
const worseCount = computed(() => sliceAll.value.filter(worse).length)
watch([sliceBy, sliceFilter, sliceSearch], () => (slicePage.value = 0))

/* Прогнозы потоков и сигналы — строками понятной таблицы. */
const streams = computed(() => Object.entries(report.value?.forecasts ?? {}).map(([id, f]) => {
  const m = f.models && f.chosen ? (f.models[f.chosen]?.mase ?? null) : null
  const b = f.models && f.baseline ? (f.models[f.baseline]?.mase ?? null) : null
  return { id, series: f.series ?? null, cmp: compare(m, b), flat: f.flat_share ?? null, skipped: f.skipped ?? null, choice: f.per_series_choice ?? null }
}))
const anomalyRows = computed(() => Object.entries(report.value?.anomalies ?? {}).map(([id, a]) => ({ id, alerts: a.alerts ?? null, recall: a.recall_at_threshold ?? null })))
const labelledTotal = computed(() => Object.values(report.value?.anomalyLabels ?? {}).reduce((s, n) => s + n, 0))
const wuenicLine = computed(() => {
  const latest = (vaccine: string) => vaccination.value.filter((v) => v.vaccine === vaccine).at(-1)
  const dtp3 = latest('DTP3')
  const mcv1 = latest('MCV1')
  return dtp3 && mcv1 ? t('gov.quality.wuenic', { year: dtp3.year, dtp3: dtp3.coveragePct.toFixed(0), mcv1: mcv1.coveragePct.toFixed(0) }) : ''
})

onMounted(async () => {
  await refdata.load()
  try {
    report.value = await analytics.quality()
  } catch (e) {
    error.value = e
  } finally {
    loading.value = false
  }
  try {
    vaccination.value = (await refdataApi.vaccination()).items
  } catch {
    // внешний ориентир опционален
  }
})
</script>

<template>
  <PageShell :title="t('gov.quality.title')">
    <template #subtitle>
      {{ t('gov.quality.subtitlePlain', { through: through || '—' }) }}
      <div class="page-legend"><OriginLegend /></div>
    </template>
    <ErrorBox :error="error" />
    <AppCard v-if="loading"><Skeleton kind="kpi" /><Skeleton :lines="4" style="margin-top: 12px" /></AppCard>
    <AppCard v-else-if="!report?.wait">
      <EmptyState :title="t('gov.quality.noReportTitle')" :text="t('gov.quality.noReportText')" icon="pi pi-verified"><code>make eval</code></EmptyState>
    </AppCard>

    <template v-if="tt">
      <KpiRow data-testid="quality-kpis">
        <KpiTile label-first :value="valueText(tt.mae_p50, 'days')" :label="t('gov.quality.kpiWaitLabel')" :hint="t('gov.quality.ruleHint', { v: valueText(tt.mae_p50_baseline, 'days') })" :chip="compare(tt.mae_p50, tt.mae_p50_baseline).text" :chip-tone="compare(tt.mae_p50, tt.mae_p50_baseline).tone" />
        <KpiTile label-first :value="valueText(tt.auc_refusal, 'score')" :label="t('gov.quality.kpiRefusalLabel')" :hint="t('gov.quality.kpiRefusalHint', { v: valueText(tt.auc_refusal_baseline, 'score') })" :chip="compare(tt.auc_refusal, tt.auc_refusal_baseline, false).text" :chip-tone="compare(tt.auc_refusal, tt.auc_refusal_baseline, false).tone" />
        <KpiTile label-first :value="pct(tt.coverage_p90)" :label="t('gov.quality.kpiCoverageLabel')" :hint="t('gov.quality.kpiCoverageHint')" />
        <KpiTile label-first :value="report?.los?.mae !== undefined ? valueText(report.los.mae, 'days') : '—'" :label="t('gov.quality.kpiLosLabel')" :hint="report?.los?.mae_baseline !== undefined ? t('gov.quality.ruleHint', { v: valueText(report.los.mae_baseline, 'days') }) : t('gov.quality.notMeasured')" />
      </KpiRow>

      <AppCard :title="t('gov.quality.modelsTitle')" origin="ml">
        <p class="caption card-lead">{{ t('gov.quality.modelsLead') }}</p>
        <div class="table-wrap">
          <table class="dense-table models" data-testid="quality-models">
            <thead><tr><th>{{ t('gov.quality.colModel') }}</th><th>{{ t('gov.quality.colAccuracy') }}</th><th>{{ t('gov.quality.colRule') }}</th><th>{{ t('gov.quality.colCompare') }}</th><th>{{ t('gov.quality.colStatus') }}</th></tr></thead>
            <tbody>
              <tr v-for="m in models" :key="m.key">
                <td><div class="name">{{ modelName(m.key) }}</div><div class="caption">{{ t(`gov.quality.model.${baseKey(m.key)}Task`) }}</div></td>
                <td :title="m.metric">{{ accuracyText(m) }}</td>
                <td class="muted">{{ m.baseline !== null ? valueText(m.baseline, m.unit) : '—' }}</td>
                <td><StatusTag :value="compare(m.model, m.baseline, m.lowerIsBetter).text" :tone="compare(m.model, m.baseline, m.lowerIsBetter).tone" /></td>
                <td><StatusTag :value="t('gov.quality.status.' + m.status)" :tone="STATUS_TONES[m.status]" /></td>
              </tr>
            </tbody>
          </table>
        </div>
        <p class="caption" style="margin: 12px 0 0">{{ t('gov.quality.modelsNote') }}</p>
      </AppCard>

      <AppCard :title="t('gov.quality.slicesTitle')" origin="ml" class="block">
        <p class="caption card-lead">{{ t('gov.quality.slicesLead') }}</p>
        <div class="toolbar list-toolbar">
          <SelectButton v-model="sliceBy" :options="sliceOptions" option-label="label" option-value="value" :allow-empty="false" size="small" />
          <span class="list-count">{{ t('gov.quality.slicesWorse', { n: worseCount, total: sliceAll.length }) }}</span>
          <span class="spacer" />
          <Select v-model="sliceFilter" :options="sliceFilterOptions" option-label="label" option-value="value" class="f-select" :aria-label="t('gov.quality.filterLabel')" />
          <IconField class="search-field">
            <InputIcon class="pi pi-search" />
            <InputText v-model="sliceSearch" :placeholder="sliceBy === 'region' ? t('gov.quality.searchRegion') : t('gov.quality.searchProfile')" :aria-label="t('gov.quality.filterLabel')" />
          </IconField>
        </div>
        <p v-if="!sliceRows.length" class="muted">{{ t('gov.quality.slicesEmpty') }}</p>
        <template v-else>
          <div class="table-wrap paged-box">
            <table class="dense-table">
              <thead><tr><th>{{ sliceBy === 'region' ? t('common.region') : t('common.profile') }}</th><th class="num">{{ t('gov.quality.colReferrals') }}</th><th class="num">{{ t('gov.quality.colModelErr') }}</th><th class="num">{{ t('gov.quality.colRuleErr') }}</th><th>{{ t('gov.quality.colCompare') }}</th></tr></thead>
              <tbody>
                <tr v-for="row in slicePaged" :key="row.region_kato ?? row.profile_code ?? rowName(row)">
                  <td>{{ rowName(row) }}</td>
                  <td class="num">{{ num(row.n) }}</td>
                  <td class="num">{{ valueText(row.mae_p50, 'days') }}</td>
                  <td class="num muted">{{ valueText(row.mae_p50_baseline, 'days') }}</td>
                  <td><StatusTag :value="compare(row.mae_p50, row.mae_p50_baseline).text" :tone="compare(row.mae_p50, row.mae_p50_baseline).tone" /></td>
                </tr>
              </tbody>
            </table>
          </div>
          <ArrowPager v-model:page="slicePage" :total="sliceRows.length" :size="SLICE_PAGE" />
        </template>
      </AppCard>
    </template>

    <div v-if="report" class="grid-2 block">
      <AppCard :title="t('gov.quality.forecastsTitle')" origin="ml">
        <p class="caption card-lead">{{ t('gov.quality.forecastsLead') }}</p>
        <div class="table-wrap">
          <table class="dense-table">
            <thead><tr><th>{{ t('gov.quality.colStream') }}</th><th class="num">{{ t('gov.quality.colSeriesPlain') }}</th><th>{{ t('gov.quality.colCompare') }}</th><th class="num">{{ t('gov.quality.colFlatPlain') }}</th></tr></thead>
            <tbody>
              <tr v-for="s in streams" :key="s.id">
                <td>{{ streamTitle(s.id) }}<div v-if="s.skipped" class="caption">{{ t('gov.quality.streamSkipped') }}</div></td>
                <td class="num">{{ s.series ?? '—' }}</td>
                <td><StatusTag :value="s.cmp.text" :tone="s.cmp.tone" /></td>
                <td class="num">{{ s.flat !== null ? pct(s.flat) : '—' }}</td>
              </tr>
            </tbody>
          </table>
        </div>
        <p class="caption" style="margin: 12px 0 0">{{ t('gov.quality.flatPlain') }}</p>
      </AppCard>

      <AppCard :title="t('gov.quality.anomaliesTitlePlain')" origin="ml">
        <p class="caption card-lead">{{ t('gov.quality.anomaliesLead') }}</p>
        <div class="table-wrap">
          <table class="dense-table">
            <thead><tr><th>{{ t('gov.quality.colStream') }}</th><th class="num">{{ t('gov.quality.colAlerts') }}</th><th class="num">{{ t('gov.quality.colRecall') }}</th></tr></thead>
            <tbody>
              <tr v-for="a in anomalyRows" :key="a.id"><td>{{ streamTitle(a.id) }}</td><td class="num">{{ a.alerts !== null ? num(a.alerts) : '—' }}</td><td class="num">{{ a.recall !== null ? pct(a.recall) : '—' }}</td></tr>
            </tbody>
          </table>
        </div>
        <p class="caption" style="margin: 12px 0 0">{{ t('gov.quality.labelsPlain', { n: labelledTotal }) }}</p>
      </AppCard>
    </div>

    <CollapsibleSection v-if="report" :title="t('gov.quality.techTitle')" :summary="t('gov.quality.techSummary')" class="block">
      <div class="tech">
        <section>
          <h3>{{ t('gov.quality.techMetrics') }}</h3>
          <div class="table-wrap">
            <table class="dense-table">
              <thead><tr><th>{{ t('gov.quality.colModel') }}</th><th>{{ t('gov.quality.colKind') }}</th><th>{{ t('gov.quality.colMetric') }}</th><th class="num">{{ t('gov.quality.colModelShort') }}</th><th class="num">{{ t('gov.quality.colRuleShort') }}</th></tr></thead>
              <tbody>
                <tr v-for="m in models" :key="m.key"><td>{{ modelName(m.key) }}</td><td class="muted">{{ t(`gov.quality.model.${baseKey(m.key)}Kind`) }}</td><td class="muted">{{ m.metric }}</td><td class="num">{{ m.model !== null ? fmt(m.model, 3) : '—' }}</td><td class="num">{{ m.baseline !== null ? fmt(m.baseline, 3) : '—' }}</td></tr>
                <tr v-if="tt"><td>{{ t('gov.quality.model.wait') }}</td><td class="muted">{{ t('gov.quality.model.waitKind') }}</td><td class="muted">{{ t('gov.quality.metric.pinball') }}</td><td class="num">{{ fmt(tt.pinball_p50, 3) }}</td><td class="num">{{ fmt(tt.pinball_p50_baseline, 3) }}</td></tr>
              </tbody>
            </table>
          </div>
        </section>
        <section>
          <h3>{{ t('gov.quality.techStreams') }}</h3>
          <p v-for="s in streams" :key="s.id" class="caption">{{ streamTitle(s.id) }}: {{ s.choice ? Object.entries(s.choice).map(([m, n]) => `${m} ${n}`).join(' · ') : (s.skipped ?? '—') }}</p>
        </section>
        <section class="notes">
          <h3>{{ t('gov.quality.techNotes') }}</h3>
          <p v-if="report.wait" class="caption">{{ t('gov.quality.waitTrained', { through: report.wait.trainedThrough, rows: num(report.wait.trainRows ?? 0) }) }}</p>
          <p v-if="report.los" class="caption">{{ t('gov.quality.losTrained', { train: num(report.los.train_rows ?? 0), test: num(report.los.test_rows ?? 0) }) }}</p>
          <p v-if="report.survival" class="caption">{{ t('gov.quality.survivalExplain') }} {{ report.survival.note }}</p>
          <p v-if="report.simulate" class="caption">{{ t('gov.simulator.title') }}: {{ pct(report.simulate.saved_share) }} — {{ t('gov.quality.savedShare', { horizon: report.simulate.horizon_days, lo: pct(report.simulate.saved_share_band?.[0]), hi: pct(report.simulate.saved_share_band?.[1]) }) }}; {{ t('gov.quality.spearman') }}: {{ report.simulate.consistency_spearman?.toFixed(2) ?? '—' }}. {{ t('gov.quality.simulateCaveat') }}</p>
          <p class="caption">{{ t('gov.quality.syntheticSpikes') }} {{ t('gov.quality.labelledExplain') }}</p>
          <p v-if="report.anomalyLabelsModel" class="caption">
            {{ t('gov.quality.retrainTitle') }}:
            <template v-if="report.anomalyLabelsModel.skipped">{{ report.anomalyLabelsModel.skipped }} — {{ t('gov.quality.retrainSkippedHint') }}</template>
            <template v-else>CV-AUC {{ report.anomalyLabelsModel.auc_cv }} {{ t('gov.map.vsNaive') }} {{ report.anomalyLabelsModel.auc_baseline_abs_score }} {{ t('gov.quality.rankingByScore') }}.</template>
          </p>
          <p v-if="wuenicLine" class="caption">{{ wuenicLine }}</p>
          <p class="caption">{{ t('gov.quality.weeklyMissing') }}</p>
          <div class="labels"><OriginTag kind="ml" /><OriginTag kind="formula" /><OriginTag kind="ai" /></div>
          <p class="caption">{{ t('gov.quality.labelsRule') }}</p>
        </section>
      </div>
    </CollapsibleSection>
  </PageShell>
</template>

<style scoped>
.page-legend { display: flex; margin-top: 8px; }
.card-lead { margin: -4px 0 14px; line-height: 1.5; }
.block { margin-top: var(--dm-space-4); }
.name { font-weight: var(--fw-bold); }
.models td { vertical-align: middle; }
.list-toolbar { margin-bottom: 12px; row-gap: 8px; gap: 12px; }
.list-count { color: var(--text-secondary); }
.spacer { flex: 1; }
.f-select { min-width: 220px; }
.search-field { flex: 0 1 320px; min-width: 220px; }
.search-field :deep(.p-inputtext) { width: 100%; }
.paged-box { min-height: 420px; }
.grid-2 { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: var(--dm-space-4); align-items: start; }
.tech { display: flex; flex-direction: column; gap: 20px; }
.tech h3 { margin: 0 0 8px; font-size: var(--dm-text-md); }
.tech p { margin: 0 0 6px; line-height: 1.5; }
.labels { display: flex; gap: 10px; flex-wrap: wrap; margin: 8px 0; }
@media (max-width: 1000px) { .grid-2 { grid-template-columns: 1fr; } }
</style>
