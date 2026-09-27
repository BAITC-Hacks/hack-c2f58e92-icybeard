<script setup lang="ts">
import { BarChart, LineChart } from 'echarts/charts'
import { GridComponent, LegendComponent, TooltipComponent } from 'echarts/components'
import { use } from 'echarts/core'
import { CanvasRenderer } from 'echarts/renderers'
import Button from 'primevue/button'
import Message from 'primevue/message'
import Textarea from 'primevue/textarea'
import { computed, nextTick, onBeforeUnmount, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import VChart from 'vue-echarts'
import { insight } from '@/api/endpoints'
import type { AskResponse, Chart, InsightStatus } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import OriginTag from '@/components/OriginTag.vue'
import AppCard from '@/components/ui/AppCard.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import PageShell from '@/components/ui/PageShell.vue'
import { useChartTheme } from '@/composables/useChartTheme'
import { useLocaleFormat } from '@/composables/useLocaleFormat'
import { num } from '@/lib/format'

use([CanvasRenderer, LineChart, BarChart, GridComponent, TooltipComponent, LegendComponent])

/** Вопросы к данным в три колонки: эталонные вопросы группами, диалог с карточками-ответами (число, график,
 * инструменты), справа — какие витрины использованы. Формулировка — языковой модели, числа — из инструментов. */
interface Turn { question: string; at: string; answer?: AskResponse; error?: unknown }
const STEPS = ['parse', 'tools', 'answer'] as const
const STEP_MS = 1500

const { t, tm } = useI18n()
const { dateTime } = useLocaleFormat()
const question = ref('')
const turns = ref<Turn[]>([])
const busy = ref(false)
const step = ref(0)
const status = ref<InsightStatus | null>(null)
const thread = ref<HTMLElement | null>(null)
let stepTimer = 0

/** Группы эталонных вопросов: «Заголовок::вопрос|вопрос;Заголовок::…» из словаря; если словарь даёт только
 * заголовок, вопросы берутся из gov.insight.examples одной группой. */
const groups = computed(() => {
  // tm — сырое сообщение: t() трактует «|» как разделитель форм множественного числа
  const parsed = String(tm('gov.insight.groups'))
    .split(';')
    .map((g) => {
      const [title, questions] = g.split('::')
      return { title: title?.trim() ?? '', questions: (questions ?? '').split('|').map((q) => q.trim()).filter(Boolean) }
    })
    .filter((g) => g.questions.length)
  if (parsed.length) return parsed
  const examples = String(tm('gov.insight.examples')).split('|').map((q) => q.trim()).filter(Boolean)
  return examples.length ? [{ title: t('gov.insight.groups'), questions: examples }] : []
})
const available = computed(() => status.value?.available !== false)
/** Использованные витрины и инструменты по всем ответам — правая колонка. */
const sources = computed(() => ({
  sources: [...new Set(turns.value.flatMap((x) => x.answer?.sources ?? []))],
  tools: [...new Set(turns.value.flatMap((x) => x.answer?.toolsUsed ?? []))],
}))

const { base: chartBase, axis: chartAxis } = useChartTheme()
function chartOption(chart: Chart) {
  return {
    ...chartBase.value,
    tooltip: { trigger: 'axis' },
    legend: { ...chartBase.value.legend, data: chart.series.map((s) => s.name) },
    grid: { left: 48, right: 16, top: 36, bottom: chart.type === 'bar' ? 90 : 40 },
    xAxis: { type: 'category', data: chart.x, ...chartAxis.value, axisLabel: { ...chartAxis.value.axisLabel, rotate: chart.type === 'bar' ? 45 : 0, fontSize: 10 } },
    yAxis: { type: 'value', ...chartAxis.value },
    series: chart.series.map((s) => ({ name: s.name, type: chart.type, data: s.data, showSymbol: false, lineStyle: ['прогноз', 'болжам'].includes(s.name) ? { type: 'dashed' } : undefined })),
  }
}

async function ask(text = question.value) {
  const q = text.trim()
  if (!q || busy.value) return
  const turn: Turn = { question: q, at: new Date().toISOString() }
  turns.value = [...turns.value, turn]
  question.value = ''
  busy.value = true
  step.value = 0
  stepTimer = window.setInterval(() => (step.value = Math.min(step.value + 1, STEPS.length - 1)), STEP_MS)
  await nextTick()
  thread.value?.scrollTo({ top: thread.value.scrollHeight })
  try {
    const answer = await insight.ask(q)
    turns.value = turns.value.map((x) => (x === turn ? { ...x, answer } : x))
  } catch (e) {
    turns.value = turns.value.map((x) => (x === turn ? { ...x, error: e } : x))
  } finally {
    window.clearInterval(stepTimer)
    busy.value = false
    await nextTick()
    thread.value?.scrollTo({ top: thread.value.scrollHeight, behavior: 'smooth' })
  }
}

onMounted(async () => {
  try {
    status.value = await insight.status()
  } catch {
    status.value = null
  }
})
onBeforeUnmount(() => window.clearInterval(stepTimer))
</script>

<template>
  <PageShell :title="t('gov.insight.title')" :lead="t('gov.insight.lead')">
    <Message v-if="status && !status.available" severity="warn" :closable="false">{{ t('gov.insight.unavailable', { provider: status.provider, model: status.model }) }}</Message>
    <div class="columns">
      <AppCard :title="t('gov.insight.reference')" dense class="col-left">
        <div v-for="g in groups" :key="g.title" class="group">
          <div class="group-title">{{ g.title }}</div>
          <button v-for="q in g.questions" :key="q" type="button" class="question" :disabled="busy || !available" @click="ask(q)">{{ q }}</button>
        </div>
      </AppCard>

      <div class="col-center">
        <div ref="thread" class="thread card">
          <EmptyState v-if="turns.length === 0" :title="t('gov.insight.emptyTitle')" :text="t('gov.insight.emptyText')" icon="pi pi-comments" />
          <div v-for="(turn, i) in turns" :key="i" class="turn">
            <div class="q"><span class="bubble">{{ turn.question }}</span><span class="muted small">{{ dateTime(turn.at) }}</span></div>
            <div v-if="turn.answer" class="a card" data-testid="insight-answer">
              <div class="a-head"><OriginTag kind="ai" :note="t('gov.insight.aiNote')" /><span class="muted small">{{ turn.answer.model }}</span></div>
              <div v-if="turn.answer.value !== null" class="a-number tabular">{{ num(turn.answer.value, Number.isInteger(turn.answer.value) ? 0 : 1) }} <span class="unit">{{ turn.answer.unit ?? '' }}</span></div>
              <p class="a-text">{{ turn.answer.answer }}</p>
              <VChart v-if="turn.answer.chart" class="chart a-chart" :option="chartOption(turn.answer.chart)" autoresize />
              <p class="muted small">{{ t('gov.insight.tools') }}: {{ turn.answer.toolsUsed.join(', ') || t('gov.insight.none') }}</p>
            </div>
            <ErrorBox v-else-if="turn.error" :error="turn.error" />
            <div v-else class="a card steps" aria-live="polite">
              <span v-for="(s, j) in STEPS" :key="s" class="step" :class="{ done: j < step, active: j === step }"><i :class="j < step ? 'pi pi-check' : 'pi pi-circle'" aria-hidden="true" /> {{ t('gov.insight.step.' + s) }}</span>
            </div>
          </div>
        </div>
        <div class="ask card">
          <Textarea v-model="question" rows="2" auto-resize :placeholder="t('gov.insight.defaultQuestion')" :disabled="!available" data-testid="insight-question" @keydown.enter.exact.prevent="ask()" />
          <Button :label="t('gov.insight.ask')" icon="pi pi-send" :loading="busy" :disabled="!available || !question.trim()" data-testid="insight-ask" @click="ask()" />
        </div>
      </div>

      <AppCard :title="t('gov.insight.sources')" dense class="col-right">
        <p v-if="!sources.sources.length && !sources.tools.length" class="muted small">{{ t('gov.insight.sourcesEmpty') }}</p>
        <template v-else>
          <div v-if="sources.sources.length" class="src-group">
            <div class="group-title">{{ t('gov.insight.marts') }}</div>
            <div v-for="s in sources.sources" :key="s" class="src mono">{{ s }}</div>
          </div>
          <div v-if="sources.tools.length" class="src-group">
            <div class="group-title">{{ t('gov.insight.tools') }}</div>
            <div v-for="s in sources.tools" :key="s" class="src mono">{{ s }}</div>
          </div>
        </template>
        <p v-if="status" class="muted small" style="margin-top: 12px">{{ status.provider }} · {{ status.model }}</p>
      </AppCard>
    </div>
  </PageShell>
</template>

<style scoped>
.columns { display: grid; grid-template-columns: 260px 1fr 240px; gap: var(--dm-space-4); align-items: start; }
.group + .group { margin-top: 12px; }
.group-title { font-size: var(--dm-text-xs); font-weight: 500; text-transform: uppercase; letter-spacing: 0.06em; color: var(--dm-muted); margin-bottom: 4px; }
.question { display: block; width: 100%; text-align: left; background: none; border: 0; padding: 6px 8px; border-radius: var(--dm-radius-sm); color: var(--dm-ink); font: inherit; font-size: var(--dm-text-sm); cursor: pointer; }
.question:hover:not(:disabled) { background: var(--dm-surface-2); color: var(--dm-ink); }
.question:disabled { color: var(--dm-muted); cursor: default; }
.thread { min-height: 320px; max-height: 60vh; overflow: auto; display: flex; flex-direction: column; gap: 16px; }
.q { display: flex; flex-direction: column; align-items: flex-end; gap: 2px; }
.bubble { background: var(--dm-ink); color: var(--dm-surface); padding: 8px 14px; border-radius: 12px 12px 2px 12px; max-width: 85%; font-size: var(--dm-text-md); }
.a { margin-top: 8px; padding: 16px; background: var(--dm-surface-2); }
.a-head { display: flex; justify-content: space-between; gap: 8px; align-items: center; margin-bottom: 6px; }
.a-number { font-size: var(--dm-text-kpi); font-weight: 500; letter-spacing: -0.02em; line-height: 1; margin: 4px 0; }
.a-number .unit { font-size: 1rem; color: var(--dm-muted); font-weight: 400; }
.a-text { white-space: pre-wrap; margin: 4px 0 8px; }
.a-chart { height: 260px; }
.steps { display: flex; gap: 16px; flex-wrap: wrap; color: var(--dm-muted); }
.step.active { color: var(--dm-ink); font-weight: 500; }
.step.done { color: var(--dm-ok); }
.ask { margin-top: 12px; display: flex; gap: 8px; align-items: flex-end; }
.ask :deep(textarea) { flex: 1; }
.src-group + .src-group { margin-top: 12px; }
.src { padding: 3px 0; word-break: break-all; }
@media (max-width: 1100px) { .columns { grid-template-columns: 1fr; } }
</style>
