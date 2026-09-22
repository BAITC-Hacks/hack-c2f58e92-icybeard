import { describe, expect, it } from 'vitest'
import { NEXT_ACTION_CODES, STAGE_CODES, checklistTone, dateShort, nextActionKey, outcomeTone, stageIndex, stageTone } from '@/lib/route'

describe('route helpers', () => {
  it('maps next-action codes to dictionary keys and leaves unknown codes to the raw API text', () => {
    expect(NEXT_ACTION_CODES).toHaveLength(4)
    expect(nextActionKey('redirect_faster')).toBe('doctor.worklist.action.redirect_faster')
    expect(nextActionKey('')).toBeNull()
    expect(nextActionKey(undefined)).toBeNull()
    expect(nextActionKey('something_new')).toBeNull()
  })

  it('orders stages as the standard does and tolerates unknown codes', () => {
    expect(STAGE_CODES).toHaveLength(6)
    expect(stageIndex('referral_issued')).toBe(0)
    expect(stageIndex('hospitalized')).toBeGreaterThan(stageIndex('waitlisted'))
    expect(stageIndex('unknown')).toBe(-1)
  })

  it('maps statuses to tones without throwing on raw values', () => {
    expect(stageTone('refused')).toBe('danger')
    expect(stageTone('waitlisted')).toBe('secondary')
    expect(checklistTone('valid')).toBe('success')
    expect(checklistTone('expiring')).toBe('warn')
    expect(checklistTone('expired')).toBe('danger')
    expect(checklistTone('weird')).toBe('secondary')
    expect(outcomeTone('hospitalized')).toBe('success')
    expect(outcomeTone('refused')).toBe('danger')
  })

  it('formats dates as dd.mm.yyyy and keeps unknown formats', () => {
    expect(dateShort('2025-02-21')).toBe('21.02.2025')
    expect(dateShort('2026-09-22T10:15:00+05:00')).toBe('22.09.2026')
    expect(dateShort(null)).toBe('—')
    expect(dateShort('вчера')).toBe('вчера')
  })
})
