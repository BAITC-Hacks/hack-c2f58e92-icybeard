<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { analytics, refdata as refdataApi } from '@/api/endpoints'
import type { QualityBreakdownRow, QualityReport, VaccinationBenchmark } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import { pct } from '@/lib/format'
import { useRefdataStore } from '@/stores/refdata'
import { useLocaleFormat } from '@/composables/useLocaleFormat'
import PageShell from '@/components/ui/PageShell.vue'
import StatusTag from '@/components/ui/StatusTag.vue'

const { t } = useI18n()
const { num } = useLocaleFormat()
const refdata = useRefdataStore()
const report = ref<QualityReport | null>(null)
const vaccination = ref<VaccinationBenchmark[]>([])
const error = ref<unknown>(null)

/** Свежайший год WUENIC по ключевым вакцинам — контекст для сигналов вакцинации. */
const wuenicLine = computed(() => {
  const latest = (vaccine: string) => vaccination.value.filter((v) => v.vaccine === vaccine).at(-1)
  const dtp3 = latest('DTP3')
  const mcv1 = latest('MCV1')
  if (!dtp3 || !mcv1) return ''
  return t('gov.quality.wuenic', { year: dtp3.year, dtp3: dtp3.coveragePct.toFixed(0), mcv1: mcv1.coveragePct.toFixed(0) })
})

const streamTitles = computed<Record<string, string>>(() => ({
  admissions_monthly: t('gov.quality.stream.admissions_monthly'),
  er_visits_daily: t('gov.quality.stream.er_visits_daily'),
  rx_weekly: t('gov.quality.stream.rx_weekly'),
  vac_monthly: t('gov.quality.stream.vac_monthly'),
  onco_monthly: t('gov.quality.stream.onco_monthly'),
  lab_estimate_monthly: t('gov.quality.stream.lab_estimate_monthly'),
}))

/** Всего сигналов, размеченных людьми (подтверждено + закрыто и т.д.). */
function labelledTotal(labels?: Record<string, number>): number {
  return Object.values(labels ?? {}).reduce((s, n) => s + n, 0)
}

/** Модель хуже baseline в этом срезе — подсветка проблемного места. */
function worse(row: QualityBreakdownRow): boolean {
  return row.pinball_p50 > row.pinball_p50_baseline
}

function rowName(row: QualityBreakdownRow): string {
  if (row.region_kato) return refdata.regionName(row.region_kato)
  return row.profile_code ? refdata.profileName(row.profile_code) : '—'
}

function gain(model: number, baseline: number): string {
  if (!baseline) return '—'
  const share = 1 - model / baseline
  return `${share >= 0 ? '−' : '+'}${Math.abs(share * 100).toFixed(0)} % ${t('gov.quality.toError')}`
}

onMounted(async () => {
  await refdata.load()
  try {
    report.value = await analytics.quality()
  } catch (e) {
    error.value = e
  }
  try {
    vaccination.value = (await refdataApi.vaccination()).items
  } catch {
    // внешний ориентир опционален: без витрины строка просто не показывается
  }
})
</script>

