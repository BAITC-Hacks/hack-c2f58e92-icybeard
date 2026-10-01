import { ref } from 'vue'
import { ApiError } from '@/api/client'
import { journal } from '@/api/endpoints'
import type { IncomingReferral } from '@/api/types'

/** Входящие направления в свою организацию: список из /journal/referrals/incoming и действия принимающей больницы —
 * подтвердить с датой, отказать, перенести дату, отметить госпитализацию или неявку, выписать. Какие кнопки показать —
 * только из item.allowed (сервер считает по журналу и отклонит остальное 409). Для ролей без своей организации
 * (администратор системы, регулятор) больница задаётся через moCode — без него список не запрашивается
 * (сервер ответил бы 422 «нужна организация»). */
export function useIncomingReferrals() {
  const items = ref<IncomingReferral[]>([])
  /** Организация, чьи входящие смотрим: null — своя (клейм mo_code пользователя). */
  const moCode = ref<string | null>(null)
  const error = ref<unknown>(null)
  const loading = ref(false)
  const acting = ref<string | null>(null)
  // по умолчанию — все входящие (и подтверждённые, и выписанные): отбор делают фильтры на странице
  const showConfirmed = ref(true)
  const severeOnly = ref(false)

  async function load() {
    loading.value = true
    error.value = null
    try {
      items.value = await journal.referralsIncoming({ moCode: moCode.value || undefined, includeConfirmed: showConfirmed.value || undefined, severe: severeOnly.value || undefined })
    } catch (e) {
      error.value = e
    } finally {
      loading.value = false
    }
  }

  async function run(decisionId: string, request: (key: string) => Promise<unknown>): Promise<boolean> {
    acting.value = decisionId
    try {
      await request(crypto.randomUUID())
      await load()
      return true
    } catch (e) {
      // 409 — состояние уже изменилось (пациент отозвал согласие, коллега успел раньше): обновляем список
      if (e instanceof ApiError && e.status === 409) await load()
      error.value = e
      return false
    } finally {
      acting.value = null
    }
  }

  const trim = (v?: string) => v?.trim() || undefined

  /** Подтвердить приём и назначить дату госпитализации (сегодня..+30 дней). */
  const confirm = (i: IncomingReferral, plannedAt: string, comment?: string) =>
    run(i.decisionId, (key) => journal.confirmReferral(i.decisionId, { patientRef: i.patientRef, plannedAt, comment: trim(comment) }, key))
  const reject = (i: IncomingReferral, reason: string) =>
    run(i.decisionId, (key) => journal.rejectReferral(i.decisionId, { patientRef: i.patientRef, reason: reason.trim() }, key))
  const reschedule = (i: IncomingReferral, plannedAt: string, reason: string) =>
    run(i.decisionId, (key) => journal.rescheduleReferral(i.decisionId, { patientRef: i.patientRef, plannedAt, reason: reason.trim() }, key))
  const admit = (i: IncomingReferral) => run(i.decisionId, (key) => journal.admitReferral(i.decisionId, { patientRef: i.patientRef }, key))
  const noShow = (i: IncomingReferral, reason?: string) =>
    run(i.decisionId, (key) => journal.noShowReferral(i.decisionId, { patientRef: i.patientRef, reason: trim(reason) }, key))
  const discharge = (i: IncomingReferral, summary: string) =>
    run(i.decisionId, (key) => journal.dischargeReferral(i.decisionId, { patientRef: i.patientRef, summary: summary.trim() }, key))

  return { items, error, loading, acting, moCode, showConfirmed, severeOnly, load, confirm, reject, reschedule, admit, noShow, discharge }
}
