<script setup lang="ts">
import { BarChart, LineChart } from 'echarts/charts'
import { GridComponent, LegendComponent, TooltipComponent } from 'echarts/components'
import { use } from 'echarts/core'
import { CanvasRenderer } from 'echarts/renderers'
import Button from 'primevue/button'
import InputText from 'primevue/inputtext'
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import VChart from 'vue-echarts'
import { insight } from '@/api/endpoints'
import type { AskResponse, Chart, InsightStatus } from '@/api/types'
import { ApiError } from '@/api/client'
import AppCard from '@/components/ui/AppCard.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import PageShell from '@/components/ui/PageShell.vue'
import SearchSelect from '@/components/ui/SearchSelect.vue'
import { useChartTheme } from '@/composables/useChartTheme'
import { useLocaleFormat } from '@/composables/useLocaleFormat'
import { downloadCsv } from '@/lib/csv'
import { num } from '@/lib/format'
import { useRefdataStore } from '@/stores/refdata'

use([CanvasRenderer, LineChart, BarChart, GridComponent, TooltipComponent, LegendComponent])

/** Вопросы к данным (W-Insight): карточка вопроса (поле, регион, «Спросить», примеры), если модель не запущена —
 * понятное объяснение вместо ошибки; ответ (текст ИИ, график, таблица данных с CSV, «Откуда взяты данные» —
 * человеческие названия инструментов) и справа история вопросов этой сессии и «Как это работает». */
interface Turn { question: string; at: string; ms?: number; answer?: AskResponse; error?: unknown }
const STEPS = ['parse', 'tools', 'answer'] as const
const STEP_MS = 1500

const { t, tm } = useI18n()
const { dateTime } = useLocaleFormat()
const refdata = useRefdataStore()
const question = ref('')
const region = ref<string | null>(null)
const turns = ref<Turn[]>([])
const current = ref<Turn | null>(null)
const busy = ref(false)
const step = ref(0)
const status = ref<InsightStatus | null>(null)
let stepTimer = 0

/** Эталонные вопросы — чипы под полем; tm — сырое сообщение (t() трактует «|» как формы числа). */
const examples = computed(() => String(tm('gov.insight.examples')).split('|').map((q) => q.trim()).filter(Boolean))
const regionOptions = computed(() => [{ regionKato: '', name: t('gov.insight.allRegions') }, ...refdata.regions])
/** Модель настроена и (для локальной Ollama) отвечает; пока статус не получен — считаем доступной. */
const available = computed(() => status.value?.available !== false && status.value?.reachable !== false)
const checking = ref(false)
const TOOL_KEYS = ['access_index', 'regions', 'bed_profiles', 'organizations', 'queue_state', 'predict_wait', 'anomalies', 'forecast', 'simulate', 'medicines_check']
const toolName = (tool: string) => (TOOL_KEYS.includes(tool) ? t(`gov.insight.tool.${tool}`) : tool)
/** Ошибка ответа словами: 503 — модель не отвечает, 429 — слишком часто, остальное — общая фраза. */
function errorText(error: unknown): { title: string; detail?: string } {
  if (error instanceof ApiError && error.status === 503) return { title: t('gov.insight.errorOffline'), detail: error.detail }
  if (error instanceof ApiError && error.status === 429) return { title: t('gov.insight.errorRate') }
  return { title: t('gov.insight.errorGeneric'), detail: error instanceof Error ? error.message : undefined }
}
async function checkStatus() {
  checking.value = true
  try {
    status.value = await insight.status()
  } catch {
    status.value = null
  } finally {
    checking.value = false
  }
}
const answer = computed(() => current.value?.answer ?? null)
/** Табличный результат — из графика ответа: строки x, колонки — ряды. */
const table = computed(() => {
  const chart = answer.value?.chart
  if (!chart) return null
  return { columns: chart.series.map((s) => s.name), rows: chart.x.map((x, i) => ({ x, values: chart.series.map((s) => s.data[i] ?? null) })) }
})

