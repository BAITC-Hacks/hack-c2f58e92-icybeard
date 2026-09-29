import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { journal } from '@/api/endpoints'
import type { NotificationBell, NotificationKind } from '@/api/types'
import { useAuthStore } from '@/stores/auth'

const POLL_INTERVAL_MS = 45_000

/** Колокольчик (задача 13 плана прозрачности, упрощена до внутрисистемных уведомлений вместо push-инфраструктуры):
 * опрашивает GET /journal/notifications/bell раз в 45 секунд, пока вкладка открыта — не WebSocket и не Kafka
 * (осознанное решение: прод-стенд работает в Messaging Mode "local", без Kafka, и ни один другой экран системы
 * не push-based; задержка в десятки секунд для уведомления о направлении пациента не критична). Опрос идёт только
 * для ролей с worklist.view и своей организацией — без этого сервер и так вернёт пустой ответ, но незачем дёргать
 * эндпоинт зря для гражданина/регулятора/оператора данных.</summary> */
export function useNotificationBell() {
  const auth = useAuthStore()
  const data = ref<NotificationBell | null>(null)
  const error = ref<unknown>(null)
  let timer: ReturnType<typeof setInterval> | null = null

  const eligible = computed(() => auth.isAuthenticated && auth.can('worklist.view') && !!auth.moCode)
  const unreadCount = computed(() => {
    if (!data.value) return 0
    return data.value.pendingIncomingCount + data.value.unreadConfirmations.length + data.value.unreadDischarges.length
  })

  async function load() {
    if (!eligible.value) {
      data.value = null
      return
    }

    try {
      data.value = await journal.notificationBell(auth.moCode ?? undefined)
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

  onMounted(() => {
    load()
    timer = setInterval(load, POLL_INTERVAL_MS)
  })

  onBeforeUnmount(() => {
    if (timer !== null) clearInterval(timer)
  })

  return { data, error, unreadCount, load, markRead }
}
