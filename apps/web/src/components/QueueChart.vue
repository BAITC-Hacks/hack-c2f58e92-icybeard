<script setup lang="ts">
import { BarChart, LineChart } from 'echarts/charts'
import { GridComponent, LegendComponent, TooltipComponent } from 'echarts/components'
import { use } from 'echarts/core'
import { CanvasRenderer } from 'echarts/renderers'
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import VChart from 'vue-echarts'
import type { QueueDay } from '@/api/types'

use([CanvasRenderer, LineChart, BarChart, GridComponent, TooltipComponent, LegendComponent])

const props = defineProps<{ days: QueueDay[]; title?: string }>()
const { t } = useI18n()

const option = computed(() => ({
  tooltip: { trigger: 'axis' },
  legend: { data: [t('queueChart.queue'), t('queueChart.registered'), t('queueChart.hospitalized'), t('queueChart.refused')] },
  grid: { left: 48, right: 48, top: 36, bottom: 32 },
  xAxis: { type: 'category', data: props.days.map((d) => d.day) },
  yAxis: [{ type: 'value', name: t('queueChart.queue') }, { type: 'value', name: t('queueChart.perDay') }],
  series: [
    { name: t('queueChart.queue'), type: 'line', data: props.days.map((d) => d.queueLen), showSymbol: false, lineStyle: { width: 2 } },
    { name: t('queueChart.registered'), type: 'bar', yAxisIndex: 1, data: props.days.map((d) => d.registered), stack: 'flow' },
    { name: t('queueChart.hospitalized'), type: 'bar', yAxisIndex: 1, data: props.days.map((d) => -d.hospitalized), stack: 'flow' },
    { name: t('queueChart.refused'), type: 'bar', yAxisIndex: 1, data: props.days.map((d) => -d.refused), stack: 'flow' },
  ],
}))
</script>

<template>
  <div class="card">
    <h2 v-if="title">{{ title }}</h2>
    <VChart class="chart" :option="option" autoresize />
  </div>
</template>
