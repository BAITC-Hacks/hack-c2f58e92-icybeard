import { i18n } from '@/i18n'

/** BCP-47 тег текущего языка интерфейса: числа и даты форматируются по нему, а не по настройкам браузера. */
export function localeTag(): string {
  return i18n.global.locale.value === 'kk' ? 'kk-KZ' : 'ru-RU'
}

export function days(value: number | null | undefined, digits = 0): string {
  if (value === null || value === undefined || Number.isNaN(value)) return '—'
  return value.toFixed(digits)
}

export function pct(value: number | null | undefined, digits = 0): string {
  if (value === null || value === undefined || Number.isNaN(value)) return '—'
  return `${(value * 100).toFixed(digits)} %`
}

export function num(value: number | null | undefined, digits = 0, locale = localeTag()): string {
  if (value === null || value === undefined || Number.isNaN(value)) return '—'
  return new Intl.NumberFormat(locale, { minimumFractionDigits: digits, maximumFractionDigits: digits }).format(value)
}

export function signed(value: number, digits = 1): string {
  const sign = value > 0 ? '+' : value < 0 ? '−' : ''
  return `${sign}${Math.abs(value).toFixed(digits)}`
}

/** `YYYY-MM-DD` — как локальная дата (без сдвига часовым поясом), ISO 8601 со временем — как момент. */
function parse(iso: string): Date {
  const dateOnly = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso)
  return dateOnly ? new Date(Number(dateOnly[1]), Number(dateOnly[2]) - 1, Number(dateOnly[3])) : new Date(iso)
}

export function date(iso: string | null | undefined, locale = localeTag()): string {
  if (!iso) return '—'
  const parsed = parse(iso)
  return Number.isNaN(parsed.getTime()) ? iso : new Intl.DateTimeFormat(locale, { day: '2-digit', month: '2-digit', year: 'numeric' }).format(parsed)
}

