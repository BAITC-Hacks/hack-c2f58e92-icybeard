import { definePreset } from '@primevue/themes'
import Aura from '@primevue/themes/aura'

/** Пресет PrimeVue на токенах «синей гаммы»: значения — ссылки на CSS-переменные из tokens.css, поэтому светлая и
 * тёмная схемы одинаковы, а тему переключает класс darumen-dark на <html> (tokens.css задаёт значения).
 * Primary — синий --accent (#2F6FE4, текст белый), secondary — --accent-subtle с текстом --accent-strong,
 * опасное действие — --danger-bg/--danger-text; кнопки всегда pill. Поля — белые с рамкой --border и кольцом
 * фокуса --focus-ring. Ссылки в фигурных скобках ({blue.*}) PrimeVue раскрывает сам, строки var(--…) эмитятся как есть. */
const surface = Object.fromEntries([0, 50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 950].map((step) => [step, `var(--dm-surface-${step})`]))

const scheme = {
  surface,
  primary: { color: 'var(--accent)', contrastColor: 'var(--text-on-accent)', hoverColor: 'var(--accent-strong)', activeColor: 'var(--accent-strong)' },
  highlight: { background: 'var(--accent-soft)', focusBackground: 'var(--accent-soft)', color: 'var(--accent-strong)', focusColor: 'var(--accent-strong)' },
  mask: { background: 'rgba(13, 21, 38, 0.45)', color: 'var(--dm-surface-200)' },
  text: { color: 'var(--text)', hoverColor: 'var(--text)', mutedColor: 'var(--text-muted)', hoverMutedColor: 'var(--text-secondary)' },
  content: { background: 'var(--surface)', hoverBackground: 'var(--surface-hover)', borderColor: 'var(--border)', color: 'var(--text)', hoverColor: 'var(--text)' },
  formField: {
    background: 'var(--surface)', disabledBackground: 'var(--bg-page)', filledBackground: 'var(--surface)',
    filledHoverBackground: 'var(--surface)', filledFocusBackground: 'var(--surface)',
    borderColor: 'var(--border)', hoverBorderColor: 'var(--border-strong)', focusBorderColor: 'var(--accent)', invalidBorderColor: 'var(--danger-strong)',
    color: 'var(--text)', disabledColor: 'var(--text-muted)', placeholderColor: 'var(--text-faint)', invalidPlaceholderColor: 'var(--danger-strong)',
    floatLabelColor: 'var(--text-muted)', floatLabelFocusColor: 'var(--text)', floatLabelActiveColor: 'var(--text-muted)', floatLabelInvalidColor: 'var(--danger-strong)',
    iconColor: 'var(--text-muted)', shadow: 'none',
  },
  overlay: {
    select: { background: 'var(--surface)', borderColor: 'var(--border-soft)', color: 'var(--text)' },
    popover: { background: 'var(--surface)', borderColor: 'var(--border-soft)', color: 'var(--text)' },
    modal: { background: 'var(--surface)', borderColor: 'var(--border-soft)', color: 'var(--text)' },
  },
}

// Теги по components.md: primary/info — статус «инфо» (accent-soft/accent-strong); secondary — нейтральный
// (surface-sunken/text-secondary); success — «действует», «в норме»; warn — «есть сигнал», «ждём согласия» (янтарь);
// danger — «риск отказа», «истёк»; contrast — бывший «AI»: бирюзовый ML и лавандовый AI упразднены → нейтральная пилюля
const tag = {
  primary: { background: 'var(--accent-soft)', color: 'var(--accent-strong)' },
  secondary: { background: 'var(--surface-sunken)', color: 'var(--text-secondary)' },
  success: { background: 'var(--success-bg)', color: 'var(--success-text)' },
  info: { background: 'var(--accent-soft)', color: 'var(--accent-strong)' },
  warn: { background: 'var(--warning-bg)', color: 'var(--warning-text)' },
  danger: { background: 'var(--danger-bg)', color: 'var(--danger-text)' },
  contrast: { background: 'var(--surface-muted)', color: 'var(--text-secondary)' },
}

