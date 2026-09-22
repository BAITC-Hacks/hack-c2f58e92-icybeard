import { describe, expect, it } from 'vitest'
import { kk } from '@/i18n/kk'
import { ru } from '@/i18n/ru'

function keys(node: unknown, prefix = ''): string[] {
  if (typeof node !== 'object' || node === null) return [prefix]
  return Object.entries(node).flatMap(([key, value]) => keys(value, prefix ? `${prefix}.${key}` : key))
}

describe('i18n dictionaries', () => {
  it('kk has exactly the keys ru has', () => {
    const missing = keys(ru).filter((key) => !keys(kk).includes(key))
    const extra = keys(kk).filter((key) => !keys(ru).includes(key))
    expect({ missing, extra }).toEqual({ missing: [], extra: [] })
  })

  it('has no demo-mode strings left', () => {
    for (const dictionary of [ru, kk]) {
      const values = JSON.stringify(dictionary).toLowerCase()
      expect(values).not.toContain('демо-режим')
      expect(values).not.toContain('darumen.role')
    }
  })
})
