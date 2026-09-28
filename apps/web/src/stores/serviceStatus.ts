import { defineStore } from 'pinia'
import { computed, ref } from 'vue'
import { pub } from '@/api/endpoints'
import type { ServiceReason, ServiceStatus } from '@/api/types'
import { parseServiceStatus, readDismissedEmailReason, SERVICE_STATUS_REFRESH_MS, writeDismissedEmailReason } from '@/lib/serviceStatus'

/** Канал уведомлений из настроек (W-Account-Notifications). */
export type NotifyChannel = 'inApp' | 'email' | 'sms' | 'push'

/** Статус внешних каналов (почта, push, SMS, eGov mobile): запрос при старте приложения и раз в 5 минут. Запрос не
 * удался — почта считается неизвестной (баннера нет), а push, SMS и eGov — недоступными. */
export const useServiceStatusStore = defineStore('serviceStatus', () => {
  /** Ответ последнего запроса; null — статус неизвестен (ещё не пришёл или запрос не удался). */
  const status = ref<ServiceStatus | null>(null)
  const dismissedEmailReason = ref<string | null>(readDismissedEmailReason())
  let timer: ReturnType<typeof setInterval> | undefined
  let pending: Promise<void> | null = null

  /** Почта недоступна — только по ответу API; без ответа почта неизвестна. */
  const emailUnavailable = computed(() => status.value?.email.available === false)
  const emailReason = computed<ServiceReason | null>(() => (emailUnavailable.value ? status.value!.email.reason ?? 'unavailable' : null))
  const pushAvailable = computed(() => status.value?.push.available === true)
  const smsAvailable = computed(() => status.value?.sms.available === true)
  const egovAvailable = computed(() => status.value?.egov.available === true)
  /** Баннер каркаса: почта недоступна и в этой сессии его не скрывали при той же причине. */
  const emailBannerVisible = computed(() => emailUnavailable.value && dismissedEmailReason.value !== emailReason.value)

  /** Почему канал уведомлений сейчас не доставляет; null — доставляет (в системе — всегда; почта — и когда статус неизвестен). */
  function channelOff(channel: NotifyChannel): ServiceReason | null {
    if (channel === 'inApp') return null
    if (channel === 'email') return emailReason.value
    const service = status.value?.[channel]
    return service?.available ? null : service?.reason ?? 'not_ready'
  }

  async function load() {
    try {
      status.value = parseServiceStatus(await pub.serviceStatus())
    } catch (error) {
      status.value = null
      console.warn('GET /api/v1/public/service-status недоступен: почта — неизвестна, push, SMS и eGov — недоступны', error)
    }
  }

  /** Повторный вызов во время запроса ждёт тот же запрос. */
  function refresh(): Promise<void> {
    pending ??= load().finally(() => {
      pending = null
    })
    return pending
  }

  /** Первый запрос и опрос раз в 5 минут; повторный вызов ничего не делает. */
  function start() {
    if (timer !== undefined) return
    void refresh()
    timer = setInterval(() => void refresh(), SERVICE_STATUS_REFRESH_MS)
  }

  function stop() {
    if (timer !== undefined) clearInterval(timer)
    timer = undefined
  }

  function dismissEmailBanner() {
    if (!emailReason.value) return
    dismissedEmailReason.value = emailReason.value
    writeDismissedEmailReason(emailReason.value)
  }

  return {
    status, dismissedEmailReason, emailUnavailable, emailReason, pushAvailable, smsAvailable, egovAvailable, emailBannerVisible,
    channelOff, refresh, start, stop, dismissEmailBanner,
  }
})
