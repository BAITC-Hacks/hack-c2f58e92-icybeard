import { describe, expect, it } from 'vitest'
import type { RouteDecision, RouteSignal } from '@/api/types'
import { NEXT_ACTION_CODES, STAGE_CODES, checklistTone, dateShort, nextActionKey, openRequest, openSignal, outcomeTone, routeEntries, stageIndex, stageTone } from '@/lib/route'

const signal = (over: Partial<RouteSignal>): RouteSignal => ({
  decisionId: 'a', recordedAt: '2026-09-25T10:00:00+00:00', kind: 'still_waiting', toMoCode: null, toMoName: null, comment: null, open: false, ...over,
})
const decision = (over: Partial<RouteDecision>): RouteDecision => ({
  decisionId: 'd', role: 'doctor', recordedAt: '2026-09-24T10:00:00+00:00', fromMoCode: null, toMoCode: '22GN', toMoName: 'Больница №2', reason: null, kind: 'redirect', ...over,
})

describe('route signals', () => {
  it('finds the open signal and the open request, ignoring answered ones', () => {
    const answered = signal({ decisionId: 'x', kind: 'request_redirect', toMoCode: '22GN', open: false })
    const open = signal({ decisionId: 'y', kind: 'request_redirect', toMoCode: '028B', open: true, recordedAt: '2026-09-26T10:00:00+00:00' })
    expect(openSignal({ signals: [open, answered] })?.decisionId).toBe('y')
    expect(openRequest({ signals: [open, answered] })?.toMoCode).toBe('028B')
    expect(openSignal({ signals: [answered] })).toBeNull()
    expect(openRequest({ signals: [signal({ kind: 'still_waiting', open: true })] })).toBeNull()
  })

  it('merges decisions and signals newest first', () => {
    const entries = routeEntries({
      decisions: [decision({ decisionId: 'd1', recordedAt: '2026-09-24T10:00:00+00:00' })],
      signals: [signal({ decisionId: 's1', recordedAt: '2026-09-25T10:00:00+00:00' }), signal({ decisionId: 's0', recordedAt: '2026-09-20T10:00:00+00:00' })],
    })
    expect(entries.map((e) => (e.kind === 'decision' ? e.decision.decisionId : e.signal.decisionId))).toEqual(['s1', 'd1', 's0'])
  })
})

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