const { base: chartBase, axis: chartAxis, theme } = useChartTheme()
function chartOption(chart: Chart) {
  return {
    ...chartBase.value,
    tooltip: { trigger: 'axis' },
    legend: { ...chartBase.value.legend, data: chart.series.map((s) => s.name) },
    grid: { left: 48, right: 16, top: 36, bottom: chart.type === 'bar' ? 90 : 40 },
    xAxis: { type: 'category', data: chart.x, ...chartAxis.value, axisLabel: { ...chartAxis.value.axisLabel, rotate: chart.type === 'bar' ? 45 : 0, fontSize: 10 } },
    yAxis: { type: 'value', ...chartAxis.value },
    series: chart.series.map((s, i) => ({ name: s.name, type: chart.type, data: s.data, showSymbol: false, itemStyle: { color: i === 0 ? theme.value.series : theme.value.palette[i % theme.value.palette.length] }, lineStyle: ['прогноз', 'болжам'].includes(s.name) ? { type: 'dashed', color: theme.value.forecast } : undefined })),
  }
}

async function ask(text = question.value) {
  const q = text.trim()
  if (!q || busy.value) return
  const turn: Turn = { question: q, at: new Date().toISOString() }
  current.value = turn
  question.value = q
  busy.value = true
  step.value = 0
  stepTimer = window.setInterval(() => (step.value = Math.min(step.value + 1, STEPS.length - 1)), STEP_MS)
  const started = performance.now()
  let done: Turn
  try {
    const response = await insight.ask(q, region.value || undefined)
    done = { ...turn, answer: response, ms: performance.now() - started }
  } catch (e) {
    done = { ...turn, error: e }
    if (e instanceof ApiError && e.status === 503) void checkStatus()
  }
  window.clearInterval(stepTimer)
  busy.value = false
  current.value = done
  turns.value = [done, ...turns.value].slice(0, 20)
}

function show(turn: Turn) {
  current.value = turn
  question.value = turn.question
}

function exportCsv() {
  if (!table.value) return
  const { columns, rows } = table.value
  downloadCsv('insight-result.csv', rows.map((r) => Object.fromEntries([['x', r.x], ...columns.map((c, i) => [c, r.values[i]])])))
}

onMounted(async () => {
  await refdata.load().catch(() => undefined)
  await checkStatus()
})
onBeforeUnmount(() => window.clearInterval(stepTimer))
</script>

