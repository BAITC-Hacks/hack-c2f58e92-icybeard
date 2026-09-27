/** Проверки форм без сессии и аккаунта: БИН, почта, телефон Казахстана, пароль по политике realm, код из письма. */

/** БИН — ровно 12 цифр. */
export function isBin(value: string): boolean {
  return /^\d{12}$/.test(value.trim())
}

/** Почта: одна «@», домен с точкой, без пробелов. */
export function isEmail(value: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(value.trim())
}

/** Цифры номера без форматирования; ведущая 8 → 7. */
export function phoneDigits(value: string): string {
  const digits = value.replace(/\D/g, '')
  return digits.length === 11 && digits.startsWith('8') ? `7${digits.slice(1)}` : digits
}

/** Телефон Казахстана: +7 и 10 цифр (мобильный или городской). */
export function isKzPhone(value: string): boolean {
  const digits = phoneDigits(value)
  return digits.length === 11 && digits.startsWith('7')
}

/** «+7 727 000 00 00» из любых 11 цифр. */
export function formatKzPhone(value: string): string {
  const d = phoneDigits(value)
  if (d.length !== 11) return value
  return `+${d[0]} ${d.slice(1, 4)} ${d.slice(4, 7)} ${d.slice(7, 9)} ${d.slice(9, 11)}`
}

/** Код подтверждения почты — 6 цифр. */
export const CODE_LENGTH = 6
export function isCode(value: string): boolean {
  return new RegExp(`^\\d{${CODE_LENGTH}}$`).test(value)
}

/** Политика паролей realm (docs/rbac.md): length(12) and upperCase(1) and lowerCase(1) and digits(1) and notUsername. */
export const PASSWORD_MIN_LENGTH = 12
export type PasswordRule = 'length' | 'upper' | 'lower' | 'digit' | 'notUsername'
export const PASSWORD_RULES: readonly PasswordRule[] = ['length', 'upper', 'lower', 'digit', 'notUsername']

export function passwordChecks(password: string, username = ''): Record<PasswordRule, boolean> {
  const login = username.trim().toLowerCase()
  return {
    length: password.length >= PASSWORD_MIN_LENGTH,
    upper: /\p{Lu}/u.test(password),
    lower: /\p{Ll}/u.test(password),
    digit: /\d/.test(password),
    notUsername: password.length > 0 && (!login || password.toLowerCase() !== login),
  }
}

export function passwordValid(password: string, username = ''): boolean {
  return Object.values(passwordChecks(password, username)).every(Boolean)
}

/** Надёжность 0…4 для шкалы: выполненные правила плюс бонус за длину ≥ 16 и символы. */
export function passwordStrength(password: string, username = ''): 0 | 1 | 2 | 3 | 4 {
  if (!password) return 0
  const checks = passwordChecks(password, username)
  const passed = [checks.length, checks.upper && checks.lower, checks.digit].filter(Boolean).length
  const bonus = password.length >= 16 || /[^\p{L}\d]/u.test(password) ? 1 : 0
  return Math.min(4, Math.max(1, passed + (passwordValid(password, username) ? bonus : 0))) as 1 | 2 | 3 | 4
}

/** Часовые пояса Казахстана (с 01.03.2024 вся страна — UTC+5). */
export const TIME_ZONES = ['Asia/Almaty', 'Asia/Qostanay', 'Asia/Qyzylorda', 'Asia/Aqtobe', 'Asia/Aqtau', 'Asia/Atyrau', 'Asia/Oral'] as const

/** «Asia/Almaty · GMT+5» — смещение по данным браузера на сегодня. */
export function timeZoneLabel(zone: string, at = new Date()): string {
  try {
    const offset = new Intl.DateTimeFormat('en-US', { timeZone: zone, timeZoneName: 'shortOffset' }).formatToParts(at).find((p) => p.type === 'timeZoneName')?.value
    return offset ? `${zone.replace('Asia/', '')} · ${offset}` : zone
  } catch {
    return zone
  }
}
