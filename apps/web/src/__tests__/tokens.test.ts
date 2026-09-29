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
  font: { family: string; weights: number[] }
}

/** Значение токена без различий в пробелах и регистре (в градиентах и тенях пробелы не значимы). */
const norm = (value: string) => value.replace(/\s+/g, ' ').trim().toUpperCase()

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
})
