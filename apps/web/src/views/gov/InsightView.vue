<script setup lang="ts">
import { BarChart, LineChart } from 'echarts/charts'
import { GridComponent, LegendComponent, TooltipComponent } from 'echarts/components'
import { use } from 'echarts/core'
import { CanvasRenderer } from 'echarts/renderers'
import Button from 'primevue/button'
import InputText from 'primevue/inputtext'
import Message from 'primevue/message'
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import VChart from 'vue-echarts'
import { insight } from '@/api/endpoints'
import type { AskResponse, Chart, InsightStatus } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import AppCard from '@/components/ui/AppCard.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import PageShell from '@/components/ui/PageShell.vue'
import SearchSelect from '@/components/ui/SearchSelect.vue'
import StatusTag from '@/components/ui/StatusTag.vue'
import { useChartTheme } from '@/composables/useChartTheme'
import { useLocaleFormat } from '@/composables/useLocaleFormat'
import { downloadCsv } from '@/lib/csv'
import { num } from '@/lib/format'
import { useRefdataStore } from '@/stores/refdata'

use([CanvasRenderer, LineChart, BarChart, GridComponent, TooltipComponent, LegendComponent])

/** Вопросы к данным (W-Insight): регион пилюлей, поле вопроса с «Спросить» и чипы-примеры; слева «Ответ» (чип AI,
 * число, текст, график, «Вызванные инструменты» с гарантиями only-gold / без persona / лимит), справа «Предыдущие
 * вопросы» этой сессии и «Результат запроса» — таблица из графика ответа с экспортом CSV. SQL API не отдаёт:
 * показываются инструменты, которые вызвала модель. */
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
const available = computed(() => status.value?.available !== false)
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
  try {
    status.value = await insight.status()
  } catch {
    status.value = null
  }
})
onBeforeUnmount(() => window.clearInterval(stepTimer))
</script>

<template>
  <PageShell :title="t('gov.insight.title')">
    <template #subtitle>{{ t('gov.insight.subtitle') }}</template>
    <template #actions>
      <SearchSelect v-model="region" :options="regionOptions" option-label="name" option-value="regionKato" size="small" :placeholder="t('gov.insight.allRegions')" />
    </template>
    <Message v-if="status && !status.available" severity="warn" :closable="false">{{ t('gov.insight.unavailable', { provider: status.provider, model: status.model }) }}</Message>

    <div class="ask-block">
      <div class="field">
        <label>{{ t('gov.insight.question') }}</label>
        <div class="ask-row">
          <InputText v-model="question" :placeholder="t('gov.insight.askPlaceholder')" :disabled="!available" data-testid="insight-question" @keydown.enter.prevent="ask()" />
          <Button :label="t('gov.insight.ask')" :loading="busy" :disabled="!available || !question.trim()" data-testid="insight-ask" @click="ask()" />
        </div>
      </div>
      <div class="chips">
        <button v-for="q in examples" :key="q" type="button" class="chip-filter" :disabled="busy || !available" @click="ask(q)">{{ q }}</button>
      </div>
    </div>

    <div class="main-grid">
      <AppCard :title="t('gov.insight.answerTitle')" origin="ai" :origin-note="t('gov.insight.aiNote')">
        <template #header><span v-if="answer" class="caption">{{ answer.model }}<template v-if="current?.ms"> · {{ t('gov.insight.seconds', { s: (current.ms / 1000).toFixed(1) }) }}</template></span></template>
        <EmptyState v-if="!current" :title="t('gov.insight.emptyTitle')" :text="t('gov.insight.emptyText')" icon="pi pi-comments" />
        <template v-else-if="busy">
          <p class="question-echo">{{ current.question }}</p>
          <div class="steps" aria-live="polite">
            <span v-for="(s, j) in STEPS" :key="s" class="step" :class="{ done: j < step, active: j === step }"><i :class="j < step ? 'pi pi-check' : 'pi pi-circle'" aria-hidden="true" /> {{ t('gov.insight.step.' + s) }}</span>
          </div>
        </template>
        <ErrorBox v-else-if="current.error" :error="current.error" />
        <template v-else-if="answer">
          <p class="question-echo">{{ current.question }}</p>
          <div v-if="answer.value !== null" class="a-number tabular">{{ num(answer.value, Number.isInteger(answer.value) ? 0 : 1) }} <span class="unit">{{ answer.unit ?? '' }}</span></div>
          <p class="a-text" data-testid="insight-answer">{{ answer.answer }}</p>
          <template v-if="answer.chart">
            <p class="caption">{{ answer.chart.title }}</p>
            <VChart class="chart a-chart" :option="chartOption(answer.chart)" autoresize />
          </template>
          <div class="eyebrow tools-title">{{ t('gov.insight.toolsCalled') }}</div>
          <div class="rows">
            <div v-for="tool in answer.toolsUsed" :key="tool" class="row tool-row"><span class="mono">{{ tool }}</span><span class="caption">{{ answer.sources.filter((s) => s.includes(tool)).join(' · ') }}</span></div>
            <p v-if="!answer.toolsUsed.length" class="muted small">{{ t('gov.insight.noToolsCalled') }}</p>
          </div>
          <div class="chips guarantees">
            <StatusTag :value="t('gov.insight.guarantee.gold')" tone="ok" />
            <StatusTag :value="t('gov.insight.guarantee.persona')" tone="ok" />
            <StatusTag :value="t('gov.insight.guarantee.limit')" tone="ok" />
          </div>
          <p class="caption">{{ t('gov.insight.footnote', { model: answer.model }) }}</p>
        </template>
      </AppCard>

      <div class="col">
        <AppCard :title="t('gov.insight.previous')">
          <p v-if="turns.length === 0" class="muted small">{{ t('gov.insight.noPrevious') }}</p>
          <div v-else class="rows">
            <button v-for="turn in turns" :key="turn.at" type="button" class="row row-button" :class="{ active: turn === current }" @click="show(turn)">
              <span class="row-main">{{ turn.question }}</span>
              <span class="caption">{{ dateTime(turn.at) }}</span>
            </button>
          </div>
        </AppCard>

        <AppCard :title="t('gov.insight.resultTitle')" origin="formula">
          <template #header><button v-if="table" type="button" class="link-arrow small" @click="exportCsv">{{ t('shell.exportCsv') }}</button></template>
          <p v-if="!answer" class="muted small">{{ t('gov.insight.sourcesEmpty') }}</p>
          <p v-else-if="!table" class="muted small">{{ t('gov.insight.resultEmpty') }}</p>
          <div v-else class="table-wrap">
            <table class="dense-table">
              <thead><tr><th></th><th v-for="c in table.columns" :key="c" class="num">{{ c }}</th></tr></thead>
              <tbody>
                <tr v-for="r in table.rows" :key="r.x"><td>{{ r.x }}</td><td v-for="(v, i) in r.values" :key="i" class="num">{{ v === null ? '—' : num(v, Number.isInteger(v) ? 0 : 1) }}</td></tr>
              </tbody>
            </table>
          </div>
        </AppCard>
      </div>
    </div>
  </PageShell>