<template>
  <PageShell :title="t('gov.insight.title')">
    <template #subtitle>{{ t('gov.insight.subtitlePlain') }}</template>

    <div v-if="status && !available" class="offline card" role="status">
      <i class="pi pi-power-off offline-icon" aria-hidden="true" />
      <div class="offline-body">
        <div class="offline-title">{{ t('gov.insight.offlineTitle') }}</div>
        <p>{{ t('gov.insight.offlineText') }}</p>
      </div>
      <Button :label="t('gov.insight.checkAgain')" icon="pi pi-refresh" severity="secondary" size="small" :loading="checking" @click="checkStatus" />
    </div>

    <div class="ask-block card">
      <div class="ask-grid">
        <div class="field grow">
          <label for="insight-q">{{ t('gov.insight.questionLabel') }}</label>
          <InputText id="insight-q" v-model="question" :placeholder="t('gov.insight.askPlaceholder')" :disabled="!available" data-testid="insight-question" @keydown.enter.prevent="ask()" />
        </div>
        <div class="field region">
          <label>{{ t('gov.insight.regionLabel') }}</label>
          <SearchSelect v-model="region" :options="regionOptions" option-label="name" option-value="regionKato" :placeholder="t('gov.insight.allRegions')" />
        </div>
        <Button class="ask-btn" :label="t('gov.insight.ask')" icon="pi pi-send" :loading="busy" :disabled="!available || !question.trim()" data-testid="insight-ask" @click="ask()" />
      </div>
      <div class="examples">
        <span class="caption">{{ t('gov.insight.examplesLabel') }}</span>
        <div class="chips">
          <button v-for="q in examples" :key="q" type="button" class="chip-filter" :disabled="busy || !available" @click="ask(q)">{{ q }}</button>
        </div>
      </div>
    </div>

    <div class="main-grid">
      <AppCard :title="t('gov.insight.answerTitle')" origin="ai" :origin-note="t('gov.insight.aiNote')">
        <template #header><span v-if="answer && current?.ms" class="caption">{{ t('gov.insight.answeredIn', { s: (current.ms / 1000).toFixed(0) }) }}</span></template>
        <EmptyState v-if="!current" :title="t('gov.insight.emptyTitle')" :text="t('gov.insight.emptyTextPlain')" icon="pi pi-comments" />
        <template v-else-if="busy">
          <p class="question-echo">{{ current.question }}</p>
          <div class="steps" aria-live="polite">
            <span v-for="(s, j) in STEPS" :key="s" class="step" :class="{ done: j < step, active: j === step }"><i :class="j < step ? 'pi pi-check' : j === step ? 'pi pi-spin pi-spinner' : 'pi pi-circle'" aria-hidden="true" /> {{ t('gov.insight.stepPlain.' + s) }}</span>
          </div>
          <p class="caption">{{ t('gov.insight.waitHint') }}</p>
        </template>
        <template v-else-if="current.error">
          <p class="question-echo">{{ current.question }}</p>
          <div class="answer-error">
            <div class="strong">{{ errorText(current.error).title }}</div>
            <div v-if="errorText(current.error).detail" class="caption">{{ errorText(current.error).detail }}</div>
          </div>
        </template>
        <template v-else-if="answer">
          <p class="question-echo">{{ current.question }}</p>
          <div v-if="answer.value !== null" class="a-number tabular">{{ num(answer.value, Number.isInteger(answer.value) ? 0 : 1) }} <span class="unit">{{ answer.unit ?? '' }}</span></div>
          <p class="a-text" data-testid="insight-answer">{{ answer.answer }}</p>
          <template v-if="answer.chart">
            <div class="section-title">{{ answer.chart.title }}</div>
            <VChart class="chart a-chart" :option="chartOption(answer.chart)" autoresize />
          </template>
          <template v-if="table">
            <div class="section-head">
              <span class="section-title">{{ t('gov.insight.dataTitle') }}</span>
              <button type="button" class="link-arrow small" @click="exportCsv">{{ t('shell.exportCsv') }}</button>
            </div>
            <div class="table-wrap data-table">
              <table class="dense-table">
                <thead><tr><th></th><th v-for="c in table.columns" :key="c" class="num">{{ c }}</th></tr></thead>
                <tbody>
                  <tr v-for="r in table.rows" :key="r.x"><td>{{ r.x }}</td><td v-for="(v, i) in r.values" :key="i" class="num">{{ v === null ? '—' : num(v, Number.isInteger(v) ? 0 : 1) }}</td></tr>
                </tbody>
              </table>
            </div>
          </template>
          <div class="sources">
            <span class="section-title">{{ t('gov.insight.sourcesTitle') }}</span>
            <div v-if="answer.toolsUsed.length" class="chips"><span v-for="tool in answer.toolsUsed" :key="tool" class="source-chip">{{ toolName(tool) }}</span></div>
            <p v-else class="muted small">{{ t('gov.insight.noSources') }}</p>
          </div>
          <p class="caption footnote">{{ t('gov.insight.footnotePlain') }}</p>
        </template>
      </AppCard>

      <div class="col">
        <AppCard :title="t('gov.insight.previous')">
          <p v-if="turns.length === 0" class="muted small">{{ t('gov.insight.noPrevious') }}</p>
          <div v-else class="rows history">
            <button v-for="turn in turns" :key="turn.at" type="button" class="row row-button" :class="{ active: turn === current }" @click="show(turn)">
              <span class="row-main">{{ turn.question }}</span>
              <span class="caption">{{ dateTime(turn.at) }}</span>
            </button>
          </div>
        </AppCard>
        <AppCard :title="t('gov.insight.howTitle')">
          <ul class="how">
            <li>{{ t('gov.insight.how1') }}</li>
            <li>{{ t('gov.insight.how2') }}</li>
            <li>{{ t('gov.insight.how3') }}</li>
          </ul>
        </AppCard>
      </div>
    </div>
  </PageShell>