const message = Object.fromEntries(
  (
    [
      ['info', 'var(--accent-strong)', 'var(--accent-soft)'],
      ['success', 'var(--success-text)', 'var(--success-bg)'],
      ['warn', 'var(--warning-text)', 'var(--warning-bg)'],
      ['error', 'var(--danger-text)', 'var(--danger-bg)'],
      ['secondary', 'var(--text-secondary)', 'var(--surface-muted)'],
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

// Кнопки (components.md): primary — accent/белый (hover accent-strong); secondary — accent-subtle/accent-strong;
// опасное действие — danger-bg/danger-text; все pill. Заливки — под root (иначе PrimeVue берёт свои surface-значения)
const button = {
  root: {
    primary: {
      background: 'var(--accent)', hoverBackground: 'var(--accent-strong)', activeBackground: 'var(--accent-strong)',
      borderColor: 'var(--accent)', hoverBorderColor: 'var(--accent-strong)', activeBorderColor: 'var(--accent-strong)',
      color: 'var(--text-on-accent)', hoverColor: 'var(--text-on-accent)', activeColor: 'var(--text-on-accent)',
      focusRing: { color: 'var(--accent)', shadow: 'none' },
    },
    secondary: {
      background: 'var(--accent-subtle)', hoverBackground: 'var(--accent-soft)', activeBackground: 'var(--accent-soft)',
      borderColor: 'var(--accent-subtle)', hoverBorderColor: 'var(--accent-soft)', activeBorderColor: 'var(--accent-soft)',
      color: 'var(--accent-strong)', hoverColor: 'var(--accent-strong)', activeColor: 'var(--accent-strong)',
      focusRing: { color: 'var(--accent-strong)', shadow: 'none' },
    },
    danger: {
      background: 'var(--danger-bg)', hoverBackground: 'color-mix(in srgb, var(--danger-bg) 86%, var(--danger-strong))', activeBackground: 'color-mix(in srgb, var(--danger-bg) 86%, var(--danger-strong))',
      borderColor: 'var(--danger-bg)', hoverBorderColor: 'color-mix(in srgb, var(--danger-bg) 86%, var(--danger-strong))', activeBorderColor: 'color-mix(in srgb, var(--danger-bg) 86%, var(--danger-strong))',
      color: 'var(--danger-text)', hoverColor: 'var(--danger-text)', activeColor: 'var(--danger-text)',
      focusRing: { color: 'var(--danger-strong)', shadow: 'none' },
    },
  },
  text: {
    primary: { hoverBackground: 'var(--accent-subtle)', activeBackground: 'var(--accent-subtle)', color: 'var(--accent-strong)' },
    secondary: { hoverBackground: 'var(--surface-muted)', activeBackground: 'var(--surface-muted)', color: 'var(--text-secondary)' },
    danger: { hoverBackground: 'var(--danger-bg)', activeBackground: 'var(--danger-bg)', color: 'var(--danger-strong)' },
  },
  // outlined = mini-кнопка «Направить сюда»: белая, рамка --accent-line, текст --accent-strong
  outlined: {
    primary: { hoverBackground: 'var(--accent-subtle)', activeBackground: 'var(--accent-subtle)', borderColor: 'var(--accent-line)', color: 'var(--accent-strong)' },
    secondary: { hoverBackground: 'var(--accent-subtle)', activeBackground: 'var(--accent-subtle)', borderColor: 'var(--accent-line)', color: 'var(--accent-strong)' },
  },
}

export const DarumenPreset = definePreset(Aura, {
  semantic: {
    primary: { 50: '{blue.50}', 100: '{blue.100}', 200: '{blue.200}', 300: '{blue.300}', 400: '{blue.400}', 500: '{blue.500}', 600: '{blue.600}', 700: '{blue.700}', 800: '{blue.800}', 900: '{blue.900}', 950: '{blue.950}' },
    formField: { borderRadius: 'var(--radius-md)', paddingX: '14px', paddingY: '10px', focusRing: { width: '0', style: 'none', color: 'transparent', offset: '0', shadow: 'var(--focus-ring)' } },
    colorScheme: { light: scheme, dark: scheme },
  },
  components: {
    button: {
      borderRadius: 'var(--radius-pill)',
      paddingX: '20px', paddingY: '11px',
      sm: { fontSize: 'var(--fs-base-sm)', paddingX: '18px', paddingY: '8px' },
      lg: { fontSize: '15.5px', paddingX: '24px', paddingY: '15px' },
      colorScheme: { light: button, dark: button },
    },
    tag: { borderRadius: 'var(--radius-sm)', fontSize: 'var(--fs-xs)', fontWeight: 700, colorScheme: { light: tag, dark: tag } },
    message: { borderRadius: 'var(--radius-lg)', colorScheme: { light: message, dark: message } },
    selectbutton: { borderRadius: 'var(--radius-pill)' },
    togglebutton: { borderRadius: 'var(--radius-pill)' },
    dialog: { borderRadius: 'var(--radius-card-lg)' },
  },
})
