<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { analytics, refdata as refdataApi } from '@/api/endpoints'
import type { QualityBreakdownRow, QualityReport, VaccinationBenchmark } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import AppCard from '@/components/ui/AppCard.vue'
import BarPair from '@/components/ui/BarPair.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import PageShell from '@/components/ui/PageShell.vue'
import Skeleton from '@/components/ui/Skeleton.vue'
import StatusTag from '@/components/ui/StatusTag.vue'
import { useLocaleFormat } from '@/composables/useLocaleFormat'
import { pct } from '@/lib/format'
import { useRefdataStore } from '@/stores/refdata'

/** Качество моделей: KPI «модель против baseline» с мини-полосами, таблицы срезов с полосами-дельтами
 * (красным — где модель хуже), карточки с итоговой строкой; без отчёта обучения — карточка «make eval». */
const STREAM_IDS = ['admissions_monthly', 'er_visits_daily', 'rx_weekly', 'vac_monthly', 'onco_monthly', 'lab_estimate_monthly']
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
/** Выигрыш к ошибке baseline: отрицательный — модель лучше. */
function gain(model: number, baseline: number): string {
  if (!baseline) return '—'
  const share = 1 - model / baseline
  return `${share >= 0 ? '−' : '+'}${Math.abs(share * 100).toFixed(0)} %`
}
const breakdowns = computed(() => [
  { key: 'region', title: t('gov.quality.errorByRegion'), hint: t('gov.quality.errorByRegionHint'), column: t('common.region'), rows: report.value?.wait?.by_region ?? [] },
  { key: 'profile', title: t('gov.quality.errorByProfile'), hint: t('gov.quality.errorByProfileHint'), column: t('common.profile'), rows: report.value?.wait?.by_profile ?? [] },
])
/** Доля плоских рядов по всем потокам, взвешенная числом рядов. */
const flatShare = computed(() => {
  const rows = Object.values(report.value?.forecasts ?? {}).filter((f) => f.flat_share !== undefined && f.series)
  const series = rows.reduce((s, f) => s + (f.series ?? 0), 0)
  return series ? rows.reduce((s, f) => s + (f.flat_share ?? 0) * (f.series ?? 0), 0) / series : null
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
  <PageShell :title="t('gov.quality.title')" :lead="t('gov.quality.lead')" :as-of="report?.wait?.trainedThrough">
    <ErrorBox :error="error" />
    <AppCard v-if="loading"><Skeleton kind="kpi" /><Skeleton :lines="4" style="margin-top: 12px" /></AppCard>
    <AppCard v-else-if="!report?.wait">
      <EmptyState :title="t('gov.quality.noReportTitle')" :text="t('gov.quality.noReportText')" icon="pi pi-verified"><code>make eval</code></EmptyState>
    </AppCard>

    <template v-if="report?.wait">
      <AppCard :title="t('gov.quality.waitTitle')" origin="ml" data-testid="quality-kpis">
        <template #header><span class="muted small">{{ t('gov.quality.waitTrained', { through: report.wait.trainedThrough, rows: num(report.wait.trainRows) }) }}</span></template>
        <div v-if="report.wait.test_time" class="kpi">
          <div class="item">
            <div class="value">{{ report.wait.test_time.pinball_p50.toFixed(2) }} <span class="muted vs">/ {{ report.wait.test_time.pinball_p50_baseline.toFixed(2) }}</span></div>
            <BarPair :model="report.wait.test_time.pinball_p50" :baseline="report.wait.test_time.pinball_p50_baseline" />
            <div class="label">{{ t('gov.quality.pinballModelBaseline') }} · {{ gain(report.wait.test_time.pinball_p50, report.wait.test_time.pinball_p50_baseline) }} {{ t('gov.quality.toError') }}</div>
          </div>
          <div class="item">
            <div class="value">{{ report.wait.test_time.coverage_p90.toFixed(3) }} <span class="muted vs">/ 0.900</span></div>
            <BarPair :model="report.wait.test_time.coverage_p90" :baseline="0.9" :lower-is-better="false" />
            <div class="label">{{ t('gov.quality.coverageP90') }}</div>
          </div>
          <div class="item">
            <div class="value">{{ report.wait.test_time.auc_refusal.toFixed(2) }} <span class="muted vs">/ {{ report.wait.test_time.auc_refusal_baseline.toFixed(2) }}</span></div>
            <BarPair :model="report.wait.test_time.auc_refusal" :baseline="report.wait.test_time.auc_refusal_baseline" :lower-is-better="false" />
            <div class="label">{{ t('gov.quality.aucRefusal') }}</div>
          </div>
          <div v-if="report.wait.test_mo" class="item">
            <div class="value">{{ report.wait.test_mo.pinball_p50.toFixed(2) }} <span class="muted vs">/ {{ report.wait.test_mo.pinball_p50_baseline.toFixed(2) }}</span></div>
            <BarPair :model="report.wait.test_mo.pinball_p50" :baseline="report.wait.test_mo.pinball_p50_baseline" />
            <div class="label">{{ t('gov.quality.pinballOutOfSample') }}</div>
          </div>
        </div>
      </AppCard>

      <div class="grid cols-2">
        <AppCard v-for="b in breakdowns" :key="b.key" :title="b.title">
          <p class="muted small">{{ b.hint }}</p>
          <table class="dense-table">
            <thead><tr><th>{{ b.column }}</th><th class="num">n</th><th>{{ t('gov.quality.modelVsBaseline') }}</th><th class="num">Δ</th></tr></thead>
            <tbody>
              <tr v-for="row in b.rows" :key="row.region_kato ?? row.profile_code ?? rowName(row)">
                <td>{{ rowName(row) }}</td>
                <td class="num muted">{{ num(row.n) }}</td>
                <td class="bar-cell"><BarPair :model="row.pinball_p50" :baseline="row.pinball_p50_baseline" /><span class="muted small tabular">{{ row.pinball_p50.toFixed(2) }} / {{ row.pinball_p50_baseline.toFixed(2) }}</span></td>
                <td class="num" :class="worse(row) ? 'delta-up' : 'delta-down'">{{ gain(row.pinball_p50, row.pinball_p50_baseline) }}</td>
              </tr>
            </tbody>
          </table>
        </AppCard>
      </div>
    </template>

    <template v-if="report">
      <AppCard :title="t('gov.quality.forecastsTitle')" origin="ml">
        <template #header><span v-if="flatShare !== null" class="muted small">{{ t('gov.quality.flatTotal', { share: pct(flatShare) }) }}</span></template>
        <table class="dense-table">
          <thead><tr><th>{{ t('gov.quality.colStream') }}</th><th class="num">{{ t('gov.quality.colSeries') }}</th><th>{{ t('gov.quality.colMase') }}</th><th>{{ t('gov.quality.colChoice') }}</th><th class="num">{{ t('gov.quality.colFlat') }}</th></tr></thead>
          <tbody>
            <tr v-for="(f, id) in report.forecasts" :key="id">
              <td>{{ streamTitle(String(id)) }}</td>
              <td class="num">{{ f.series ?? '—' }}</td>
              <td>
                <template v-if="f.models && f.chosen && f.baseline">
                  <span class="tabular">{{ f.models[f.chosen]?.mase.toFixed(2) }} / {{ f.models[f.baseline]?.mase.toFixed(2) }}</span>
                  <StatusTag v-if="(f.models[f.chosen]?.mase ?? 1) <= (f.models[f.baseline]?.mase ?? 1)" :value="t('gov.quality.betterThanNaive')" tone="ok" style="margin-left: 6px" />
                  <StatusTag v-else :value="t('gov.quality.worseThanNaive')" tone="danger" style="margin-left: 6px" />
                </template>
                <span v-else class="muted">{{ f.skipped ?? '—' }}</span>
              </td>
              <td class="muted small">{{ f.per_series_choice ? Object.entries(f.per_series_choice).map(([m, n]) => `${m}: ${n}`).join(' · ') : '—' }}</td>
              <td class="num">{{ f.flat_share !== undefined ? pct(f.flat_share) : '—' }}</td>
            </tr>
          </tbody>
        </table>
        <p class="muted small" style="margin-top: 8px">{{ t('gov.quality.flatExplain') }}</p>
      </AppCard>

      <div class="grid cols-2">
        <AppCard :title="t('gov.quality.anomaliesTitle')" origin="formula">
          <template #header><span class="muted small">{{ t('gov.quality.labelledBy') }}: {{ labelledTotal(report.anomalyLabels) }} {{ t('gov.quality.signalsShort') }}</span></template>
          <div v-for="(a, id) in report.anomalies" :key="id" class="factor">
            <span>{{ streamTitle(String(id)) }}</span>
            <span class="contribution">{{ a.alerts ?? '—' }} {{ t('gov.quality.alertsShort') }} · {{ t('gov.quality.recall') }} {{ a.recall_at_threshold !== undefined ? pct(a.recall_at_threshold) : '—' }}</span>
          </div>
          <p class="muted small" style="margin-top: 8px">{{ t('gov.quality.syntheticSpikes') }}</p>
          <p class="muted small">
            <template v-if="labelledTotal(report.anomalyLabels) > 0">{{ Object.entries(report.anomalyLabels ?? {}).map(([s, n]) => `${s}: ${n}`).join(' · ') }} — </template>{{ t('gov.quality.labelledExplain') }}
          </p>
          <p v-if="report.anomalyLabelsModel" class="muted small">
            {{ t('gov.quality.retrainTitle') }}:
            <template v-if="report.anomalyLabelsModel.skipped">{{ report.anomalyLabelsModel.skipped }} — {{ t('gov.quality.retrainSkippedHint') }}</template>
            <template v-else>CV-AUC {{ report.anomalyLabelsModel.auc_cv }} {{ t('gov.map.vsNaive') }} {{ report.anomalyLabelsModel.auc_baseline_abs_score }} {{ t('gov.quality.rankingByScore') }}.</template>
          </p>
          <p v-if="wuenicLine" class="muted small">{{ wuenicLine }}</p>
        </AppCard>

        <AppCard v-if="report.simulate" :title="t('gov.simulator.title')" origin="formula">
          <div class="kpi">
            <div class="item"><div class="value">{{ pct(report.simulate.saved_share) }}</div><div class="label">{{ t('gov.quality.savedShare', { horizon: report.simulate.horizon_days, lo: pct(report.simulate.saved_share_band?.[0]), hi: pct(report.simulate.saved_share_band?.[1]) }) }}</div></div>
            <div class="item"><div class="value">{{ report.simulate.consistency_spearman?.toFixed(2) ?? '—' }}</div><div class="label">{{ t('gov.quality.spearman') }}</div></div>
          </div>
          <p class="muted small" style="margin-top: 8px">{{ t('gov.quality.simulateCaveat') }}</p>
        </AppCard>

        <AppCard v-if="report.survival?.splits" :title="t('gov.quality.survivalTitle')" origin="ml">
          <div class="kpi">
            <div v-if="report.survival.splits.test_time" class="item">
              <div class="value">{{ report.survival.splits.test_time.c_index.toFixed(3) }} <span class="muted vs">/ {{ report.survival.splits.test_time.c_index_baseline.toFixed(3) }}</span></div>
              <BarPair :model="report.survival.splits.test_time.c_index" :baseline="report.survival.splits.test_time.c_index_baseline" :lower-is-better="false" />
              <div class="label">{{ t('gov.quality.cIndex') }}</div>
            </div>
            <div v-if="report.survival.splits.test_mo" class="item">
              <div class="value">{{ report.survival.splits.test_mo.c_index.toFixed(3) }} <span class="muted vs">/ {{ report.survival.splits.test_mo.c_index_baseline.toFixed(3) }}</span></div>
              <BarPair :model="report.survival.splits.test_mo.c_index" :baseline="report.survival.splits.test_mo.c_index_baseline" :lower-is-better="false" />
              <div class="label">{{ t('gov.quality.cIndexOutOfSample') }}</div>
            </div>
            <div v-if="report.survival.splits.test_time?.p_admit_mean?.['30'] !== undefined" class="item">
              <div class="value">{{ pct(report.survival.splits.test_time.p_admit_mean?.['30'] ?? 0) }} <span class="muted vs">/ {{ pct(report.survival.splits.test_time.observed_share?.['30'] ?? 0) }}</span></div>
              <div class="label">{{ t('gov.quality.pAdmit30') }}</div>
            </div>
          </div>
          <p class="muted small" style="margin-top: 8px">{{ t('gov.quality.survivalExplain') }} {{ report.survival.note }}.</p>
        </AppCard>

        <AppCard v-if="report.los" :title="t('gov.quality.losTitle')" origin="ml">
          <div class="kpi">
            <div class="item">
              <div class="value">{{ report.los.pinball_p50?.toFixed(2) }} <span class="muted vs">/ {{ report.los.pinball_p50_baseline?.toFixed(2) }}</span></div>
              <BarPair :model="report.los.pinball_p50 ?? 0" :baseline="report.los.pinball_p50_baseline ?? 0" />
              <div class="label">{{ t('gov.quality.pinballModelBaseline') }} · {{ gain(report.los.pinball_p50 ?? 0, report.los.pinball_p50_baseline ?? 0) }} {{ t('gov.quality.toError') }}</div>
            </div>
            <div class="item"><div class="value">{{ report.los.mae?.toFixed(2) }} <span class="muted vs">/ {{ report.los.mae_baseline?.toFixed(2) }}</span></div><div class="label">{{ t('gov.quality.maeDays') }}</div></div>
            <div class="item"><div class="value">{{ num(report.los.cells) }}</div><div class="label">{{ t('gov.quality.losCells') }}</div></div>
          </div>
          <p class="muted small" style="margin-top: 8px">{{ t('gov.quality.losTrained', { train: num(report.los.train_rows), test: num(report.los.test_rows) }) }}</p>
        </AppCard>
      </div>
    </template>
  </PageShell>
</template>

<style scoped>
.vs { font-size: var(--dm-text-sm); font-weight: 400; letter-spacing: 0; }
.kpi .item .label { margin-top: 6px; }
.bar-cell { min-width: 200px; }
</style>
