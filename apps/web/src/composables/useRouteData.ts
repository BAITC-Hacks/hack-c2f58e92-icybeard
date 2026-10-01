import { computed, ref } from 'vue'
import { ApiError } from '@/api/client'
import { route as routeApi } from '@/api/endpoints'
import type { PatientRoute, RouteAction, SignalKind } from '@/api/types'
import { openRequest, openSignal } from '@/lib/route'

/** Данные маршрута для двух экранов (Мой путь гражданина и маршрут пациента врача): загрузка, состояния 403/404,
 * действия с одним ключом идемпотентности на загруженный маршрут (повторный клик не создаёт вторую запись).
 * Что можно сделать сейчас — только из progress.allowed (сервер считает это по журналу), экраны правил не вычисляют. */
export function useRouteData(patientRef: () => string | undefined) {
  const data = ref<PatientRoute | null>(null)
  const error = ref<unknown>(null)
  const notFound = ref(false)
  const forbidden = ref(false)
  const busy = ref(false)
  /** код организации, kind сигнала или действие — что сейчас отправляется; кнопки на это время заблокированы */
  const acting = ref<string | null>(null)
  let key = ''

  const progress = computed(() => data.value?.progress ?? null)
  const can = (action: RouteAction) => progress.value?.allowed.includes(action) ?? false
  const openSig = computed(() => (data.value ? openSignal(data.value) : null))
  const pendingRequest = computed(() => (data.value ? openRequest(data.value) : null))
  const journal = computed(() => data.value?.journal ?? [])
  const expired = computed(() => data.value?.checklist.filter((c) => c.status === 'expired').length ?? 0)
  const valid = computed(() => data.value?.checklist.filter((c) => c.status !== 'expired').length ?? 0)
  const target = computed(() => data.value?.benchmarks.find((b) => b.code === 'moh_target_wait_days') ?? null)
  const requestedAlternative = computed(() => data.value?.alternatives.find((a) => a.mo.moCode === openSig.value?.toMoCode) ?? null)
  /** Больницы, которые отказали в приёме или от которых отказался пациент, — их не предлагаем. */
  const alternatives = computed(() => {
    const blocked = new Set(progress.value?.blockedMoCodes ?? [])
    return data.value?.alternatives.filter((a) => !blocked.has(a.mo.moCode)) ?? []
  })
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
      // 409 — маршрут уже изменился (кто-то успел раньше): показываем актуальное состояние
      if (e instanceof ApiError && e.status === 409) await load().then(() => (error.value = e))
      return false
    } finally {
      acting.value = null
    }
  }

  function withRef(marker: string, request: (ref: string) => Promise<unknown>) {
    const ref = patientRef()
    if (!ref) return Promise.resolve(false)
    return act(marker, () => request(ref))
  }

  /** Врач: перенаправить в другую организацию с причиной (Kind = redirect); severe — клинический флаг тяжести (задача 3). */
  const redirect = (toMoCode: string, reason: string, severe = false) =>
    withRef(toMoCode, (ref) => routeApi.redirect(ref, { toMoCode, reason, severe: severe || undefined }, key))

  /** Врач: оставить в текущей организации с причиной (Kind = keep). */
  const keep = (reason: string) => withRef('keep', (ref) => routeApi.keep(ref, { reason }, key))

  /** Врач больницы пациента: отменить ещё не подтверждённый перевод. */
  const cancelTransfer = (reason: string) => withRef('cancel_transfer', (ref) => routeApi.cancelTransfer(ref, { reason }, key))

  /** Ответственная больница: подтвердить снятие с листа ожидания по просьбе пациента. */
  const close = (reason: string) => withRef('close', (ref) => routeApi.close(ref, { reason }, key))

  /** Гражданин: валидация листа ожидания, «хочу остаться», «больше не нужно» или просьба рассмотреть организацию. */
  function signal(kind: SignalKind, toMoCode?: string, comment?: string) {
    return act(toMoCode ?? kind, () => routeApi.signal({ kind, toMoCode, comment: comment?.trim() || undefined }, crypto.randomUUID()))
  }

  /** Гражданин: согласие или отказ на перевод; до подтверждения больницей отказ = отзыв согласия. */
  function consent(decisionId: string, accepted: boolean, reason?: string) {
    return act(accepted ? 'accept_transfer' : 'decline_transfer', () =>
      routeApi.consent({ decisionId, accepted, reason: reason?.trim() || undefined }, crypto.randomUUID()))
  }

  return {
    data, error, notFound, forbidden, busy, acting, progress, can, openSig, pendingRequest, journal, expired, valid, target, requestedAlternative,
    alternatives, latestDecision, load, redirect, keep, cancelTransfer, close, signal, consent,
  }
}
