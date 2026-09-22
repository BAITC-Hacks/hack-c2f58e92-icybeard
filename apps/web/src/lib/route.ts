/** Коды стадий маршрута из Стандарта ҚР-ДСМ-27 в порядке прохождения (docs/api.md, раздел Route). */
export const STAGE_CODES = ['referral_issued', 'examination', 'waitlisted', 'date_assigned', 'hospitalized', 'refused'] as const
export type StageCode = (typeof STAGE_CODES)[number]

/** Коды следующего шага рабочего списка (WorklistBuilder.Action* в API); подпись — ключ doctor.worklist.action.<code>. */
export const NEXT_ACTION_CODES = ['redirect_faster', 'review_before_call', 'clarify_date', 'wait_for_call'] as const
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

/** `YYYY-MM-DD` или ISO 8601 → `дд.мм.гггг`; пустое значение → «—», незнакомый формат — как есть. */
export function dateShort(iso: string | null | undefined): string {
  if (!iso) return '—'
  const match = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso)
  return match ? `${match[3]}.${match[2]}.${match[1]}` : iso
}
