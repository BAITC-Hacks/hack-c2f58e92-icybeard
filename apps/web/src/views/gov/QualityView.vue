<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { analytics, refdata as refdataApi } from '@/api/endpoints'
import type { QualityBreakdownRow, QualityReport, VaccinationBenchmark } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import OriginTag from '@/components/OriginTag.vue'
import AppCard from '@/components/ui/AppCard.vue'
import BarPair from '@/components/ui/BarPair.vue'
import CollapsibleSection from '@/components/ui/CollapsibleSection.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import KpiRow from '@/components/ui/KpiRow.vue'
import KpiTile from '@/components/ui/KpiTile.vue'
import PageShell from '@/components/ui/PageShell.vue'
import Skeleton from '@/components/ui/Skeleton.vue'
import StatusTag from '@/components/ui/StatusTag.vue'
import { useLocaleFormat } from '@/composables/useLocaleFormat'
import { pct } from '@/lib/format'
import { useRefdataStore } from '@/stores/refdata'

/** Качество моделей (W-Quality): четыре KPI «модель / ориентир», сводная таблица «Модели в продукте» по /quality
 * (ожидание, риск отказа, LOS, survival, прогнозы потоков, аномалии, скрайб), карточка «Что помечено и как»;
 * срезы по регионам/профилям и остальные отчёты — свёрнутой секцией. Ряда ошибки по неделям в отчёте нет. */
interface ModelRow { key: string; metric: string; model: number | null; baseline: number | null; lowerIsBetter: boolean; period: string; status: 'prod' | 'check' | 'draft'; format: (v: number) => string }
const STREAM_IDS = ['admissions_monthly', 'er_visits_daily', 'rx_weekly', 'vac_monthly', 'onco_monthly', 'lab_estimate_monthly']
const STATUS_TONES = { prod: 'ok', check: 'warn', draft: 'accent' } as const
const { t } = useI18n()
const { num } = useLocaleFormat()
const refdata = useRefdataStore()
const report = ref<QualityReport | null>(null)
const vaccination = ref<VaccinationBenchmark[]>([])
const error = ref<unknown>(null)
const loading = ref(true)

const wuenicLine = computed(() => {
  const latest = (vaccine: string) => vaccination.value.filter((v) => v.vaccine === vaccine).at(-1)
  const dtp3 = latest('DTP3')
  const mcv1 = latest('MCV1')
  return dtp3 && mcv1 ? t('gov.quality.wuenic', { year: dtp3.year, dtp3: dtp3.coveragePct.toFixed(0), mcv1: mcv1.coveragePct.toFixed(0) }) : ''
})
const streamTitle = (id: string) => (STREAM_IDS.includes(id) ? t(`gov.quality.stream.${id}`) : id)
const labelledTotal = (labels?: Record<string, number>) => Object.values(labels ?? {}).reduce((s, n) => s + n, 0)
const worse = (row: QualityBreakdownRow) => row.pinball_p50 > row.pinball_p50_baseline
const rowName = (row: QualityBreakdownRow) => (row.region_kato ? refdata.regionName(row.region_kato) : row.profile_code ? refdata.profileName(row.profile_code) : '—')
/** Выигрыш к ориентиру в процентах (положительный — модель лучше). */
function gainPct(model: number, baseline: number, lowerIsBetter = true): number | null {
  if (!baseline) return null
  return Math.round((lowerIsBetter ? 1 - model / baseline : model / baseline - 1) * 100)
}
const gainText = (model: number | null, baseline: number | null, lowerIsBetter = true) => {
  if (model === null || baseline === null) return t('gov.quality.noBaseline')
  const g = gainPct(model, baseline, lowerIsBetter)
  return g === null ? t('gov.quality.noBaseline') : g >= 0 ? t('gov.quality.betterBy', { pct: g }) : t('gov.quality.worseBy', { pct: -g })
}
const through = computed(() => report.value?.wait?.trainedThrough?.slice(0, 10) ?? '')
const breakdowns = computed(() => [
  { key: 'region', title: t('gov.quality.errorByRegion'), hint: t('gov.quality.errorByRegionHint'), column: t('common.region'), rows: report.value?.wait?.by_region ?? [] },
  { key: 'profile', title: t('gov.quality.errorByProfile'), hint: t('gov.quality.errorByProfileHint'), column: t('common.profile'), rows: report.value?.wait?.by_profile ?? [] },
])

