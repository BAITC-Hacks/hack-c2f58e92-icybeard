<script setup lang="ts">
import Tag from 'primevue/tag'
import { onMounted, ref } from 'vue'
import { analytics } from '@/api/endpoints'
import type { QualityBreakdownRow, QualityReport } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import { pct } from '@/lib/format'
import { useRefdataStore } from '@/stores/refdata'

const refdata = useRefdataStore()
const report = ref<QualityReport | null>(null)
const error = ref<unknown>(null)

const streamTitles: Record<string, string> = {
  admissions_monthly: 'Госпитализации, помесячно',
  er_visits_daily: 'Приёмные покои, по дням',
  rx_weekly: 'Рецепты, по неделям',
  vac_monthly: 'Вакцинация, помесячно',
  onco_monthly: 'Онкология: впервые выявленные, помесячно',
  lab_estimate_monthly: 'Лаборатории (оценка), помесячно',
}

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
  return `${share >= 0 ? '−' : '+'}${Math.abs(share * 100).toFixed(0)} % к ошибке`
}

onMounted(async () => {
  await refdata.load()
  try {
    report.value = await analytics.quality()
  } catch (e) {
    error.value = e
  }
})
</script>

<template>
  <main class="page">
    <h1>Качество моделей</h1>
    <p class="lead">
      Метрики из отчётов обучения (make train / make eval): модель против простого правила на отложенной выборке.
      Это тот же источник, что цитируют карточки моделей и презентация.
    </p>
    <ErrorBox :error="error" />

    <template v-if="report?.wait">
      <div class="card">
        <h2>Ожидание и риск отказа (LightGBM)</h2>
        <p class="muted">Обучение по {{ report.wait.trainedThrough }}, {{ report.wait.trainRows?.toLocaleString('ru-RU') }} направлений; проверка — март 2025 и 10 % организаций вне обучения.</p>
        <div v-if="report.wait.test_time" class="kpi" style="margin-top: 10px">
          <div class="item">
            <div class="value">{{ report.wait.test_time.pinball_p50.toFixed(2) }} <span class="muted">/ {{ report.wait.test_time.pinball_p50_baseline.toFixed(2) }}</span></div>
            <div class="label">пинбол p50, модель / baseline ({{ gain(report.wait.test_time.pinball_p50, report.wait.test_time.pinball_p50_baseline) }})</div>
          </div>
          <div class="item">
            <div class="value">{{ report.wait.test_time.coverage_p90.toFixed(3) }}</div>
            <div class="label">покрытие интервала p90 (цель 0.900)</div>
          </div>
          <div class="item">
            <div class="value">{{ report.wait.test_time.auc_refusal.toFixed(2) }} <span class="muted">/ {{ report.wait.test_time.auc_refusal_baseline.toFixed(2) }}</span></div>
            <div class="label">AUC отказа, модель / baseline</div>
          </div>
          <div class="item" v-if="report.wait.test_mo">
            <div class="value">{{ report.wait.test_mo.pinball_p50.toFixed(2) }} <span class="muted">/ {{ report.wait.test_mo.pinball_p50_baseline.toFixed(2) }}</span></div>
            <div class="label">пинбол p50 на организациях вне обучения</div>
          </div>
        </div>
      </div>

      <div class="grid cols-2" style="margin-top: 16px">
        <div class="card">
          <h2>Ошибка по регионам</h2>
          <p class="muted">Пинбол p50 модели против baseline, март 2025. Красным — регионы, где модель хуже простого правила.</p>
          <div v-for="row in report.wait.by_region ?? []" :key="row.region_kato" class="factor">
            <span>{{ rowName(row) }} <span class="muted">· {{ row.n.toLocaleString('ru-RU') }}</span></span>
            <span class="contribution" :class="worse(row) ? 'minus' : 'plus'">{{ row.pinball_p50.toFixed(2) }} / {{ row.pinball_p50_baseline.toFixed(2) }}</span>
          </div>
        </div>
        <div class="card">
          <h2>Ошибка по профилям</h2>
          <p class="muted">Те же метрики по профилям коек: видно, где модели не хватает данных.</p>
          <div v-for="row in report.wait.by_profile ?? []" :key="row.profile_code" class="factor">
            <span>{{ rowName(row) }} <span class="muted">· {{ row.n.toLocaleString('ru-RU') }}</span></span>
            <span class="contribution" :class="worse(row) ? 'minus' : 'plus'">{{ row.pinball_p50.toFixed(2) }} / {{ row.pinball_p50_baseline.toFixed(2) }}</span>
          </div>
        </div>
      </div>
    </template>

    <div v-if="report" class="card" style="margin-top: 16px">
      <h2>Прогнозы потоков</h2>
      <table style="width: 100%; border-collapse: collapse">
        <thead>
          <tr class="muted" style="text-align: left">
            <th style="padding: 6px 4px">Поток</th><th>Рядов</th><th>MASE / наив</th><th>Выбор моделей по рядам</th><th>Плоские</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="(f, id) in report.forecasts" :key="id" style="border-top: 1px solid var(--darumen-border)">
            <td style="padding: 8px 4px">{{ streamTitles[id] ?? id }}</td>
            <td>{{ f.series ?? '—' }}</td>
            <td>
              <template v-if="f.models && f.chosen && f.baseline">
                {{ f.models[f.chosen]?.mase.toFixed(2) }} / {{ f.models[f.baseline]?.mase.toFixed(2) }}
                <Tag v-if="(f.models[f.chosen]?.mase ?? 1) <= (f.models[f.baseline]?.mase ?? 1)" value="лучше наива" severity="success" style="margin-left: 6px" />
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
      <p class="muted" style="margin-top: 8px">«Плоские» — доля рядов, где прогноз повторяет один уровень («уровень последнего месяца»); такие ряды подписаны на графиках.</p>
    </div>

    <div v-if="report" class="grid cols-2" style="margin-top: 16px">
      <div class="card">
        <h2>Аномалии</h2>
        <div v-for="(a, id) in report.anomalies" :key="id" class="factor">
          <span>{{ streamTitles[id] ?? id }}</span>
          <span class="contribution">{{ a.alerts ?? '—' }} сигн. · полнота {{ a.recall_at_threshold !== undefined ? pct(a.recall_at_threshold) : '—' }}</span>
        </div>
        <p class="muted" style="margin-top: 8px">Проверка на подсаженных всплесках ×3.</p>
        <p class="muted" style="margin-top: 4px">
          Разметка людьми: {{ labelledTotal(report.anomalyLabels) }} сигналов
          <template v-if="labelledTotal(report.anomalyLabels) > 0">
            ({{ Object.entries(report.anomalyLabels ?? {}).map(([s, n]) => `${s}: ${n}`).join(' · ') }})
          </template>
          — каждое подтверждение из журнала становится меткой, на которой детектор получит измеримую точность.
        </p>
      </div>
      <div class="card" v-if="report.simulate">
        <h2>Симулятор</h2>
        <div class="kpi">
          <div class="item">
            <div class="value">{{ pct(report.simulate.saved_share) }}</div>
            <div class="label">экономия дней ожидания за {{ report.simulate.horizon_days }} дней (интервал {{ pct(report.simulate.saved_share_band?.[0]) }}…{{ pct(report.simulate.saved_share_band?.[1]) }})</div>
          </div>
          <div class="item">
            <div class="value">{{ report.simulate.consistency_spearman?.toFixed(2) ?? '—' }}</div>
            <div class="label">Спирмен с фактическим ожиданием (порог 0.5)</div>
          </div>
        </div>
        <p class="muted" style="margin-top: 8px">Сценарии корректно сравнивать между собой; абсолютные дни модель занижает — это ограничение написано в карточке.</p>
      </div>
    </div>
  </main>
</template>
