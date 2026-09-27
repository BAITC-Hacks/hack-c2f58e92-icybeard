import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

// vitest отдаёт импорт .css пустой строкой даже с ?raw — читаем файл напрямую (cwd vitest — apps/web)
const css = readFileSync(resolve(process.cwd(), 'src/styles/tokens.css'), 'utf8')
// design/tokens.json лежит в корне репозитория, вне apps/web: статический импорт ломает vue-tsc в Docker-сборке
// (в образ копируется только apps/web), поэтому читаем файл так же, как tokens.css
const tokens = JSON.parse(readFileSync(resolve(process.cwd(), '../../design/tokens.json'), 'utf8')) as Record<string, Record<string, string>>

/** Роль из design/tokens.json → переменная в tokens.css. */
const VARS: Record<string, string> = {
  surface: '--dm-bg', card: '--dm-surface', ink: '--dm-ink', muted: '--dm-muted', faint: '--dm-faint', hairline: '--dm-hairline',
  accent: '--dm-accent', accentHover: '--dm-accent-hover', accentSoft: '--dm-accent-soft', neutralSoft: '--dm-neutral-soft',
  ok: '--dm-ok', okSoft: '--dm-ok-soft', warn: '--dm-warn', warnSoft: '--dm-warn-soft', warnStrong: '--dm-warn-strong',
  danger: '--dm-danger', dangerSoft: '--dm-danger-soft', info: '--dm-info', infoSoft: '--dm-info-soft', ai: '--dm-ai', aiSoft: '--dm-ai-soft',
  benchSoft: '--dm-bench-soft', map1: '--dm-map-1', map2: '--dm-map-2', map3: '--dm-map-3', map4: '--dm-map-4', map5: '--dm-map-5',
}

function block(selector: string): Record<string, string> {
  const start = css.indexOf(`${selector} {`)
  const body = css.slice(start, css.indexOf('}', start))
  return Object.fromEntries([...body.matchAll(/(--dm-[\w-]+):\s*([^;]+);/g)].map((m) => [m[1], m[2]!.trim().toUpperCase()]))
}

describe('design tokens', () => {
  it.each([
    ['light', ':root'],
    ['dark', 'html.darumen-dark'],
  ])('%s theme in tokens.css matches design/tokens.json', (theme, selector) => {
    const vars = block(selector)
    const expected = tokens[theme]!
    for (const [role, variable] of Object.entries(VARS)) {
      expect(vars[variable], `${variable} for ${role}`).toBe(expected[role]!.toUpperCase())
    }
  })

  it.each(['light', 'dark'])('maps every %s role of design/tokens.json to a CSS variable', (theme) => {
    expect(Object.keys(tokens[theme]!).filter((role) => !(role in VARS))).toEqual([])
  })

  it('uses the violet accent as the primary colour, with white text on it in the light theme', () => {
    const light = block(':root')
    expect(light['--dm-primary']).toBe(tokens.light!.accent!.toUpperCase())
    expect(light['--dm-primary-contrast']).toBe('#FFFFFF')
    expect(block('html.darumen-dark')['--dm-primary']).toBe(tokens.dark!.accent!.toUpperCase())
  })

  it('keeps the base size and family the mobile app uses', () => {
    expect(css).toContain(`--dm-text-base: ${tokens.font.baseSize}px`)
    expect(css).toContain(`'${tokens.font.family}`)
  })
})
