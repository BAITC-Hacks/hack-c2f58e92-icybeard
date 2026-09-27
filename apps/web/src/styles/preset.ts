import { definePreset } from '@primevue/themes'
import Aura from '@primevue/themes/aura'

/** Пресет PrimeVue на токенах Палитры C «Белый холст»: значения — ссылки на CSS-переменные из tokens.css, поэтому
 * светлая и тёмная схемы одинаковы, а тему переключает класс darumen-dark на <html> (tokens.css задаёт значения).
 * Primary — фиолетовый accent (#5B5BD6, текст белый), secondary — inset #EAECF2 с ink, опасное действие — inset с
 * critical-текстом. Ссылки в фигурных скобках ({indigo.*}) PrimeVue раскрывает сам, строки var(--…) эмитятся как есть. */
const surface = Object.fromEntries([0, 50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 950].map((step) => [step, `var(--dm-surface-${step})`]))

const scheme = {
  surface,
  primary: { color: 'var(--dm-primary)', contrastColor: 'var(--dm-primary-contrast)', hoverColor: 'var(--dm-accent-hover)', activeColor: 'var(--dm-accent-hover)' },
  highlight: { background: 'var(--dm-accent-soft)', focusBackground: 'var(--dm-accent-soft)', color: 'var(--dm-ink)', focusColor: 'var(--dm-ink)' },
  mask: { background: 'rgba(22, 23, 29, 0.45)', color: 'var(--dm-surface-200)' },
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

// Теги по доске C-Tokens: primary — «текущая» (selected/accent-hover); secondary — «нет данных», «формула» (inset/ink-2);
// success — «подтверждено», «в норме»; info — «ML-модель» (info-soft/ink); warn — «риск», «перегрузка» (янтарь);
// danger — «отказ»; contrast — «AI» (lavender/accent-hover)
const tag = {
  primary: { background: 'var(--dm-accent-soft)', color: 'var(--dm-accent-hover)' },
  secondary: { background: 'var(--dm-neutral-soft)', color: 'var(--dm-muted)' },
  success: { background: 'var(--dm-ok-soft)', color: 'var(--dm-ok)' },
  info: { background: 'var(--dm-info-soft)', color: 'var(--dm-ink)' },
  warn: { background: 'var(--dm-warn-soft)', color: 'var(--dm-warn)' },
  danger: { background: 'var(--dm-danger-soft)', color: 'var(--dm-danger)' },
  contrast: { background: 'var(--dm-ai-soft)', color: 'var(--dm-ai)' },
}

const message = Object.fromEntries(
  (
    [
      ['info', 'var(--dm-ink)', 'var(--dm-info-soft)'],
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

// Кнопки: primary — фиолетовый/белый (наведение accent-hover), secondary — inset/ink, опасное действие — inset/critical, без рамок
// Токены кнопки Aura: заливки — под root (иначе PrimeVue берёт свои surface-значения, и в тёмной теме secondary светлая)
const button = {
  root: {
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
      background: 'var(--dm-neutral-soft)', hoverBackground: 'var(--dm-danger-soft)', activeBackground: 'var(--dm-danger-soft)',
      borderColor: 'var(--dm-neutral-soft)', hoverBorderColor: 'var(--dm-danger-soft)', activeBorderColor: 'var(--dm-danger-soft)',
      color: 'var(--dm-danger)', hoverColor: 'var(--dm-danger)', activeColor: 'var(--dm-danger)',
      focusRing: { color: 'var(--dm-danger)', shadow: 'none' },
    },
  },
  text: {
    primary: { hoverBackground: 'var(--dm-accent-soft)', activeBackground: 'var(--dm-accent-soft)', color: 'var(--dm-accent-hover)' },
    secondary: { hoverBackground: 'var(--dm-neutral-soft)', activeBackground: 'var(--dm-neutral-soft)', color: 'var(--dm-muted)' },
    danger: { hoverBackground: 'var(--dm-danger-soft)', activeBackground: 'var(--dm-danger-soft)', color: 'var(--dm-danger)' },
  },
  outlined: {
    primary: { hoverBackground: 'var(--dm-neutral-soft)', activeBackground: 'var(--dm-neutral-soft)', borderColor: 'var(--dm-hairline)', color: 'var(--dm-ink)' },
    secondary: { hoverBackground: 'var(--dm-neutral-soft)', activeBackground: 'var(--dm-neutral-soft)', borderColor: 'var(--dm-hairline)', color: 'var(--dm-ink)' },
  },
}

export const DarumenPreset = definePreset(Aura, {
  semantic: {
    primary: { 50: '{indigo.50}', 100: '{indigo.100}', 200: '{indigo.200}', 300: '{indigo.300}', 400: '{indigo.400}', 500: '{indigo.500}', 600: '{indigo.600}', 700: '{indigo.700}', 800: '{indigo.800}', 900: '{indigo.900}', 950: '{indigo.950}' },
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