export function dateTime(iso: string | null | undefined, locale = localeTag()): string {
  if (!iso) return '—'
  const parsed = parse(iso)
  return Number.isNaN(parsed.getTime())
    ? iso
    : new Intl.DateTimeFormat(locale, { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' }).format(parsed)
}

/** «28.09 · 03:14» — для колонок «последний вход», «загрузка» (год понятен из контекста таблицы). Формат досок
 * одинаков для RU и KK: ICU для kk-KZ даёт «09-28», поэтому день и месяц собираются вручную. */
export function dateTimeShort(iso: string | null | undefined): string {
  if (!iso) return '—'
  const parsed = parse(iso)
  if (Number.isNaN(parsed.getTime())) return iso
  const two = (n: number) => String(n).padStart(2, '0')
  return `${two(parsed.getDate())}.${two(parsed.getMonth() + 1)} · ${two(parsed.getHours())}:${two(parsed.getMinutes())}`
}

/** Ступень шкалы карты для индекса доступности (0…100, выше = доступнее): 1 — 60 и выше, 2 — 50–59, 3 — 40–49,
 * 4 — 30–39, 5 — ниже 30. Цвета ступеней — рамп --dm-map-1…5 (зелёный → жёлтый → оранжевый → красный): чем
 * краснее, тем хуже доступность. Индекс относительный (среднее перцентильных рангов), поэтому значения держатся
 * в середине шкалы и границы идут через 10 пунктов. */
export const INDEX_SCALE_STEPS = [60, 50, 40, 30] as const
export function indexStep(value: number): 1 | 2 | 3 | 4 | 5 {
  const step = INDEX_SCALE_STEPS.filter((edge) => value < edge).length
  return (step + 1) as 1 | 2 | 3 | 4 | 5
}

export function indexColor(value: number): string {
  return `var(--dm-map-${indexStep(value)})`
}

/** Риск отказа словами относительно среднего по стране (11 % направлений заканчиваются отказом), на языке интерфейса. */
export function refusalWords(p: number | null | undefined): string {
  if (p === null || p === undefined || Number.isNaN(p)) return '—'
  const key = p >= 0.165 ? 'above' : p <= 0.055 ? 'below' : 'average'
  return i18n.global.t(`format.refusal.${key}`)
}

export function severityTone(severity: string): 'danger' | 'warn' | 'info' {
  if (severity === 'critical') return 'danger'
  if (severity === 'warning') return 'warn'
  return 'info'
}

/** Организационно-правовые формы, которые убираются из начала названия (длинные раньше коротких, без учёта регистра). */
const LEGAL_FORMS = [
  'Коммунальное государственное предприятие на праве хозяйственного ведения',
  'Государственное коммунальное предприятие на праве хозяйственного ведения',
  'Республиканское государственное предприятие на праве хозяйственного ведения',
  'Государственное коммунальное казённое предприятие', 'Государственное коммунальное казенное предприятие',
  'Коммунальное государственное казённое предприятие', 'Коммунальное государственное казенное предприятие',
  'Коммунальное государственное предприятие', 'Государственное коммунальное предприятие', 'Республиканское государственное предприятие',
  'Товарищество с ограниченной ответственностью', 'Некоммерческое акционерное общество', 'Акционерное общество',
  'Коммунальное государственное учреждение', 'Республиканское государственное учреждение', 'Государственное учреждение',
  'Частное учреждение', 'Учреждение', 'Индивидуальный предприниматель',
  'КГП на ПХВ', 'ГКП на ПХВ', 'РГП на ПХВ', 'КГППХВ', 'ГКППХВ', 'РГППХВ', 'ГККП', 'КГП', 'ГКП', 'РГП', 'КГУ', 'РГУ', 'ТОО', 'НАО', 'АО', 'ГУ', 'ЧУ', 'ИП',
]
const OPEN_QUOTES = '"«„“'
const CLOSE_QUOTES = '"»“”'
/** Хвост после закрывающей кавычки — принадлежность («Управления здравоохранения…», «на праве…»): по нему узнаётся конец имени. */
const AFFILIATION_TAIL = /^(на праве|управлени|министерств|комитет|департамент|акимат|уоз|уз |мз |ру |гу )/iu
// \b в JS не знает кириллицу — граница слова через lookbehind по букве
const ORDER_FRAGMENT = /(?<!\p{L})ордена\s+["«„“][^"»“”]*["»“”]\s*/giu

function stripLegalForm(name: string): string {
  const lower = name.toLowerCase()
  for (const form of LEGAL_FORMS) {
    const f = form.toLowerCase()
    if (lower.startsWith(f) && (name.length === f.length || /[\s"«„“]/u.test(name[f.length] ?? ''))) return name.slice(f.length).trim()
  }
  return name
}

/** Позиция закрывающей кавычки для имени, начатого кавычкой в позиции 0: первая кавычка, за которой идёт конец строки
 * или принадлежность («Управления…»); иначе последняя кавычка. Так переживаются лишняя кавычка в конце
 * («…больница №4" Управления … Алматы"») и вложенные («Реабилитационный центр "Алау" Управления…»). */
function closingQuote(text: string): number {
  const candidates: number[] = []
  for (let i = 1; i < text.length; i += 1) if (CLOSE_QUOTES.includes(text[i]!)) candidates.push(i)
  if (candidates.length === 0) return -1
  for (const i of candidates) {
    const tail = text.slice(i + 1).trim()
    if (tail === '' || AFFILIATION_TAIL.test(tail)) return i
  }
  return candidates[candidates.length - 1]!
}

/** Короткое имя организации: без организационно-правовой формы и принадлежности («Достар Мед» вместо
 * «Товарищество с ограниченной ответственностью "Достар Мед"»). Полное имя остаётся для title и подстрок. */
export function shortOrgName(name: string | null | undefined): string {
  if (!name) return ''
  // «на праве хозяйственного ведения "…"» встречается и без формы собственности впереди
  const rest = stripLegalForm(name.trim()).replace(/^на праве (хозяйственного ведения|оперативного управления)\s*/iu, '')
  if (!rest) return name.trim()
  let short = rest
  if (OPEN_QUOTES.includes(rest[0]!)) {
    const close = closingQuote(rest)
    short = close > 0 ? rest.slice(1, close) : rest.slice(1)
    // нечётное число кавычек внутри — внешняя закрывающая слилась с внутренней («…центр "Алау" Управления…»): оставляем её в имени
    const innerQuotes = [...short].filter((ch) => CLOSE_QUOTES.includes(ch) || OPEN_QUOTES.includes(ch)).length
    if (close > 0 && innerQuotes % 2 === 1) short = rest.slice(1, close + 1)
  }
  short = short.replace(ORDER_FRAGMENT, '').replace(/\s{2,}/g, ' ').trim()
  return short || name.trim()
}
