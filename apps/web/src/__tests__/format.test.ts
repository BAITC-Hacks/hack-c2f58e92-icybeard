import { describe, expect, it } from 'vitest'
import { days, indexColor, pct, signed } from '@/lib/format'

describe('format', () => {
  it('formats days, percent and signed deltas', () => {
    expect(days(12.4)).toBe('12')
    expect(days(null)).toBe('—')
    expect(pct(0.456)).toBe('46 %')
    expect(signed(-3.25)).toBe('−3.3')
    expect(signed(0)).toBe('0.0')
  })

  it('maps the index to a hue from red to green, lighter on the dark theme', () => {
    expect(indexColor(0)).toBe('hsl(0 55% 42%)')
    expect(indexColor(100)).toBe('hsl(120 55% 42%)')
    expect(indexColor(50, true)).toBe('hsl(60 55% 58%)')
  })
})
