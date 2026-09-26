import { computed, ref } from 'vue'
import { ApiError } from '@/api/client'
import { route as routeApi } from '@/api/endpoints'
import type { PatientRoute, SignalKind } from '@/api/types'
import { openRequest, openSignal, routeEntries } from '@/lib/route'

/** Данные маршрута для двух экранов (Мой путь гражданина и маршрут пациента врача): загрузка, состояния 403/404,
 * действия с одним ключом идемпотентности на загруженный маршрут (повторный клик не создаёт вторую запись). */
export function useRouteData(patientRef: () => string | undefined) {
  const data = ref<PatientRoute | null>(null)
  const error = ref<unknown>(null)
  const notFound = ref(false)
  const forbidden = ref(false)
  const busy = ref(false)
  /** код организации, kind сигнала или 'keep' — что сейчас отправляется; кнопки на это время заблокированы */
  const acting = ref<string | null>(null)
  let key = ''

  const openSig = computed(() => (data.value ? openSignal(data.value) : null))
  const pendingRequest = computed(() => (data.value ? openRequest(data.value) : null))
  const entries = computed(() => (data.value ? routeEntries(data.value) : []))
  const expired = computed(() => data.value?.checklist.filter((c) => c.status === 'expired').length ?? 0)
  const valid = computed(() => data.value?.checklist.filter((c) => c.status !== 'expired').length ?? 0)
  const target = computed(() => data.value?.benchmarks.find((b) => b.code === 'moh_target_wait_days') ?? null)
  const requestedAlternative = computed(() => data.value?.alternatives.find((a) => a.mo.moCode === openSig.value?.toMoCode) ?? null)
  /** Последний ответ врача (перенаправление или «оставить») — гражданину показывается в «Что сейчас». */
  const latestDecision = computed(() => data.value?.decisions.slice().sort((a, b) => (a.recordedAt < b.recordedAt ? 1 : -1))[0] ?? null)

  async function load() {
    busy.value = true
    error.value = null
    notFound.value = false
    forbidden.value = false
    try {
      const ref = patientRef()
      data.value = ref ? await routeApi.patient(ref) : await routeApi.me()
      key = crypto.randomUUID()
    } catch (e) {
      if (e instanceof ApiError && e.status === 404) notFound.value = true
      else if (e instanceof ApiError && e.status === 403) forbidden.value = true
      else error.value = e
    } finally {
      busy.value = false
    }
  }

  async function act(marker: string, request: () => Promise<unknown>): Promise<boolean> {
    acting.value = marker
    try {
      await request()
      await load()
      return true
    } catch (e) {
      error.value = e
      return false
    } finally {
      acting.value = null
    }
  }

  /** Врач: перенаправить в другую организацию с причиной (Kind = redirect). */
  function redirect(toMoCode: string, reason: string) {
    const ref = patientRef()
    if (!ref) return Promise.resolve(false)
    return act(toMoCode, () => routeApi.redirect(ref, { toMoCode, reason }, key))
  }

  /** Врач: оставить в текущей организации с причиной — ответ на сигнал гражданина (Kind = keep). */
  function keep(reason: string) {
    const ref = patientRef()
    if (!ref) return Promise.resolve(false)
    return act('keep', () => routeApi.keep(ref, { reason }, key))
  }

  /** Гражданин: валидация листа ожидания или просьба рассмотреть организацию. */
  function signal(kind: SignalKind, toMoCode?: string, comment?: string) {
    return act(toMoCode ?? kind, () => routeApi.signal({ kind, toMoCode, comment: comment?.trim() || undefined }, crypto.randomUUID()))
  }

  return { data, error, notFound, forbidden, busy, acting, openSig, pendingRequest, entries, expired, valid, target, requestedAlternative, latestDecision, load, redirect, keep, signal }
}