/** Сводная таблица моделей — только из полей отчёта; чего в отчёте нет, то «нет в отчёте». */
const models = computed<ModelRow[]>(() => {
  const r = report.value
  if (!r) return []
  const tt = r.wait?.test_time
  const surv = r.survival?.splits?.test_time
  const f2 = (v: number) => v.toFixed(2)
  const period = through.value ? t('gov.quality.periodThrough', { through: through.value }) : t('gov.quality.periodNone')
  const status = (m: number | null, b: number | null, lower = true): ModelRow['status'] => (m === null || b === null ? 'check' : (lower ? m <= b : m >= b) ? 'prod' : 'check')
  const rows: ModelRow[] = [
    { key: 'wait', metric: t('gov.quality.metric.pinball'), model: tt?.pinball_p50 ?? null, baseline: tt?.pinball_p50_baseline ?? null, lowerIsBetter: true, period, status: status(tt?.pinball_p50 ?? null, tt?.pinball_p50_baseline ?? null), format: f2 },
    { key: 'refusal', metric: t('gov.quality.metric.auc'), model: tt?.auc_refusal ?? null, baseline: tt?.auc_refusal_baseline ?? null, lowerIsBetter: false, period, status: status(tt?.auc_refusal ?? null, tt?.auc_refusal_baseline ?? null, false), format: f2 },
    { key: 'los', metric: t('gov.quality.metric.mae'), model: r.los?.mae ?? null, baseline: r.los?.mae_baseline ?? null, lowerIsBetter: true, period: r.los?.test_window?.replace(/ 00:00:00/g, '') ?? t('gov.quality.periodNone'), status: status(r.los?.mae ?? null, r.los?.mae_baseline ?? null), format: f2 },
    { key: 'survival', metric: t('gov.quality.metric.cindex'), model: surv?.c_index ?? null, baseline: surv?.c_index_baseline ?? null, lowerIsBetter: false, period, status: status(surv?.c_index ?? null, surv?.c_index_baseline ?? null, false), format: (v) => v.toFixed(3) },
  ]
  for (const [id, f] of Object.entries(r.forecasts)) {
    const m = f.models && f.chosen ? (f.models[f.chosen]?.mase ?? null) : null
    const b = f.models && f.baseline ? (f.models[f.baseline]?.mase ?? null) : null
    rows.push({ key: `forecast:${id}`, metric: t('gov.quality.metric.mase'), model: m, baseline: b, lowerIsBetter: true, period, status: status(m, b), format: f2 })
  }
  const recall = Object.values(r.anomalies).map((a) => a.recall_at_threshold).filter((v): v is number => v !== undefined)
  rows.push({ key: 'anomaly', metric: t('gov.quality.metric.recall'), model: recall.length ? recall.reduce((s, v) => s + v, 0) / recall.length : null, baseline: null, lowerIsBetter: false, period, status: 'check', format: (v) => pct(v) })
  rows.push({ key: 'scribe', metric: t('gov.quality.metric.manual'), model: null, baseline: null, lowerIsBetter: false, period: t('gov.quality.periodNone'), status: 'draft', format: f2 })
  return rows
})
const baseKey = (key: string) => (key.startsWith('forecast:') ? 'forecast' : key)
const modelName = (key: string) => (key.startsWith('forecast:') ? `${t('gov.quality.model.forecast')}: ${streamTitle(key.slice(9))}` : t(`gov.quality.model.${key}`))

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
    <template #subtitle>{{ t('gov.quality.subtitle', { through: through || '—' }) }}</template>
    <ErrorBox :error="error" />
    <AppCard v-if="loading"><Skeleton kind="kpi" /><Skeleton :lines="4" style="margin-top: 12px" /></AppCard>
    <AppCard v-else-if="!report?.wait">
      <EmptyState :title="t('gov.quality.noReportTitle')" :text="t('gov.quality.noReportText')" icon="pi pi-verified"><code>make eval</code></EmptyState>
    </AppCard>

    <template v-if="report?.wait?.test_time">
      <KpiRow data-testid="quality-kpis">
        <KpiTile :value="`± ${report.wait.test_time.pinball_p50.toFixed(2)}`" :unit="t('common.days')" :label="t('gov.quality.kpiWaitError', { baseline: report.wait.test_time.pinball_p50_baseline.toFixed(2) })" origin="ml" :chip="gainText(report.wait.test_time.pinball_p50, report.wait.test_time.pinball_p50_baseline)" chip-tone="ok" />
        <KpiTile :value="report.wait.test_time.auc_refusal.toFixed(2)" :label="t('gov.quality.kpiAuc', { baseline: report.wait.test_time.auc_refusal_baseline.toFixed(2) })" origin="ml" :chip="gainText(report.wait.test_time.auc_refusal, report.wait.test_time.auc_refusal_baseline, false)" chip-tone="ok" />
        <KpiTile :value="report.wait.test_time.coverage_p90.toFixed(3)" :label="t('gov.quality.kpiCoverage')" origin="ml" />
        <KpiTile :value="report.los?.mae !== undefined ? report.los.mae.toFixed(2) : '—'" :label="t('gov.quality.kpiLos', { baseline: report.los?.mae_baseline?.toFixed(2) ?? '—' })" origin="ml" :hint="report.los ? undefined : t('gov.quality.periodNone')" />
      </KpiRow>

      <AppCard :title="t('gov.quality.modelsTitle')" origin="ml">
        <template #header><span class="caption">{{ t('gov.quality.modelsCaption') }}</span></template>
        <div class="table-wrap">
          <table class="dense-table" data-testid="quality-models">
            <thead><tr><th>{{ t('gov.quality.colModel') }}</th><th>{{ t('gov.quality.colTask') }}</th><th>{{ t('gov.quality.colMetric') }}</th><th>{{ t('gov.quality.colVsNaive') }}</th><th>{{ t('gov.quality.colPeriod') }}</th><th>{{ t('gov.quality.colStatus') }}</th></tr></thead>
            <tbody>
              <tr v-for="m in models" :key="m.key">
                <td><span class="strong">{{ modelName(m.key) }}</span><div class="caption">{{ t(`gov.quality.model.${baseKey(m.key)}Kind`) }}</div></td>
                <td class="muted">{{ t(`gov.quality.model.${baseKey(m.key)}Task`) }}</td>
                <td class="muted">{{ m.metric }}</td>
                <td class="tabular">
                  <template v-if="m.model !== null"><span class="strong">{{ m.format(m.model) }}</span> / {{ m.baseline !== null ? m.format(m.baseline) : '—' }} <span class="caption">· {{ gainText(m.model, m.baseline, m.lowerIsBetter) }}</span><BarPair v-if="m.baseline !== null" :model="m.model" :baseline="m.baseline" :lower-is-better="m.lowerIsBetter" class="pair" /></template>
                  <span v-else class="muted">{{ t('gov.quality.periodNone') }}</span>
                </td>
                <td class="caption">{{ m.period }}</td>
                <td><StatusTag :value="t('gov.quality.status.' + m.status)" :tone="STATUS_TONES[m.status]" /></td>
              </tr>
            </tbody>
          </table>
        </div>
        <p class="caption" style="margin: 12px 0 0">{{ t('gov.quality.weeklyMissing') }} {{ t('gov.quality.waitTrained', { through: report.wait.trainedThrough, rows: num(report.wait.trainRows) }) }}</p>
        <div class="labels-block">
          <div class="eyebrow">{{ t('gov.quality.labelsTitle') }}</div>
          <div class="labels"><OriginTag kind="ml" /><OriginTag kind="formula" /><OriginTag kind="ai" /></div>
          <p class="muted small" style="margin: 10px 0 0">{{ t('gov.quality.labelsRule') }}</p>
        </div>
      </AppCard>
    </template>

    <CollapsibleSection v-if="report" :title="t('gov.quality.details')" origin="ml">
      <div class="grid cols-2">
        <section v-for="b in breakdowns" :key="b.key" class="sub">
          <h3>{{ b.title }}</h3>
          <p class="caption">{{ b.hint }}</p>
          <table class="dense-table">
            <thead><tr><th>{{ b.column }}</th><th class="num">n</th><th>{{ t('gov.quality.modelVsBaseline') }}</th><th class="num">Δ</th></tr></thead>
            <tbody>
              <tr v-for="row in b.rows" :key="row.region_kato ?? row.profile_code ?? rowName(row)">
                <td>{{ rowName(row) }}</td>
                <td class="num muted">{{ num(row.n) }}</td>
                <td class="bar-cell"><BarPair :model="row.pinball_p50" :baseline="row.pinball_p50_baseline" /><span class="caption tabular">{{ row.pinball_p50.toFixed(2) }} / {{ row.pinball_p50_baseline.toFixed(2) }}</span></td>
                <td class="num" :class="worse(row) ? 'delta-up' : 'delta-down'">{{ gainText(row.pinball_p50, row.pinball_p50_baseline) }}</td>
              </tr>
            </tbody>
          </table>
        </section>
        <section class="sub">
          <h3>{{ t('gov.quality.forecastsTitle') }}</h3>
          <table class="dense-table">
            <thead><tr><th>{{ t('gov.quality.colStream') }}</th><th class="num">{{ t('gov.quality.colSeries') }}</th><th>{{ t('gov.quality.colChoice') }}</th><th class="num">{{ t('gov.quality.colFlat') }}</th></tr></thead>
            <tbody>
              <tr v-for="(f, id) in report.forecasts" :key="id">
                <td>{{ streamTitle(String(id)) }}</td>
                <td class="num">{{ f.series ?? '—' }}</td>
                <td class="caption">{{ f.per_series_choice ? Object.entries(f.per_series_choice).map(([m, n]) => `${m}: ${n}`).join(' · ') : (f.skipped ?? '—') }}</td>
                <td class="num">{{ f.flat_share !== undefined ? pct(f.flat_share) : '—' }}</td>
              </tr>
            </tbody>
          </table>
          <p class="caption">{{ t('gov.quality.flatExplain') }}</p>
        </section>
        <section class="sub">
          <h3>{{ t('gov.quality.anomaliesTitle') }}</h3>
          <div v-for="(a, id) in report.anomalies" :key="id" class="factor small">
            <span>{{ streamTitle(String(id)) }}</span>
            <span class="contribution">{{ a.alerts ?? '—' }} {{ t('gov.quality.alertsShort') }} · {{ t('gov.quality.recall') }} {{ a.recall_at_threshold !== undefined ? pct(a.recall_at_threshold) : '—' }}</span>
          </div>
          <p class="caption">{{ t('gov.quality.syntheticSpikes') }} {{ t('gov.quality.labelledBy') }}: {{ labelledTotal(report.anomalyLabels) }} {{ t('gov.quality.signalsShort') }} — {{ t('gov.quality.labelledExplain') }}</p>
          <p v-if="report.anomalyLabelsModel" class="caption">
            {{ t('gov.quality.retrainTitle') }}:
            <template v-if="report.anomalyLabelsModel.skipped">{{ report.anomalyLabelsModel.skipped }} — {{ t('gov.quality.retrainSkippedHint') }}</template>
            <template v-else>CV-AUC {{ report.anomalyLabelsModel.auc_cv }} {{ t('gov.map.vsNaive') }} {{ report.anomalyLabelsModel.auc_baseline_abs_score }} {{ t('gov.quality.rankingByScore') }}.</template>
          </p>
          <p v-if="wuenicLine" class="caption">{{ wuenicLine }}</p>
          <p v-if="report.simulate" class="caption">{{ t('gov.simulator.title') }}: {{ pct(report.simulate.saved_share) }} — {{ t('gov.quality.savedShare', { horizon: report.simulate.horizon_days, lo: pct(report.simulate.saved_share_band?.[0]), hi: pct(report.simulate.saved_share_band?.[1]) }) }}; {{ t('gov.quality.spearman') }}: {{ report.simulate.consistency_spearman?.toFixed(2) ?? '—' }}. {{ t('gov.quality.simulateCaveat') }}</p>
          <p v-if="report.survival" class="caption">{{ t('gov.quality.survivalExplain') }} {{ report.survival.note }}</p>
          <p v-if="report.los" class="caption">{{ t('gov.quality.losTrained', { train: num(report.los.train_rows), test: num(report.los.test_rows) }) }}</p>
        </section>
      </div>
    </CollapsibleSection>
  </PageShell>
</template>

<style scoped>
.strong { font-weight: var(--fw-bold); }
.pair { display: flex; margin-top: 4px; max-width: 120px; }
.labels-block { border-top: 1px solid var(--border); margin-top: 14px; padding-top: 14px; }
.labels { display: flex; gap: 10px; flex-wrap: wrap; margin-top: 8px; }
.sub h3 { margin: 0 0 4px; }
.bar-cell { min-width: 180px; }
</style>
