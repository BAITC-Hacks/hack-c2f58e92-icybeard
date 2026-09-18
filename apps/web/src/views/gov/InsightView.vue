<script setup lang="ts">
import { BarChart, LineChart } from 'echarts/charts'
import { GridComponent, LegendComponent, TooltipComponent } from 'echarts/components'
import { use } from 'echarts/core'
import { CanvasRenderer } from 'echarts/renderers'
import Button from 'primevue/button'
import Message from 'primevue/message'
import Textarea from 'primevue/textarea'
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import VChart from 'vue-echarts'
import { insight } from '@/api/endpoints'
import type { AskResponse, InsightStatus } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import OriginTag from '@/components/OriginTag.vue'

use([CanvasRenderer, LineChart, BarChart, GridComponent, TooltipComponent, LegendComponent])

const { t } = useI18n()
const question = ref('')
const result = ref<AskResponse | null>(null)
const error = ref<unknown>(null)
const busy = ref(false)
const status = ref<InsightStatus | null>(null)
const examples = computed(() => t('gov.insight.examples').split('|'))
if (!question.value) question.value = t('gov.insight.defaultQuestion')

const chartOption = computed(() => {
  const chart = result.value?.chart
  if (!chart) return null
  return {
    tooltip: { trigger: 'axis' },
    legend: { data: chart.series.map((s) => s.name) },
    grid: { left: 48, right: 16, top: 36, bottom: chart.type === 'bar' ? 90 : 40 },
    xAxis: { type: 'category', data: chart.x, axisLabel: { rotate: chart.type === 'bar' ? 45 : 0, fontSize: 10 } },
    yAxis: { type: 'value' },
    series: chart.series.map((s) => ({ name: s.name, type: chart.type, data: s.data, showSymbol: false, lineStyle: ['прогноз', 'болжам'].includes(s.name) ? { type: 'dashed' } : undefined })),
  }
})

async function ask() {
  busy.value = true
  error.value = null
  try {
    result.value = await insight.ask(question.value)
  } catch (e) {
    error.value = e
  } finally {
    busy.value = false
  }
}

onMounted(async () => {
  try {
    status.value = await insight.status()
  } catch {
    status.value = null
  }
})
</script>

<template>
  <main class="page">
    <h1>{{ t('gov.insight.title') }}</h1>
    <p class="lead">{{ t('gov.insight.lead') }}</p>
    <Message v-if="status && !status.available" severity="warn" :closable="false">
      {{ t('gov.insight.unavailable', { provider: status.provider, model: status.model }) }}
    </Message>
    <div class="card">
      <div class="field"><label>{{ t('gov.insight.question') }}</label><Textarea v-model="question" rows="2" auto-resize /></div>
      <div class="actions">
        <Button :label="t('gov.insight.ask')" icon="pi pi-comment" :loading="busy" @click="ask" />
        <Button v-for="e in examples" :key="e" :label="e" size="small" severity="secondary" text @click="question = e" />
      </div>
      <ErrorBox :error="error" />
    </div>
    <div v-if="result" class="grid cols-2" style="margin-top: 16px">
      <div class="card">
        <h2>{{ t('gov.insight.answer') }} <OriginTag kind="ai" :note="t('gov.insight.aiNote')" /></h2>
        <p style="white-space: pre-wrap">{{ result.answer }}</p>
        <p class="muted">{{ t('gov.insight.tools') }}: {{ result.toolsUsed.join(', ') || t('gov.insight.none') }} · {{ t('common.model') }} {{ result.model }}</p>
      </div>
      <div v-if="chartOption" class="card">
        <h2>{{ result.chart?.title }}</h2>
        <VChart class="chart" :option="chartOption" autoresize />
      </div>
    </div>
  </main>
</template>
