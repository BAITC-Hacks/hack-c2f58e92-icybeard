/** Данные старше этого числа дней показываются баннером «Данные на …» (W-States, «данные устарели»). */
export const STALE_AFTER_DAYS = 7

export function isStale(asOf: string | null | undefined, now = Date.now()): boolean {
  if (!asOf) return false
  const at = new Date(asOf).getTime()
  return !Number.isNaN(at) && now - at > STALE_AFTER_DAYS * 86_400_000
}
