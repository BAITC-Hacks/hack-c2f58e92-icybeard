import { definePreset } from '@primevue/themes'
import Aura from '@primevue/themes/aura'

/** Пресет PrimeVue на токенах «Тихой клиники»: значения — ссылки на CSS-переменные из tokens.css, поэтому
 * светлая и тёмная схемы одинаковы, а тему переключает класс darumen-dark на <html> (tokens.css задаёт значения).
 * Primary — ink (тёмно-синие кнопки), коралл остаётся сигналом и в пресет как primary не попадает.
 * Ссылки в фигурных скобках ({slate.*}) PrimeVue раскрывает сам, строки var(--…) эмитятся как есть. */
const surface = Object.fromEntries([0, 50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 950].map((step) => [step, `var(--dm-surface-${step})`]))

const scheme = {
  surface,
  primary: { color: 'var(--dm-primary)', contrastColor: 'var(--dm-primary-contrast)', hoverColor: 'var(--dm-accent-hover)', activeColor: 'var(--dm-accent-hover)' },
  highlight: { background: 'var(--dm-neutral-soft)', focusBackground: 'var(--dm-neutral-soft)', color: 'var(--dm-ink)', focusColor: 'var(--dm-ink)' },
  mask: { background: 'rgba(11, 30, 61, 0.5)', color: 'var(--dm-surface-200)' },
  text: { color: 'var(--dm-ink)', hoverColor: 'var(--dm-ink)', mutedColor: 'var(--dm-muted)', hoverMutedColor: 'var(--dm-ink)' },
  content: { background: 'var(--dm-surface)', hoverBackground: 'var(--dm-surface-2)', borderColor: 'var(--dm-hairline)', color: 'var(--dm-ink)', hoverColor: 'var(--dm-ink)' },
  formField: {
    background: 'var(--dm-surface-2)', disabledBackground: 'var(--dm-surface-2)', filledBackground: 'var(--dm-surface-2)',
    filledHoverBackground: 'var(--dm-surface-2)', filledFocusBackground: 'var(--dm-surface-2)',
    borderColor: 'transparent', hoverBorderColor: 'transparent', focusBorderColor: 'var(--dm-primary)', invalidBorderColor: 'var(--dm-danger)',
    color: 'var(--dm-ink)', disabledColor: 'var(--dm-muted)', placeholderColor: 'var(--dm-muted)', invalidPlaceholderColor: 'var(--dm-danger)',
    floatLabelColor: 'var(--dm-muted)', floatLabelFocusColor: 'var(--dm-ink)', floatLabelActiveColor: 'var(--dm-muted)', floatLabelInvalidColor: 'var(--dm-danger)',
    iconColor: 'var(--dm-muted)', shadow: 'none',
  },
  overlay: {
    select: { background: 'var(--dm-surface)', borderColor: 'var(--dm-hairline)', color: 'var(--dm-ink)' },
    popover: { background: 'var(--dm-surface)', borderColor: 'var(--dm-hairline)', color: 'var(--dm-ink)' },
    modal: { background: 'var(--dm-surface)', borderColor: 'var(--dm-hairline)', color: 'var(--dm-ink)' },
  },
}

// Теги и сообщения: пары «фон/текст» системы — ok: sage; warn/danger: coral-wash/coral-text; info/ML: heal-wash/ink
const tag = {
  primary: { background: 'var(--dm-accent-soft)', color: 'var(--dm-ink)' },
  secondary: { background: 'var(--dm-neutral-soft)', color: 'var(--dm-muted)' },
  success: { background: 'var(--dm-ok-soft)', color: 'var(--dm-ok)' },
  info: { background: 'var(--dm-accent-soft)', color: 'var(--dm-ink)' },
  warn: { background: 'var(--dm-warn-soft)', color: 'var(--dm-warn)' },
  danger: { background: 'var(--dm-danger-soft)', color: 'var(--dm-danger)' },
  contrast: { background: 'var(--dm-ink)', color: 'var(--dm-surface)' },
}

