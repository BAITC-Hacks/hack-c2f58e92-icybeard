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
  accent: '--dm-accent', accentSoft: '--dm-accent-soft', ok: '--dm-ok', okSoft: '--dm-ok-soft', warn: '--dm-warn', warnSoft: '--dm-warn-soft',
  danger: '--dm-danger', dangerSoft: '--dm-danger-soft', neutralSoft: '--dm-neutral-soft',
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

  it('keeps the base size and family the mobile app uses', () => {
    expect(css).toContain(`--dm-text-base: ${tokens.font.baseSize}px`)
    expect(css).toContain(`'${tokens.font.family}`)
  })
})
