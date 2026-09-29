import { ref } from 'vue'
import { journal } from '@/api/endpoints'
import type { IncomingReferral } from '@/api/types'

/** Входящие направления в свою организацию (задача 4): список из /journal/referrals/incoming и подтверждение приёма.
 * Подтвердить можно только направление с patientConsent === 'accepted' — сервер отклонит остальные 409. */
export function useIncomingReferrals() {
  const items = ref<IncomingReferral[]>([])
  const error = ref<unknown>(null)
  const loading = ref(false)
  const acting = ref<string | null>(null)
  const showConfirmed = ref(false)
  const severeOnly = ref(false)

  async function load() {
    loading.value = true
    error.value = null
    try {
      items.value = await journal.referralsIncoming({ includeConfirmed: showConfirmed.value || undefined, severe: severeOnly.value || undefined })
    } catch (e) {
      error.value = e
    } finally {
      loading.value = false
    }
  }

  /** decisionId и patientRef — из той же строки списка, что и кнопка «Подтвердить». */
  async function confirm(decisionId: string, patientRef: string, comment?: string): Promise<boolean> {
    acting.value = decisionId
    try {
      await journal.confirmReferral(decisionId, { patientRef, comment: comment?.trim() || undefined }, crypto.randomUUID())
      await load()
      return true
    } catch (e) {
      error.value = e
      return false
    } finally {
      acting.value = null
    }
  }

  /** Выписка/эпикриз (задача 11): доступна только когда i.confirmed && !i.discharged — сервер и так это проверит
   * (409), но фронтенд скрывает действие заранее, чтобы не полагаться на обработку ошибки как на основной путь. */
  async function discharge(decisionId: string, patientRef: string, summary: string): Promise<boolean> {
    acting.value = decisionId
    try {
      await journal.dischargeReferral(decisionId, { patientRef, summary: summary.trim() }, crypto.randomUUID())
      await load()
      return true
    } catch (e) {
      error.value = e
      return false
    } finally {
      acting.value = null
    }
  }

  return { items, error, loading, acting, showConfirmed, severeOnly, load, confirm, discharge }
}
