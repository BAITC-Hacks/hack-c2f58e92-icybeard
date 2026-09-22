import { computed } from 'vue'
import { useTheme } from './useTheme'

export interface ChartTheme {
  ink: string
  muted: string
  hairline: string
  accent: string
  surface: string
  palette: string[]
  band: string
  font: string
}

function cssVar(name: string): string {
  if (typeof document === 'undefined') return ''
  return getComputedStyle(document.documentElement).getPropertyValue(name).trim()
}

/** Цвета графиков и карты из вычисленных токенов: canvas ECharts и MapLibre не понимают var(--…),
 * поэтому значения читаются заново при каждой смене темы (класс darumen-dark на <html>). */
export function useChartTheme() {
  const { isDark } = useTheme()
  const theme = computed<ChartTheme>(() => {
    void isDark.value // зависимость: пересчитать после переключения темы
    return {
      ink: cssVar('--dm-ink'),
      muted: cssVar('--dm-muted'),
      hairline: cssVar('--dm-hairline'),
      accent: cssVar('--dm-accent'),
      surface: cssVar('--dm-surface'),
      palette: ['--dm-chart-1', '--dm-chart-2', '--dm-chart-3', '--dm-chart-4'].map(cssVar),
      band: cssVar('--dm-chart-band'),
      font: cssVar('--dm-font-sans'),
    }
  })

  /** Общая часть option ECharts: прозрачный фон, палитра и цвета текста из токенов. */
  const base = computed(() => ({
    backgroundColor: 'transparent',
    color: theme.value.palette,
    textStyle: { color: theme.value.ink, fontFamily: theme.value.font },
    legend: { textStyle: { color: theme.value.muted } },
  }))

  /** Оси: подписи приглушённые, линии и сетка — hairline. */
  const axis = computed(() => ({
    axisLabel: { color: theme.value.muted },
    axisLine: { lineStyle: { color: theme.value.hairline } },
    splitLine: { lineStyle: { color: theme.value.hairline } },
    nameTextStyle: { color: theme.value.muted },
  }))

  return { theme, base, axis, isDark }
}