<template>
  <PageShell :title="t('gov.quality.title')" :lead="t('gov.quality.lead')">
    <ErrorBox :error="error" />

    <template v-if="report?.wait">
      <div class="card">
        <h2>{{ t('gov.quality.waitTitle') }}</h2>
        <p class="muted">{{ t('gov.quality.waitTrained', { through: report.wait.trainedThrough, rows: num(report.wait.trainRows) }) }}</p>
        <div v-if="report.wait.test_time" class="kpi" style="margin-top: 10px">
          <div class="item">
            <div class="value">{{ report.wait.test_time.pinball_p50.toFixed(2) }} <span class="muted">/ {{ report.wait.test_time.pinball_p50_baseline.toFixed(2) }}</span></div>
            <div class="label">{{ t('gov.quality.pinballModelBaseline') }} ({{ gain(report.wait.test_time.pinball_p50, report.wait.test_time.pinball_p50_baseline) }})</div>
          </div>
          <div class="item">
            <div class="value">{{ report.wait.test_time.coverage_p90.toFixed(3) }}</div>
            <div class="label">{{ t('gov.quality.coverageP90') }}</div>
          </div>
          <div class="item">
            <div class="value">{{ report.wait.test_time.auc_refusal.toFixed(2) }} <span class="muted">/ {{ report.wait.test_time.auc_refusal_baseline.toFixed(2) }}</span></div>
            <div class="label">{{ t('gov.quality.aucRefusal') }}</div>
          </div>
          <div class="item" v-if="report.wait.test_mo">
            <div class="value">{{ report.wait.test_mo.pinball_p50.toFixed(2) }} <span class="muted">/ {{ report.wait.test_mo.pinball_p50_baseline.toFixed(2) }}</span></div>
            <div class="label">{{ t('gov.quality.pinballOutOfSample') }}</div>
          </div>
        </div>
      </div>

      <div class="grid cols-2" style="margin-top: 16px">
        <div class="card">
          <h2>{{ t('gov.quality.errorByRegion') }}</h2>
          <p class="muted">{{ t('gov.quality.errorByRegionHint') }}</p>
          <div v-for="row in report.wait.by_region ?? []" :key="row.region_kato" class="factor">
            <span>{{ rowName(row) }} <span class="muted">· {{ num(row.n) }}</span></span>
            <span class="contribution" :class="worse(row) ? 'minus' : 'plus'">{{ row.pinball_p50.toFixed(2) }} / {{ row.pinball_p50_baseline.toFixed(2) }}</span>
          </div>
        </div>
        <div class="card">
          <h2>{{ t('gov.quality.errorByProfile') }}</h2>
          <p class="muted">{{ t('gov.quality.errorByProfileHint') }}</p>
          <div v-for="row in report.wait.by_profile ?? []" :key="row.profile_code" class="factor">
            <span>{{ rowName(row) }} <span class="muted">· {{ num(row.n) }}</span></span>
            <span class="contribution" :class="worse(row) ? 'minus' : 'plus'">{{ row.pinball_p50.toFixed(2) }} / {{ row.pinball_p50_baseline.toFixed(2) }}</span>
          </div>
        </div>
      </div>
    </template>

    <div v-if="report" class="card" style="margin-top: 16px">
      <h2>{{ t('gov.quality.forecastsTitle') }}</h2>
      <table style="width: 100%; border-collapse: collapse">
        <thead>
          <tr class="muted" style="text-align: left">
            <th style="padding: 6px 4px">{{ t('gov.quality.colStream') }}</th><th>{{ t('gov.quality.colSeries') }}</th><th>{{ t('gov.quality.colMase') }}</th><th>{{ t('gov.quality.colChoice') }}</th><th>{{ t('gov.quality.colFlat') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="(f, id) in report.forecasts" :key="id" style="border-top: 1px solid var(--darumen-border)">
            <td style="padding: 8px 4px">{{ streamTitles[id] ?? id }}</td>
            <td>{{ f.series ?? '—' }}</td>
            <td>
              <template v-if="f.models && f.chosen && f.baseline">
                {{ f.models[f.chosen]?.mase.toFixed(2) }} / {{ f.models[f.baseline]?.mase.toFixed(2) }}
                <StatusTag v-if="(f.models[f.chosen]?.mase ?? 1) <= (f.models[f.baseline]?.mase ?? 1)" :value="t('gov.quality.betterThanNaive')" tone="ok" style="margin-left: 6px" />
              </template>
              <span v-else class="muted">{{ f.skipped ?? '—' }}</span>
            </td>
            <td class="muted">
              <template v-if="f.per_series_choice">
                {{ Object.entries(f.per_series_choice).map(([m, n]) => `${m}: ${n}`).join(' · ') }}
              </template>
              <span v-else>—</span>
            </td>
            <td>{{ f.flat_share !== undefined ? pct(f.flat_share) : '—' }}</td>
          </tr>
        </tbody>
      </table>
      <p class="muted" style="margin-top: 8px">{{ t('gov.quality.flatExplain') }}</p>
    </div>

    <div v-if="report" class="grid cols-2" style="margin-top: 16px">
      <div class="card">
        <h2>{{ t('gov.quality.anomaliesTitle') }}</h2>
        <div v-for="(a, id) in report.anomalies" :key="id" class="factor">
          <span>{{ streamTitles[id] ?? id }}</span>
          <span class="contribution">{{ a.alerts ?? '—' }} {{ t('gov.quality.alertsShort') }} · {{ t('gov.quality.recall') }} {{ a.recall_at_threshold !== undefined ? pct(a.recall_at_threshold) : '—' }}</span>
        </div>
        <p class="muted" style="margin-top: 8px">{{ t('gov.quality.syntheticSpikes') }}</p>
        <p class="muted" style="margin-top: 4px">
          {{ t('gov.quality.labelledBy') }}: {{ labelledTotal(report.anomalyLabels) }} {{ t('gov.quality.signalsShort') }}
          <template v-if="labelledTotal(report.anomalyLabels) > 0">
            ({{ Object.entries(report.anomalyLabels ?? {}).map(([s, n]) => `${s}: ${n}`).join(' · ') }})
          </template>
          — {{ t('gov.quality.labelledExplain') }}
        </p>
        <p v-if="report.anomalyLabelsModel" class="muted" style="margin-top: 4px">
          {{ t('gov.quality.retrainTitle') }}:
          <template v-if="report.anomalyLabelsModel.skipped">{{ report.anomalyLabelsModel.skipped }} — {{ t('gov.quality.retrainSkippedHint') }}</template>
          <template v-else>CV-AUC {{ report.anomalyLabelsModel.auc_cv }} {{ t('gov.map.vsNaive') }} {{ report.anomalyLabelsModel.auc_baseline_abs_score }} {{ t('gov.quality.rankingByScore') }}.</template>
        </p>
        <p v-if="wuenicLine" class="muted" style="margin-top: 4px">{{ wuenicLine }}</p>
      </div>
      <div class="card" v-if="report.simulate">
        <h2>{{ t('gov.simulator.title') }}</h2>
        <div class="kpi">
          <div class="item">
            <div class="value">{{ pct(report.simulate.saved_share) }}</div>
            <div class="label">{{ t('gov.quality.savedShare', { horizon: report.simulate.horizon_days, lo: pct(report.simulate.saved_share_band?.[0]), hi: pct(report.simulate.saved_share_band?.[1]) }) }}</div>
          </div>
          <div class="item">
            <div class="value">{{ report.simulate.consistency_spearman?.toFixed(2) ?? '—' }}</div>
            <div class="label">{{ t('gov.quality.spearman') }}</div>
          </div>
        </div>
        <p class="muted" style="margin-top: 8px">{{ t('gov.quality.simulateCaveat') }}</p>
      </div>
      <div class="card" v-if="report.survival?.splits">
        <h2>{{ t('gov.quality.survivalTitle') }}</h2>
        <div class="kpi">
          <div class="item" v-if="report.survival.splits.test_time">
            <div class="value">{{ report.survival.splits.test_time.c_index.toFixed(3) }} <span class="muted">/ {{ report.survival.splits.test_time.c_index_baseline.toFixed(3) }}</span></div>
            <div class="label">{{ t('gov.quality.cIndex') }}</div>
          </div>
          <div class="item" v-if="report.survival.splits.test_mo">
            <div class="value">{{ report.survival.splits.test_mo.c_index.toFixed(3) }} <span class="muted">/ {{ report.survival.splits.test_mo.c_index_baseline.toFixed(3) }}</span></div>
            <div class="label">{{ t('gov.quality.cIndexOutOfSample') }}</div>
          </div>
          <div class="item" v-if="report.survival.splits.test_time?.p_admit_mean?.['30'] !== undefined">
            <div class="value">{{ pct(report.survival.splits.test_time.p_admit_mean?.['30'] ?? 0) }} <span class="muted">/ {{ pct(report.survival.splits.test_time.observed_share?.['30'] ?? 0) }}</span></div>
            <div class="label">{{ t('gov.quality.pAdmit30') }}</div>
          </div>
        </div>
        <p class="muted" style="margin-top: 8px">{{ t('gov.quality.survivalExplain') }} {{ report.survival.note }}.</p>
      </div>
      <div class="card" v-if="report.los">
        <h2>{{ t('gov.quality.losTitle') }}</h2>
        <div class="kpi">
          <div class="item">
            <div class="value">{{ report.los.pinball_p50?.toFixed(2) }} <span class="muted">/ {{ report.los.pinball_p50_baseline?.toFixed(2) }}</span></div>
            <div class="label">{{ t('gov.quality.pinballModelBaseline') }} ({{ gain(report.los.pinball_p50 ?? 0, report.los.pinball_p50_baseline ?? 0) }})</div>
          </div>
          <div class="item">
            <div class="value">{{ report.los.mae?.toFixed(2) }} <span class="muted">/ {{ report.los.mae_baseline?.toFixed(2) }}</span></div>
            <div class="label">{{ t('gov.quality.maeDays') }}</div>
          </div>
          <div class="item">
            <div class="value">{{ num(report.los.cells) }}</div>
            <div class="label">{{ t('gov.quality.losCells') }}</div>
          </div>
        </div>
        <p class="muted" style="margin-top: 8px">{{ t('gov.quality.losTrained', { train: num(report.los.train_rows), test: num(report.los.test_rows) }) }}</p>
      </div>
    </div>
  </PageShell>
</template>
