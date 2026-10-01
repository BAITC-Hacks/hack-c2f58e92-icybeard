import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

// vitest отдаёт импорт .css пустой строкой даже с ?raw — читаем файл напрямую (cwd vitest — apps/web)
const css = readFileSync(resolve(process.cwd(), 'src/styles/tokens.css'), 'utf8')
// design/tokens.json лежит в корне репозитория, вне apps/web: статический импорт ломает vue-tsc в Docker-сборке
// (в образ копируется только apps/web), поэтому читаем файл так же, как tokens.css
const tokens = JSON.parse(readFileSync(resolve(process.cwd(), '../../design/tokens.json'), 'utf8')) as {
  light: Record<string, string>
  dark: Record<string, string>
  'scale-ramp': { light: string[]; dark: string[] }
  radius: Record<string, number>
  font: { family: string; weights: number[] }
  type: { text: Record<string, number>; web: Record<string, number>; mobile: Record<string, number> }
  layout: { web: Record<string, number | string>; mobile: Record<string, number> }
}

/** Значение токена без различий в пробелах и регистре (в градиентах и тенях пробелы не значимы). */
const norm = (value: string) => value.replace(/\s+/g, ' ').trim().toUpperCase()

/** Число из tokens.json как значение CSS: 14.5 → «14.5px», строка («24px 32px») — как есть. */
const px = (value: number | string) => norm(typeof value === 'number' ? `${value}px` : value)

/** camelCase-ключ JSON → kebab-case имени переменной: cardLg → card-lg. */
const kebab = (key: string) => key.replace(/[A-Z]/g, (ch) => `-${ch.toLowerCase()}`)

function block(selector: string): Record<string, string> {
  const start = css.indexOf(`${selector} {`)
  const body = css.slice(start, css.indexOf('\n}', start))
  return Object.fromEntries([...body.matchAll(/(--[\w-]+):\s*([^;]+);/g)].map((m) => [m[1], norm(m[2]!)]))
}

