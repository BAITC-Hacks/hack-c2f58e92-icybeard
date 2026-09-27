import { describe, expect, it } from 'vitest'
import { formatKzPhone, isBin, isCode, isEmail, isKzPhone, passwordChecks, passwordStrength, passwordValid } from '@/lib/validation'

describe('form validation', () => {
  it('BIN is exactly 12 digits', () => {
    expect(isBin('123456789012')).toBe(true)
    expect(isBin('12345678901')).toBe(false)
    expect(isBin('12345678901a')).toBe(false)
  })

  it('email and Kazakhstan phone', () => {
    expect(isEmail('a.seitkali@almaty-onco.kz')).toBe(true)
    expect(isEmail('no-at.kz')).toBe(false)
    expect(isKzPhone('+7 727 000 00 00')).toBe(true)
    expect(isKzPhone('8 701 123 45 67')).toBe(true)
    expect(isKzPhone('+7 727 000')).toBe(false)
    expect(formatKzPhone('87011234567')).toBe('+7 701 123 45 67')
  })

  it('6-digit code', () => {
    expect(isCode('394112')).toBe(true)
    expect(isCode('3941')).toBe(false)
  })

  it('password follows the realm policy: 12+, upper, lower, digit, not the username', () => {
    expect(passwordValid('Darumen-2026x')).toBe(true)
    expect(passwordValid('darumen')).toBe(false)
    expect(passwordChecks('short1A', '').length).toBe(false)
    expect(passwordChecks('ALLUPPERCASE12', '').lower).toBe(false)
    expect(passwordChecks('Aseitkali1234', 'aseitkali1234').notUsername).toBe(false)
    expect(passwordStrength('')).toBe(0)
    expect(passwordStrength('Darumen-2026x')).toBe(4)
  })
})
