import type { PatientRoute, RouteDecision, RouteSignal } from '@/api/types'

/** Открытый сигнал гражданина (врач ещё не ответил); null — сигналов нет. */
export function openSignal(route: Pick<PatientRoute, 'signals'>): RouteSignal | null {
  return route.signals.find((s) => s.open) ?? null
}

/** Открытая просьба «рассмотреть организацию быстрее» — у альтернативы вместо кнопки показывается «запрос отправлен». */
export function openRequest(route: Pick<PatientRoute, 'signals'>): RouteSignal | null {
  return route.signals.find((s) => s.open && s.kind === 'request_redirect') ?? null
}

export type RouteEntry = { at: string; kind: 'decision'; decision: RouteDecision } | { at: string; kind: 'signal'; signal: RouteSignal }

/** Решения врача и сигналы гражданина одной лентой, свежие первыми (ISO-время сравнивается как строки). */
export function routeEntries(route: Pick<PatientRoute, 'decisions' | 'signals'>): RouteEntry[] {
  const rows: RouteEntry[] = [
    ...route.decisions.map((d) => ({ at: d.recordedAt, kind: 'decision' as const, decision: d })),
    ...route.signals.map((s) => ({ at: s.recordedAt, kind: 'signal' as const, signal: s })),
  ]
  return rows.sort((a, b) => (a.at < b.at ? 1 : a.at > b.at ? -1 : 0))
}

/** Коды стадий маршрута из Стандарта ҚР-ДСМ-27 в порядке прохождения (docs/api.md, раздел Route). */
export const STAGE_CODES = ['referral_issued', 'examination', 'waitlisted', 'transfer', 'date_assigned', 'hospitalized', 'refused'] as const
export type StageCode = (typeof STAGE_CODES)[number]

/** Коды следующего шага рабочего списка (WorklistBuilder.Action* в API); подпись — ключ doctor.worklist.action.<code>. */
export const NEXT_ACTION_CODES = [
  'redirect_faster', 'review_before_call', 'clarify_date', 'wait_for_call', 'decision_made', 'await_consent', 'await_confirmation', 'confirm_admission',
  'transferred_out', 'admit_on_date', 'date_overdue', 'discharge_when_done', 'confirm_withdrawal', 'closed',
] as const
export type NextActionCode = (typeof NEXT_ACTION_CODES)[number]

export type Tone = 'success' | 'info' | 'warn' | 'danger' | 'secondary'

/** Ключ словаря для кода следующего шага; незнакомый или пустой код → null, и клиент показывает русскую подпись API. */
export function nextActionKey(code: string | null | undefined): string | null {
  return NEXT_ACTION_CODES.includes(code as NextActionCode) ? `doctor.worklist.action.${code}` : null
}

export function stageIndex(code: string): number {
  return STAGE_CODES.indexOf(code as StageCode)
}

export function stageTone(code: string): Tone {
  if (code === 'refused') return 'danger'
  if (code === 'hospitalized') return 'success'
  if (code === 'date_assigned') return 'info'
  return 'secondary'
}

export function checklistTone(status: string): Tone {
  if (status === 'valid') return 'success'
  if (status === 'expiring') return 'warn'
  if (status === 'expired') return 'danger'
  return 'secondary'
}

export function outcomeTone(outcome: string): Tone {
  if (outcome === 'hospitalized') return 'success'
  if (outcome === 'refused') return 'danger'
  return 'secondary'
}

/** «Сегодня» по Казахстану (Asia/Almaty) как `YYYY-MM-DD` — так же считает сервер для дат госпитализации. */
export function almatyToday(now = new Date()): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Almaty', year: 'numeric', month: '2-digit', day: '2-digit' }).format(now)
}

/** `YYYY-MM-DD` + n дней (календарных). */
export function addDays(iso: string, n: number): string {
  const d = new Date(`${iso}T00:00:00Z`)
  d.setUTCDate(d.getUTCDate() + n)
  return d.toISOString().slice(0, 10)
}

/** `YYYY-MM-DD` или ISO 8601 → `дд.мм.гггг`; пустое значение → «—», незнакомый формат — как есть. */
export function dateShort(iso: string | null | undefined): string {
  if (!iso) return '—'
  const match = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso)
  return match ? `${match[3]}.${match[2]}.${match[1]}` : iso
}
