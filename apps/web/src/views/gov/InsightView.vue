<script setup lang="ts">
import { BarChart, LineChart } from 'echarts/charts'
import { GridComponent, LegendComponent, TooltipComponent } from 'echarts/components'
import { use } from 'echarts/core'
import { CanvasRenderer } from 'echarts/renderers'
import Button from 'primevue/button'
import Message from 'primevue/message'
import Textarea from 'primevue/textarea'
import { computed, onMounted, ref } from 'vue'
import VChart from 'vue-echarts'
import { insight } from '@/api/endpoints'
import type { AskResponse, InsightStatus } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import OriginTag from '@/components/OriginTag.vue'

use([CanvasRenderer, LineChart, BarChart, GridComponent, TooltipComponent, LegendComponent])

const question = ref('Какой регион самый доступный по плановой госпитализации в марте 2025?')
const result = ref<AskResponse | null>(null)
const error = ref<unknown>(null)
const busy = ref(false)
const status = ref<InsightStatus | null>(null)
const examples = [
  'Сколько дней ждут офтальмологию в Алматы?',
  'Есть ли критические сигналы по Алматы?',
  'Что будет с ожиданием в Алматы по офтальмологии, если добавить 15 % мощности?',
  'Назови три региона с худшим индексом доступности.',
]

const chartOption = computed(() => {
  const chart = result.value?.chart
  if (!chart) return null
  return {
    tooltip: { trigger: 'axis' },
    legend: { data: chart.series.map((s) => s.name) },
    grid: { left: 48, right: 16, top: 36, bottom: chart.type === 'bar' ? 90 : 40 },
    xAxis: { type: 'category', data: chart.x, axisLabel: { rotate: chart.type === 'bar' ? 45 : 0, fontSize: 10 } },
    yAxis: { type: 'value' },
    series: chart.series.map((s) => ({ name: s.name, type: chart.type, data: s.data, showSymbol: false, lineStyle: s.name === 'прогноз' ? { type: 'dashed' } : undefined })),
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
    <h1>Вопросы к данным</h1>
    <p class="lead">Вопрос на естественном языке превращается в вызовы инструментов доменов (индекс, прогноз, очередь, симулятор) и короткий ответ с цифрой. Модель не видит сырые данные.</p>
    <Message v-if="status && !status.available" severity="warn" :closable="false">
      Insight выключен: для провайдера {{ status.provider }} ({{ status.model }}) на сервере не задан ключ API (файл .env). Вопросы вернут 503.
    </Message>
    <div class="card">
      <div class="field"><label>Вопрос</label><Textarea v-model="question" rows="2" auto-resize /></div>
      <div class="actions">
        <Button label="Спросить" icon="pi pi-comment" :loading="busy" @click="ask" />
        <Button v-for="e in examples" :key="e" :label="e" size="small" severity="secondary" text @click="question = e" />
      </div>
      <ErrorBox :error="error" />
    </div>
    <div v-if="result" class="grid cols-2" style="margin-top: 16px">
      <div class="card">
        <h2>Ответ <OriginTag kind="ai" note="Формулировка — языковой модели; каждое число взято из перечисленных ниже инструментов" /></h2>
        <p style="white-space: pre-wrap">{{ result.answer }}</p>
        <p class="muted">инструменты: {{ result.toolsUsed.join(', ') || 'нет' }} · модель {{ result.model }}</p>
      </div>
      <div v-if="chartOption" class="card">
        <h2>{{ result.chart?.title }}</h2>
        <VChart class="chart" :option="chartOption" autoresize />
      </div>
    </div>
  </main>
</template>
