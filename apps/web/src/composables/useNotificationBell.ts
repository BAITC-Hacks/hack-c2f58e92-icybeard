import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { journal, route as routeApi } from '@/api/endpoints'
import type { CitizenNotifications, NotificationBell, NotificationKind } from '@/api/types'
import { useAuthStore } from '@/stores/auth'

const POLL_INTERVAL_MS = 45_000

/** Колокольчик (внутрисистемные уведомления вместо push-инфраструктуры): опрос раз в 45 секунд, пока вкладка открыта.
 * Персонал с worklist.view и своей организацией — GET /journal/notifications/bell (входящие, подтверждения, выписки);
 * гражданин — GET /route/me/notifications (что по его маршруту сделали другие: предложили перевод, назначили дату,
 * отказали, сняли с очереди…). Остальным ролям сервер не опрашивается. */
export function useNotificationBell() {
  const auth = useAuthStore()
  const data = ref<NotificationBell | null>(null)
  const citizen = ref<CitizenNotifications | null>(null)
  const error = ref<unknown>(null)
  let timer: ReturnType<typeof setInterval> | null = null

  const eligible = computed(() => auth.isAuthenticated && auth.can('worklist.view') && !!auth.moCode)
  const citizenEligible = computed(() => auth.isAuthenticated && auth.role === 'citizen' && auth.can('route.own'))
  const unreadCount = computed(() => {
    const staff = data.value ? data.value.pendingIncomingCount + data.value.unreadConfirmations.length + data.value.unreadDischarges.length + (data.value.patientSignals?.length ?? 0) : 0
    return staff + (citizen.value?.unread ?? 0)
  })

  async function load() {
    try {
      data.value = eligible.value ? await journal.notificationBell(auth.moCode ?? undefined) : null
      citizen.value = citizenEligible.value ? await routeApi.notifications() : null
      error.value = null
    } catch (e) {
      error.value = e
    }
  }

  /** Отмечает событие прочитанным и сразу обновляет сводку — без ожидания следующего опроса. */
  async function markRead(kind: NotificationKind, decisionId: string) {
    try {
      await journal.markNotificationRead(kind, decisionId)
    } finally {
      await load()
    }
  }

  async function markRouteRead(id: string) {
    try {
      await routeApi.markNotificationRead(id)
    } finally {
      await load()
    }
  }

  onMounted(() => {
    load()
    timer = setInterval(load, POLL_INTERVAL_MS)
  })

  onBeforeUnmount(() => {
    if (timer !== null) clearInterval(timer)
  })

  return { data, citizen, error, unreadCount, load, markRead, markRouteRead }
}