describe('design tokens («синяя гамма»)', () => {
  it.each([
    ['light', ':root'],
    ['dark', 'html.darumen-dark'],
  ] as const)('%s theme in tokens.css matches design/tokens.json', (theme, selector) => {
    const vars = block(selector)
    for (const [role, value] of Object.entries(tokens[theme])) {
      expect(vars[`--${role}`], `--${role} (${theme})`).toBe(norm(value))
    }
  })

  it('keeps the blue accent as the primary colour, with white text on it', () => {
    const light = block(':root')
    expect(light['--dm-primary']).toBe('VAR(--ACCENT)')
    expect(light['--accent']).toBe(tokens.light.accent!.toUpperCase())
    expect(light['--text-on-accent']).toBe('#FFFFFF')
    // тёмная тема: акцентная заливка остаётся той же, текстовый акцент — светлый
    expect(block('html.darumen-dark')['--accent']).toBe(tokens.dark.accent!.toUpperCase())
  })

  it('keeps semantics non-blue: risk and overload stay warning/danger in both themes', () => {
    for (const theme of ['light', 'dark'] as const) {
      for (const role of ['warning-text', 'warning-strong', 'danger-text', 'danger-strong']) {
        expect(tokens[theme][role], `${role} (${theme})`).not.toBe(tokens[theme].accent)
      }
    }
  })

  it('keeps the Manrope family and maps legacy --dm-* names onto the new tokens', () => {
    expect(css).toContain(`'${tokens.font.family}`)
    const light = block(':root')
    for (const [legacy, target] of [
      ['--dm-bg', '--bg-page'],
      ['--dm-surface', '--surface'],
      ['--dm-ink', '--text'],
      ['--dm-muted', '--text-secondary'],
      ['--dm-hairline', '--border'],
      ['--dm-accent', '--accent'],
      ['--dm-accent-hover', '--accent-strong'],
      ['--dm-accent-soft', '--accent-soft'],
      ['--dm-ok', '--success-text'],
      ['--dm-warn', '--warning-text'],
      ['--dm-danger', '--danger-text'],
      // бирюзовый «ML» и лавандовый «AI» упразднены — метки происхождения нейтральные
      ['--dm-info-soft', '--surface-muted'],
      ['--dm-ai-soft', '--surface-muted'],
    ] as const) {
      expect(light[legacy], legacy).toBe(`VAR(${target.toUpperCase()})`)
    }
  })

  it.each([
    ['light', ':root'],
    ['dark', 'html.darumen-dark'],
  ] as const)('%s map ramp --dm-map-1…5 matches scale-ramp, with good/mid/bad at steps 1, 3 and 5', (theme, selector) => {
    const vars = block(selector)
    const ramp = tokens['scale-ramp'][theme]
    expect(ramp).toHaveLength(5)
    ramp.forEach((value, i) => expect(vars[`--dm-map-${i + 1}`], `--dm-map-${i + 1} (${theme})`).toBe(norm(value)))
    expect([ramp[0], ramp[2], ramp[4]]).toEqual([tokens[theme]['scale-good'], tokens[theme]['scale-mid'], tokens[theme]['scale-bad']])
  })

  it('radius tokens match --radius-* (camelCase keys become kebab-case)', () => {
    const light = block(':root')
    for (const [key, value] of Object.entries(tokens.radius)) {
      expect(light[`--radius-${kebab(key)}`], `--radius-${kebab(key)}`).toBe(px(value))
    }
  })

  it('font weights match the --fw-* scale (Manrope has no 900: «black» renders as 800)', () => {
    const light = block(':root')
    const weights = Object.entries(light).filter(([name]) => name.startsWith('--fw-')).map(([, value]) => Number(value))
    expect([...new Set(weights)].sort((a, b) => a - b)).toEqual([...tokens.font.weights].sort((a, b) => a - b))
    expect(light['--fw-black']).toBe(light['--fw-extrabold'])
  })

  it('the shared text tier and the web display tier match --fs-*', () => {
    const light = block(':root')
    for (const [key, value] of Object.entries({ ...tokens.type.text, ...tokens.type.web })) {
      expect(light[`--fs-${key}`], `--fs-${key}`).toBe(px(value))
    }
    // ни одного --fs-* вне tokens.json: новый кегль сначала попадает в единый источник
    const declared = Object.keys(light).filter((name) => name.startsWith('--fs-')).map((name) => name.slice('--fs-'.length))
    expect(declared.sort()).toEqual(Object.keys({ ...tokens.type.text, ...tokens.type.web }).sort())
  })

  it('keeps the phone display tier no larger than the web one and the reading tier shared', () => {
    // на телефоне крупный ярус свой (KPI 22 против 26), но тело и подписи — те же, что у веба на той же ширине
    expect(tokens.type.mobile.kpi).toBeLessThanOrEqual(tokens.type.web.kpi)
    expect(tokens.type.mobile.title).toBeLessThanOrEqual(tokens.type.web['h1-citizen'])
    expect(tokens.type.text.base).toBe(14.5)
  })

  it('web layout tokens match tokens.css', () => {
    const light = block(':root')
    for (const [key, value] of Object.entries(tokens.layout.web)) {
      expect(light[`--${key}`], `--${key}`).toBe(px(value))
    }
  })

  it('legacy --dm-text-* aliases point at the type scale', () => {
    const light = block(':root')
    for (const [legacy, target] of [
      ['--dm-text-xs', '--fs-xs'],
      ['--dm-text-sm', '--fs-base-sm'],
      ['--dm-text-md', '--fs-base'],
      ['--dm-text-lg', '--fs-lg'],
      ['--dm-text-xl', '--fs-xl'],
      ['--dm-text-h1', '--fs-h1-cabinet'],
      ['--dm-text-kpi', '--fs-kpi'],
      ['--dm-text-hero', '--fs-display'],
    ] as const) {
      expect(light[legacy], legacy).toBe(`VAR(${target.toUpperCase()})`)
    }
  })
})
