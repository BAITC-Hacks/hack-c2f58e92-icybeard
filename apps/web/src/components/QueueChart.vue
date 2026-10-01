<script setup lang="ts">
import { BarChart, LineChart } from 'echarts/charts'
import { GridComponent, LegendComponent, TooltipComponent } from 'echarts/components'
import { use } from 'echarts/core'
import { CanvasRenderer } from 'echarts/renderers'
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import VChart from 'vue-echarts'
import type { QueueDay } from '@/api/types'
import { useChartTheme } from '@/composables/useChartTheme'

use([CanvasRenderer, LineChart, BarChart, GridComponent, TooltipComponent, LegendComponent])

/** `bare` — без обёртки-карточки (график внутри AppCard). Цвета рядов — из useChartTheme: очередь — фиолетовая серия, поток — рамп карты, отказы — янтарь. */
const props = defineProps<{ days: QueueDay[]; title?: string; bare?: boolean; height?: number }>()
const shortDay = (d: string) => `${d.slice(8, 10)}.${d.slice(5, 7)}`
const { t } = useI18n()
const { theme, base, axis } = useChartTheme()

const option = computed(() => ({
  ...base.value,
  tooltip: { trigger: 'axis', axisPointer: { type: 'shadow' } },
  legend: { ...base.value.legend, bottom: 0, itemGap: 22, itemWidth: 14, itemHeight: 10, data: [t('queueChart.queue'), t('queueChart.registered'), t('queueChart.hospitalized'), t('queueChart.refused')] },
  grid: { left: 56, right: 56, top: 44, bottom: 64 },
  xAxis: { type: 'category', data: props.days.map((d) => d.day), ...axis.value, axisLabel: { ...axis.value.axisLabel, formatter: shortDay, hideOverlap: true } },
  yAxis: [{ type: 'value', name: t('queueChart.queueAxis'), nameGap: 18, ...axis.value }, { type: 'value', name: t('queueChart.perDay'), nameGap: 18, ...axis.value, splitLine: { show: false } }],
  series: [
    { name: t('queueChart.queue'), type: 'line', data: props.days.map((d) => d.queueLen), showSymbol: false, smooth: 0.3, z: 3, lineStyle: { width: 3, color: theme.value.series }, itemStyle: { color: theme.value.series }, areaStyle: { color: theme.value.series, opacity: 0.08 } },
    { name: t('queueChart.registered'), type: 'bar', yAxisIndex: 1, data: props.days.map((d) => d.registered), stack: 'flow', barMaxWidth: 10, itemStyle: { color: theme.value.scale[2], borderRadius: [3, 3, 0, 0] } },
    { name: t('queueChart.hospitalized'), type: 'bar', yAxisIndex: 1, data: props.days.map((d) => -d.hospitalized), stack: 'flow', itemStyle: { color: theme.value.scale[3] } },
    { name: t('queueChart.refused'), type: 'bar', yAxisIndex: 1, data: props.days.map((d) => -d.refused), stack: 'flow', itemStyle: { color: theme.value.anomaly } },
  ],
}))
</script>

<template>
  <div :class="{ card: !bare }">
    <h2 v-if="title">{{ title }}</h2>
    <VChart class="chart" :option="option" :style="height ? { height: `${height}px` } : undefined" autoresize />
  </div>
</template>
