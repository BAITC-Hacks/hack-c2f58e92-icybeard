import { definePreset } from '@primevue/themes'
import Aura from '@primevue/themes/aura'

/** Пресет PrimeVue на токенах Clinical Minimal: значения — ссылки на CSS-переменные из tokens.css, поэтому
 * светлая и тёмная схемы одинаковы, а тему переключает класс darumen-dark на <html> (tokens.css задаёт значения).
 * Ссылки в фигурных скобках ({teal.*}) PrimeVue раскрывает сам, строки var(--…) эмитятся как есть. */
const surface = Object.fromEntries([0, 50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 950].map((step) => [step, `var(--dm-surface-${step})`]))

const scheme = {
  surface,
  primary: { color: 'var(--dm-accent)', contrastColor: '#ffffff', hoverColor: 'var(--dm-accent-hover)', activeColor: 'var(--dm-accent-hover)' },
  highlight: { background: 'var(--dm-accent-soft)', focusBackground: 'var(--dm-accent-soft)', color: 'var(--dm-accent)', focusColor: 'var(--dm-accent)' },
  mask: { background: 'rgba(16, 20, 24, 0.5)', color: 'var(--dm-surface-200)' },
  text: { color: 'var(--dm-ink)', hoverColor: 'var(--dm-ink)', mutedColor: 'var(--dm-muted)', hoverMutedColor: 'var(--dm-ink)' },
  content: { background: 'var(--dm-surface)', hoverBackground: 'var(--dm-surface-2)', borderColor: 'var(--dm-hairline)', color: 'var(--dm-ink)', hoverColor: 'var(--dm-ink)' },
  formField: {
    background: 'var(--dm-surface)', disabledBackground: 'var(--dm-surface-2)', filledBackground: 'var(--dm-surface-2)',
    filledHoverBackground: 'var(--dm-surface-2)', filledFocusBackground: 'var(--dm-surface-2)',
    borderColor: 'var(--dm-hairline)', hoverBorderColor: 'var(--dm-muted)', focusBorderColor: 'var(--dm-accent)', invalidBorderColor: 'var(--dm-danger)',
    color: 'var(--dm-ink)', disabledColor: 'var(--dm-muted)', placeholderColor: 'var(--dm-muted)', invalidPlaceholderColor: 'var(--dm-danger)',
    floatLabelColor: 'var(--dm-muted)', floatLabelFocusColor: 'var(--dm-accent)', floatLabelActiveColor: 'var(--dm-muted)', floatLabelInvalidColor: 'var(--dm-danger)',
    iconColor: 'var(--dm-muted)', shadow: 'none',
  },
  overlay: {
    select: { background: 'var(--dm-surface)', borderColor: 'var(--dm-hairline)', color: 'var(--dm-ink)' },
    popover: { background: 'var(--dm-surface)', borderColor: 'var(--dm-hairline)', color: 'var(--dm-ink)' },
    modal: { background: 'var(--dm-surface)', borderColor: 'var(--dm-hairline)', color: 'var(--dm-ink)' },
  },
}

// Теги и сообщения: приглушённые пары «фон/текст» вместо насыщенных палитр Aura
const tag = {
  primary: { background: 'var(--dm-accent-soft)', color: 'var(--dm-accent)' },
  secondary: { background: 'var(--dm-neutral-soft)', color: 'var(--dm-muted)' },
  success: { background: 'var(--dm-ok-soft)', color: 'var(--dm-ok)' },
  info: { background: 'var(--dm-accent-soft)', color: 'var(--dm-accent)' },
  warn: { background: 'var(--dm-warn-soft)', color: 'var(--dm-warn)' },
  danger: { background: 'var(--dm-danger-soft)', color: 'var(--dm-danger)' },
  contrast: { background: 'var(--dm-ink)', color: 'var(--dm-surface)' },
}

const message = Object.fromEntries(
  (
    [
      ['info', 'var(--dm-accent)', 'var(--dm-accent-soft)'],
      ['success', 'var(--dm-ok)', 'var(--dm-ok-soft)'],
      ['warn', 'var(--dm-warn)', 'var(--dm-warn-soft)'],
      ['error', 'var(--dm-danger)', 'var(--dm-danger-soft)'],
      ['secondary', 'var(--dm-muted)', 'var(--dm-neutral-soft)'],
    ] as const
  ).map(([name, color, soft]) => [
    name,
    {
      background: soft, borderColor: soft, color, shadow: 'none',
      closeButton: { hoverBackground: 'transparent', focusRing: { color, shadow: 'none' } },
      outlined: { color, borderColor: color },
      simple: { color },
    },
  ]),
)

export const DarumenPreset = definePreset(Aura, {
  semantic: {
    primary: { 50: '{teal.50}', 100: '{teal.100}', 200: '{teal.200}', 300: '{teal.300}', 400: '{teal.400}', 500: '{teal.500}', 600: '{teal.600}', 700: '{teal.700}', 800: '{teal.800}', 900: '{teal.900}', 950: '{teal.950}' },
    colorScheme: { light: scheme, dark: scheme },
  },
  components: {
    tag: { colorScheme: { light: tag, dark: tag } },
    message: { colorScheme: { light: message, dark: message } },
  },
})