</template>

<style scoped>
.ask-block { display: flex; flex-direction: column; gap: 12px; }
.ask-row { display: flex; gap: 12px; align-items: center; }
.ask-row :deep(.p-inputtext) { flex: 1; background: var(--dm-surface); }
.main-grid { display: grid; grid-template-columns: minmax(0, 1.4fr) minmax(0, 1fr); gap: var(--dm-space-4); align-items: start; }
.col { display: flex; flex-direction: column; gap: var(--dm-space-4); min-width: 0; }
.question-echo { margin: 0 0 8px; font-size: var(--dm-text-md); color: var(--dm-muted); }
.a-number { font-size: var(--dm-text-kpi); font-weight: 500; letter-spacing: -0.02em; line-height: 1; margin: 4px 0 8px; }
.a-number .unit { font-size: var(--dm-text-base); color: var(--dm-muted); font-weight: 400; }
.a-text { white-space: pre-wrap; margin: 0 0 12px; font-size: var(--dm-text-base); }
.a-chart { height: 260px; }
.tools-title { border-top: 1px solid var(--dm-hairline); padding-top: 12px; margin-top: 8px; }
.tool-row { min-height: 40px; }
.guarantees { margin: 12px 0; }
.steps { display: flex; gap: 16px; flex-wrap: wrap; color: var(--dm-muted); }
.step.active { color: var(--dm-ink); font-weight: 500; }
.step.done { color: var(--dm-ok); }
.row-button { width: 100%; background: none; border: 0; border-bottom: 1px solid var(--dm-hairline); font: inherit; color: inherit; text-align: left; cursor: pointer; padding: 12px 0; }
.row-button:last-child { border-bottom: 0; }
.row-button.active .row-main, .row-button:hover .row-main { color: var(--dm-accent-hover); }
@media (max-width: 1000px) { .main-grid { grid-template-columns: 1fr; } }
</style>