const message = Object.fromEntries(
  (
    [
      ['info', 'var(--dm-ink)', 'var(--dm-accent-soft)'],
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

// Кнопки: primary ink/белый, secondary — soft/ink, без рамок
const button = {
  primary: {
    background: 'var(--dm-primary)', hoverBackground: 'var(--dm-accent-hover)', activeBackground: 'var(--dm-accent-hover)',
    borderColor: 'var(--dm-primary)', hoverBorderColor: 'var(--dm-accent-hover)', activeBorderColor: 'var(--dm-accent-hover)',
    color: 'var(--dm-primary-contrast)', hoverColor: 'var(--dm-primary-contrast)', activeColor: 'var(--dm-primary-contrast)',
    focusRing: { color: 'var(--dm-primary)', shadow: 'none' },
  },
  secondary: {
    background: 'var(--dm-neutral-soft)', hoverBackground: 'var(--dm-hairline)', activeBackground: 'var(--dm-hairline)',
    borderColor: 'var(--dm-neutral-soft)', hoverBorderColor: 'var(--dm-hairline)', activeBorderColor: 'var(--dm-hairline)',
    color: 'var(--dm-ink)', hoverColor: 'var(--dm-ink)', activeColor: 'var(--dm-ink)',
    focusRing: { color: 'var(--dm-ink)', shadow: 'none' },
  },
  danger: {
    background: 'var(--dm-danger-soft)', hoverBackground: 'var(--dm-danger-soft)', activeBackground: 'var(--dm-danger-soft)',
    borderColor: 'var(--dm-danger-soft)', hoverBorderColor: 'var(--dm-danger-soft)', activeBorderColor: 'var(--dm-danger-soft)',
    color: 'var(--dm-danger)', hoverColor: 'var(--dm-danger)', activeColor: 'var(--dm-danger)',
    focusRing: { color: 'var(--dm-danger)', shadow: 'none' },
  },
  text: {
    primary: { hoverBackground: 'var(--dm-neutral-soft)', activeBackground: 'var(--dm-neutral-soft)', color: 'var(--dm-ink)' },
    secondary: { hoverBackground: 'var(--dm-neutral-soft)', activeBackground: 'var(--dm-neutral-soft)', color: 'var(--dm-muted)' },
  },
  outlined: {
    primary: { hoverBackground: 'var(--dm-neutral-soft)', activeBackground: 'var(--dm-neutral-soft)', borderColor: 'var(--dm-hairline)', color: 'var(--dm-ink)' },
    secondary: { hoverBackground: 'var(--dm-neutral-soft)', activeBackground: 'var(--dm-neutral-soft)', borderColor: 'var(--dm-hairline)', color: 'var(--dm-ink)' },
  },
}

export const DarumenPreset = definePreset(Aura, {
  semantic: {
    primary: { 50: '{slate.50}', 100: '{slate.100}', 200: '{slate.200}', 300: '{slate.300}', 400: '{slate.400}', 500: '{slate.500}', 600: '{slate.600}', 700: '{slate.700}', 800: '{slate.800}', 900: '{slate.900}', 950: '{slate.950}' },
    formField: { borderRadius: 'var(--dm-radius-md)', paddingX: '16px', paddingY: '10px', focusRing: { width: '2px', style: 'solid', color: 'var(--dm-primary)', offset: '0', shadow: 'none' } },
    colorScheme: { light: scheme, dark: scheme },
  },
  components: {
    button: {
      borderRadius: 'var(--dm-radius-md)',
      paddingX: '20px', paddingY: '10px',
      sm: { fontSize: '14px', paddingX: '14px', paddingY: '7px' },
      lg: { fontSize: '17px', paddingX: '24px', paddingY: '14px' },
      colorScheme: { light: button, dark: button },
    },
    tag: { borderRadius: 'var(--dm-radius-sm)', fontSize: '12px', fontWeight: 500, colorScheme: { light: tag, dark: tag } },
    message: { borderRadius: 'var(--dm-radius-md)', colorScheme: { light: message, dark: message } },
    selectbutton: { borderRadius: 'var(--dm-radius-pill)' },
    togglebutton: { borderRadius: 'var(--dm-radius-pill)' },
    dialog: { borderRadius: 'var(--dm-radius-lg)' },
  },
})
