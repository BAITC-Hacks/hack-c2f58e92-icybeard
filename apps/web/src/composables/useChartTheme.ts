import { computed } from 'vue'
import { useTheme } from './useTheme'

/** Цвета графиков Палитры C: серия — фиолетовый accent, прогноз и интервал — светлые фиолетовые, аномалии и
 * риск — янтарь (никогда не фиолетовые), лучший вариант — good. */
export interface ChartTheme {
  ink: string
  muted: string
  hairline: string
  /** фиолетовый brand-акцент (= series) */
  accent: string
  /** основная серия: факт, очередь, «после» в сценарии */
  series: string
  /** линия прогноза (пунктир) — светлый фиолетовый */
  forecast: string
  /** аномалия, риск, перегрузка, отказы — янтарь */
  anomaly: string
  /** лучший вариант — good */
  ok: string
  surface: string
  /** ряды графиков: фиолетовый, янтарь, good, светлый фиолетовый */
  palette: string[]
  /** рамп карты и индекса: пять фиолетовых от «ниже 60» к «87 и выше» (выше = хуже) */
  scale: string[]
  /** полоса интервала прогноза */
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
      series: cssVar('--dm-chart-1'),
      forecast: cssVar('--dm-chart-forecast'),
      anomaly: cssVar('--dm-warn-strong'),
      ok: cssVar('--dm-ok'),
      surface: cssVar('--dm-surface'),
      palette: ['--dm-chart-1', '--dm-chart-2', '--dm-chart-3', '--dm-chart-4'].map(cssVar),
      scale: ['--dm-map-1', '--dm-map-2', '--dm-map-3', '--dm-map-4', '--dm-map-5'].map(cssVar),
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
