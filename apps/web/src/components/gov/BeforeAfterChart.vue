<script setup lang="ts">
import { BarChart, CustomChart } from 'echarts/charts'
import { GridComponent, LegendComponent, TooltipComponent } from 'echarts/components'
import { use } from 'echarts/core'
import { CanvasRenderer } from 'echarts/renderers'
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import VChart from 'vue-echarts'
import { useChartTheme } from '@/composables/useChartTheme'

use([CanvasRenderer, BarChart, CustomChart, GridComponent, TooltipComponent, LegendComponent])

/** «До / после» симулятора: два столбца среднего ожидания и интервал чувствительности на столбце сценария. */
const props = defineProps<{ before: number; after: number; interval: [number, number] }>()
const { t } = useI18n()
const { theme, base, axis } = useChartTheme()

const option = computed(() => ({
  ...base.value,
  tooltip: { trigger: 'axis' },
  grid: { left: 48, right: 16, top: 16, bottom: 32 },
  xAxis: { type: 'category', data: [t('gov.simulator.before'), t('gov.simulator.after')], ...axis.value },
  yAxis: { type: 'value', name: t('common.days'), ...axis.value },
  series: [
    {
      type: 'bar',
      data: [
        { value: props.before, itemStyle: { color: theme.value.palette[2] } },
        { value: props.after, itemStyle: { color: theme.value.accent } },
      ],
      barWidth: 56,
    },
    {
      // усы интервала: [сценарий + нижняя граница дельты, сценарий + верхняя граница] на столбце сценария
      type: 'custom',
      name: t('gov.simulator.sensitivity'),
      data: [[1, props.interval[0], props.interval[1]]],
      renderItem: (_params: unknown, api: { value: (i: number) => number; coord: (v: [number, number]) => [number, number] }) => {
        const x = api.coord([api.value(0), 0])[0]
        const lo = api.coord([api.value(0), api.value(1)])[1]
        const hi = api.coord([api.value(0), api.value(2)])[1]
        const style = { stroke: theme.value.ink, lineWidth: 1.5 }
        return {
          type: 'group',
          children: [
            { type: 'line', shape: { x1: x, y1: lo, x2: x, y2: hi }, style },
            { type: 'line', shape: { x1: x - 10, y1: lo, x2: x + 10, y2: lo }, style },
            { type: 'line', shape: { x1: x - 10, y1: hi, x2: x + 10, y2: hi }, style },
          ],
        }
      },
      tooltip: { show: false },
      z: 3,
    },
  ],
}))
</script>

<template>
  <VChart class="chart before-after" :option="option" autoresize />
</template>

<style scoped>
.before-after { height: 240px; }
</style>
