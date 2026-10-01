import { describe, expect, it } from 'vitest'
import { describeChoice, describeSubject, organizationOf, referralSubjectId, roleLabel, subjectLabel, type DecisionNames } from '@/lib/decision'

const names: DecisionNames = {
  region: (kato) => ({ '75': 'г. Алматы' })[kato] ?? kato,
  profile: (code) => ({ '381': 'Офтальмологические' })[code] ?? code,
  organization: (moCode) => ({ '028B': 'Институт глазных болезней' })[moCode] ?? moCode,
}

describe('decision labels', () => {
  it('shows organizations by name and statuses in words', () => {
    expect(describeChoice({ moCode: '028B' }, names)).toBe('Институт глазных болезней (028B)')
    expect(describeChoice({ moCode: '9999' }, names)).toBe('9999 (9999)')
    expect(describeChoice({ status: 'acknowledged' }, names)).toBe('подтверждён')
    expect(describeChoice(null, names)).toBe('—')
    expect(describeChoice({ other: 1 }, names)).toBe('{"other":1}')
    expect(organizationOf({ moCode: '028B' })).toBe('028B')
    expect(organizationOf({ status: 'open' })).toBeNull()
  })

  it('describes the referral subject built by the assistant', () => {
    const id = referralSubjectId('75', '028B', '381', '2025-04-01')
    expect(describeSubject('referral', id, names)).toBe('г. Алматы · Офтальмологические · 2025-04-01')
    expect(describeSubject('anomaly', '0123456789abcdef', names)).toBe('сигнал 01234567')
    expect(describeSubject('other', 'x', names)).toBe('x')
  })

  it('translates subject and role', () => {
    expect(subjectLabel('referral')).toBe('новое направление')
    expect(subjectLabel('anomaly')).toBe('сигнал по данным')
    expect(subjectLabel('route')).toBe('пациент в очереди')
    expect(roleLabel('regulator')).toBe('регулятор')
  })
})
