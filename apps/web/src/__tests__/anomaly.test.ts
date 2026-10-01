import { describe, expect, it } from 'vitest'
import { describeEntity, deviationText, severityLabel, statusLabel, streamTitle, type EntityNames } from '@/lib/anomaly'

const names: EntityNames = {
  region: (kato) => ({ '75': 'г. Алматы' })[kato] ?? kato,
  profile: (code) => ({ '381': 'Офтальмологические' })[code] ?? code,
  organization: (moCode) => ({ '028B': 'Институт глазных болезней' })[moCode] ?? moCode,
}

describe('anomaly labels', () => {
  it('names region, organization and profile instead of codes', () => {
    expect(describeEntity({ region_kato: '75', profile_code: '381' }, '75', names)).toEqual(['г. Алматы', 'профиль «Офтальмологические»'])
    expect(describeEntity({ region_kato: '75', mo_key: 'городская больница 1' }, '75', names)).toEqual(['г. Алматы', 'Городская больница 1'])
    expect(describeEntity({ region_kato: '75', mo_key: 'x', mo_code: '028B' }, '75', names)).toEqual(['г. Алматы', 'Институт глазных болезней'])
  })

  it('takes the region from the signal when the entity has none and keeps unknown keys readable', () => {
    expect(describeEntity({ localization: 'C50' }, null, names)).toEqual(['локализация C50'])
    expect(describeEntity({ localization: 'ALL' }, null, names)).toEqual(['все локализации'])
    expect(describeEntity({ vaccination_plan: '12' }, '75', names)).toEqual(['г. Алматы', 'план вакцинации 12'])
    expect(describeEntity({ region_kato: 'unknown', drug_mnn_id: '77' }, null, names)).toEqual(['регион не определён', 'МНН 77'])
    expect(describeEntity({ other: 'v' }, null, names)).toEqual(['other: v'])
  })

  it('translates stream, severity, status and deviation', () => {
    expect(streamTitle('onco_monthly')).toBe('Онкология, впервые выявленные')
    expect(streamTitle('custom')).toBe('custom')
    expect(severityLabel('critical')).toBe('сильное отклонение')
    expect(statusLabel('dismissed')).toBe('ложный сигнал')
    expect(deviationText(10, 5)).toBe('больше обычного')
    expect(deviationText(1, 5)).toBe('меньше обычного')
  })
})