</template>

<style scoped>
.offline { display: flex; gap: 16px; align-items: flex-start; border: 1px solid var(--dm-hairline); }
.offline-icon { font-size: 20px; color: var(--text-secondary); margin-top: 2px; }
.offline-body { flex: 1; min-width: 0; }
.offline-title { font-weight: var(--fw-bold); font-size: var(--dm-text-md); }
.offline-body p { margin: 4px 0 0; line-height: 1.5; }
.offline-tech { margin-top: 10px; color: var(--text-secondary); font-size: var(--dm-text-sm); }
.offline-tech summary { cursor: pointer; }
.offline-tech pre { background: var(--surface-muted); border-radius: 8px; padding: 8px 12px; margin: 8px 0 0; font-size: 13px; white-space: pre-wrap; }
.ask-block { display: flex; flex-direction: column; gap: 16px; }
.ask-grid { display: grid; grid-template-columns: minmax(0, 1fr) 260px auto; gap: 12px; align-items: end; }
.field { display: flex; flex-direction: column; gap: 6px; min-width: 0; }
.field label { font-size: var(--dm-text-sm); color: var(--text-secondary); }
.field :deep(.p-inputtext), .field :deep(.p-select) { width: 100%; }
.examples { display: flex; flex-direction: column; gap: 8px; }
.main-grid { display: grid; grid-template-columns: minmax(0, 1.7fr) minmax(0, 1fr); gap: var(--dm-space-4); align-items: start; }
.col { display: flex; flex-direction: column; gap: var(--dm-space-4); min-width: 0; }
.question-echo { margin: 0 0 12px; font-size: var(--dm-text-md); font-weight: var(--fw-bold); }
.a-number { font-size: var(--dm-text-kpi); font-weight: var(--fw-extrabold); letter-spacing: -0.02em; line-height: 1; margin: 4px 0 8px; }
.a-number .unit { font-size: var(--dm-text-base); color: var(--dm-muted); font-weight: 400; }
.a-text { white-space: pre-wrap; margin: 0 0 16px; font-size: var(--dm-text-base); line-height: 1.55; }
.a-chart { height: 260px; }
.section-title { font-weight: var(--fw-bold); display: block; margin: 12px 0 8px; }
.section-head { display: flex; align-items: baseline; justify-content: space-between; gap: 12px; border-top: 1px solid var(--dm-hairline); margin-top: 12px; }
.data-table { max-height: 320px; overflow-y: auto; }
.sources { border-top: 1px solid var(--dm-hairline); margin-top: 12px; }
.source-chip { display: inline-flex; padding: 4px 12px; border-radius: 999px; background: var(--surface-muted); font-size: var(--dm-text-sm); }
.footnote { margin: 12px 0 0; }
.answer-error { background: var(--surface-muted); border-radius: 12px; padding: 12px 16px; display: flex; flex-direction: column; gap: 4px; }
.strong { font-weight: var(--fw-bold); }
.steps { display: flex; gap: 20px; flex-wrap: wrap; color: var(--dm-muted); margin-bottom: 8px; }
.step.active { color: var(--dm-ink); font-weight: var(--fw-bold); }
.step.done { color: var(--dm-ok); }
.history { max-height: 360px; overflow-y: auto; }
.row-button { width: 100%; background: none; border: 0; border-bottom: 1px solid var(--dm-hairline); font: inherit; color: inherit; text-align: left; cursor: pointer; padding: 12px 0; }
.row-button:last-child { border-bottom: 0; }
.row-button.active .row-main, .row-button:hover .row-main { color: var(--dm-accent-hover); }
.how { margin: 0; padding-left: 18px; display: flex; flex-direction: column; gap: 8px; line-height: 1.5; color: var(--text-secondary); }
@media (max-width: 1000px) {
  .main-grid { grid-template-columns: 1fr; }
  .ask-grid { grid-template-columns: 1fr; }
}
</style>
