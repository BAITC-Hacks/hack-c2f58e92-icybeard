<script setup lang="ts">
import { LineChart } from 'echarts/charts'
import { DataZoomComponent, GridComponent, LegendComponent, TooltipComponent } from 'echarts/components'
import { use } from 'echarts/core'
import { CanvasRenderer } from 'echarts/renderers'
import { computed } from 'vue'
import VChart from 'vue-echarts'
import type { ForecastPoint, HistoryPoint } from '@/api/types'

use([CanvasRenderer, LineChart, GridComponent, TooltipComponent, LegendComponent, DataZoomComponent])

const props = defineProps<{ history: HistoryPoint[]; points?: ForecastPoint[]; title?: string; unit?: string }>()

/** История сплошной линией, прогноз пунктиром с полосой 80 % интервала. */
const option = computed(() => {
  const forecast = props.points ?? []
  const periods = [...props.history.map((h) => h.period), ...forecast.map((p) => p.period)]
  const history = [...props.history.map((h) => h.y), ...forecast.map(() => null)]
  const last = props.history.at(-1)
  const yhat = [...props.history.map((_, i) => (i === props.history.length - 1 ? last?.y ?? null : null)), ...forecast.map((p) => p.yhat)]
  const lo = [...props.history.map(() => null), ...forecast.map((p) => p.lo)]
  const band = [...props.history.map(() => null), ...forecast.map((p) => p.hi - p.lo)]
  return {
    tooltip: { trigger: 'axis' },
    legend: { data: ['Факт', 'Прогноз'] },
    grid: { left: 48, right: 16, top: 36, bottom: 48 },
    xAxis: { type: 'category', data: periods, boundaryGap: false },
    yAxis: { type: 'value', name: props.unit ?? '' },
    dataZoom: periods.length > 40 ? [{ type: 'slider', start: Math.max(0, 100 - (40 / periods.length) * 100) }] : [],
    series: [
      { name: 'Факт', type: 'line', data: history, showSymbol: false, lineStyle: { width: 2 } },
      { name: 'нижняя', type: 'line', data: lo, stack: 'band', lineStyle: { opacity: 0 }, showSymbol: false, silent: true, tooltip: { show: false } },
      { name: 'интервал 80 %', type: 'line', data: band, stack: 'band', lineStyle: { opacity: 0 }, areaStyle: { color: 'rgba(11,114,133,0.15)' }, showSymbol: false, silent: true, tooltip: { show: false } },
      { name: 'Прогноз', type: 'line', data: yhat, showSymbol: false, lineStyle: { type: 'dashed', width: 2, color: '#0b7285' } },
    ],
  }
})
</script>

<template>
  <div class="card">
    <h2 v-if="title">{{ title }}</h2>
    <VChart class="chart" :option="option" autoresize />
  </div>
</template>
