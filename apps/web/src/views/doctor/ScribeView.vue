<script setup lang="ts">
import QRCode from 'qrcode'
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import InputText from 'primevue/inputtext'
import SelectButton from 'primevue/selectbutton'
import Textarea from 'primevue/textarea'
import { useToast } from 'primevue/usetoast'
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute, useRouter } from 'vue-router'
import { ApiError } from '@/api/client'
import { journal, scribe } from '@/api/endpoints'
import type { ScribeConsent, ScribeConsentStatus, ScribeHealth, ScribeSegment, ScribeVocabulary, WorklistItem } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import AppCard from '@/components/ui/AppCard.vue'
import PageShell from '@/components/ui/PageShell.vue'
import SearchSelect from '@/components/ui/SearchSelect.vue'
import StatusTag from '@/components/ui/StatusTag.vue'
import { useRecorder } from '@/composables/useRecorder'
import { kk } from '@/i18n/kk'
import { ru } from '@/i18n/ru'
import { pickRecordingFormat } from '@/lib/audio'
import { dateShort } from '@/lib/route'
import { useRefdataStore } from '@/stores/refdata'

/** AI-скрайб приёма. Порядок как в жизни: 1) пациент своей больницы (или сразу со страницы пациента), 2) запрос
 * согласия — пациент получает уведомление и отвечает в «Моём пути», 3) запись — только с согласием, одно согласие на
 * один приём в этот день. Дальше: стенограмма (фразы можно исправить вручную или по словарю/ИИ) → весь текст приёма
 * одним полем и памятка → врач правит и утверждает; аудио удаляется,
 * памятка привязывается к пациенту и появляется у него в «Моём пути» (плюс ссылка и QR на приёме). */
const KK_LETTERS = /[әіңғүұқөһӘІҢҒҮҰҚӨҺ]/u
const POLL_MS = 5000

function segmentLang(text: string): 'kk' | 'ru' {
  return KK_LETTERS.test(text) ? 'kk' : 'ru'
}
function stamp(seconds: number): string {
  const s = Math.max(0, Math.round(seconds))
  return `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`
}

const { t } = useI18n()
const toast = useToast()
const route = useRoute()
const router = useRouter()
const refdata = useRefdataStore()

const language = ref<'ru' | 'kk'>('ru')
const languageOptions = computed(() => [
  { value: 'ru' as const, label: t('doctor.scribe.langRu') },
  { value: 'kk' as const, label: t('doctor.scribe.langKk') },
])
const health = ref<ScribeHealth | null>(null)
const error = ref<unknown>(null)

// шаг 1: пациент своей больницы
const patients = ref<WorklistItem[]>([])
const patientsLoading = ref(false)
const patientRef = ref<string | null>(typeof route.query.patientRef === 'string' ? route.query.patientRef : null)
const patientOptions = computed(() => {
  const list = patients.value.map((p) => ({ value: p.patientRef, label: `${p.patientRef} · ${refdata.profileName(p.profileCode)} · ${t('route.daysWaitingShort', { days: p.daysWaiting })}` }))
  if (patientRef.value && !list.some((o) => o.value === patientRef.value)) list.unshift({ value: patientRef.value, label: patientRef.value })
  return list
})

// шаг 2: согласие пациента
const consents = ref<ScribeConsent[]>([])
const consent = computed<ScribeConsent | null>(() => consents.value[0] ?? null)
const consentState = computed<ScribeConsentStatus | 'none'>(() => consent.value?.status ?? 'none')
/** Новый запрос — когда нет действующего: ждёт ответа, согласие дано или начатая запись (её продолжают или отменяют в шаге 3). */
const canAsk = computed(() => !!patientRef.value && !['pending', 'granted', 'recording'].includes(consentState.value))
/** Начатую запись сервис скрайба не нашёл (запись была до обновления, когда сессии жили только в памяти). */
const sessionLost = ref(false)
const resuming = ref(false)
const consentBusy = ref(false)
let poll: ReturnType<typeof setInterval> | null = null

// шаг 3 и дальше: запись
const sessionId = ref<string | null>(null)
const transcript = ref('')
const segments = ref<ScribeSegment[]>([])
// правка стенограммы: врач нажимает на фразу; «Исправить термины» — ИИ по словарю терминов (по кнопке)
const editingIndex = ref<number | null>(null)
const editText = ref('')
const savingSegment = ref(false)
const correcting = ref(false)
const vocabularyOpen = ref(false)
const vocabularyText = ref('')
const vocabularyCount = ref(0)
const vocabularyBuiltIn = ref(0)
const vocabularyGroups = ref<NonNullable<ScribeVocabulary['groups']>>([])
const vocabularySearch = ref('')
const filteredGroups = computed(() => {
  const q = vocabularySearch.value.trim().toLowerCase()
  return vocabularyGroups.value
    .map((g) => ({ ...g, terms: q ? g.terms.filter((term) => term.toLowerCase().includes(q)) : g.terms }))
    .filter((g) => g.terms.length)
})
const vocabularySaving = ref(false)
const typed = ref('')
const showTyped = ref(false)
// запись приёма — весь текст стенограммы одним полем: врач правит там, где нужно, и утверждает.
// Пока врач не трогал поле, оно следует за стенограммой; памятка собирается из назначений.
const recordText = ref('')
const recordDirty = ref(false)
const leaflet = ref('')
const leafletDirty = ref(false)
/** Стенограмма изменилась после ручной правки записи — предлагаем подставить новый текст. */
const transcriptChanged = ref(false)
const leafletUrl = ref<string | null>(null)
const qrDataUrl = ref<string | null>(null)
const busy = ref(false)
const approved = ref(false)
const tab = ref<'record' | 'leaflet'>('record')
const tabOptions = computed(() => [
  { value: 'record' as const, label: t('doctor.scribe.recordTitle') },
  { value: 'leaflet' as const, label: t('doctor.scribe.leafletLabel') },
])

const recordingFormat = typeof MediaRecorder !== 'undefined' && !!navigator.mediaDevices ? pickRecordingFormat((type) => MediaRecorder.isTypeSupported(type)) : null
const recorder = useRecorder(recordingFormat, (blob, name) => upload(blob, name))

const status = computed(() => {
  if (approved.value) return { key: 'approved', tone: 'ok' as const }
  if (recorder.recording.value) return { key: 'recording', tone: 'danger' as const }
  if (busy.value) return { key: 'processing', tone: 'warn' as const }
  if (transcript.value) return { key: 'transcribed', tone: 'accent' as const }
  if (sessionId.value) return { key: 'ready', tone: 'neutral' as const }
  return null
})
const timer = computed(() => stamp(recorder.elapsed.value))
const CONSENT_TONES: Record<string, 'ok' | 'warn' | 'neutral' | 'danger' | 'accent'> = {
  none: 'neutral', pending: 'warn', granted: 'ok', declined: 'danger', withdrawn: 'neutral', cancelled: 'neutral', expired: 'neutral', recording: 'warn', discarded: 'neutral', completed: 'ok',
}

async function loadPatients() {
  patientsLoading.value = true
  try {
    patients.value = (await journal.worklist()).items
  } catch {
    patients.value = [] // без списка врач всё равно может прийти со страницы пациента
  } finally {
    patientsLoading.value = false
  }
}

async function loadConsents() {
  if (!patientRef.value) {
    consents.value = []
    return
  }
  try {
    consents.value = await scribe.consents(patientRef.value)
  } catch (e) {
    consents.value = []
    error.value = e
  }
}

function syncPolling() {
  const waiting = consentState.value === 'pending' && !sessionId.value
  if (waiting && poll === null) poll = setInterval(loadConsents, POLL_MS)
  if (!waiting && poll !== null) {
    clearInterval(poll)
    poll = null
  }
}

async function askConsent() {
  if (!patientRef.value) return
  consentBusy.value = true
  error.value = null
  try {
    await scribe.requestConsent(patientRef.value, crypto.randomUUID())
    toast.add({ severity: 'success', summary: t('doctor.scribe.consentSent'), life: 3000 })
  } catch (e) {
    if (!(e instanceof ApiError && e.status === 409)) error.value = e
  } finally {
    consentBusy.value = false
    await loadConsents()
  }
}

async function cancelConsent() {
  if (!patientRef.value || !consent.value) return
  consentBusy.value = true
  try {
    await scribe.cancelConsent(consent.value.requestId, patientRef.value)
  } catch (e) {
    error.value = e
  } finally {
    consentBusy.value = false
    await loadConsents()
  }
}

function resetSession() {
  sessionLost.value = false
  sessionId.value = null
  recordText.value = ''
  recordDirty.value = false
  leaflet.value = ''
  leafletDirty.value = false
  transcriptChanged.value = false
  tab.value = 'record'
  transcript.value = ''
  segments.value = []
  typed.value = ''
  showTyped.value = false
  leafletUrl.value = null
  qrDataUrl.value = null
  approved.value = false
  editingIndex.value = null
}

async function start() {
  if (!consent.value || consentState.value !== 'granted') return
  error.value = null
  try {
    resetSession()
    sessionId.value = (await scribe.createSession(consent.value.requestId, language.value)).sessionId
    await loadConsents()
  } catch (e) {
    error.value = e
    await loadConsents()
  }
}

/** Продолжить начатую и не утверждённую запись (страницу закрыли или обновили): та же сессия сервиса скрайба,
 * стенограмма и черновик восстанавливаются с того места, где остановились. */
async function resume() {
  if (!consent.value?.sessionId) return
  resuming.value = true
  error.value = null
  try {
    const state = await scribe.session(consent.value.sessionId)
    resetSession()
    language.value = state.language
    segments.value = state.transcript
    transcript.value = state.transcript.map((s) => s.text).join(' ')
    sessionId.value = state.sessionId
  } catch (e) {
    if (e instanceof ApiError && e.status === 404) sessionLost.value = true
    else error.value = e
  } finally {
    resuming.value = false
  }
}

/** Отменить начатую запись: аудио и черновик удаляются, согласие израсходовано — для нового приёма новый запрос. */
async function discard() {
  if (!patientRef.value || !consent.value) return
  consentBusy.value = true
  error.value = null
  try {
    await scribe.discardRecording(consent.value.requestId, patientRef.value)
    resetSession()
    toast.add({ severity: 'info', summary: t('doctor.scribe.discardDone'), life: 3000 })
  } catch (e) {
    error.value = e
  } finally {
    consentBusy.value = false
    await loadConsents()
  }
}

/** Новый приём: тот же или другой пациент, на новый приём нужно новое согласие. */
function newVisit() {
  resetSession()
  loadConsents()
}

async function record() {
  error.value = null
  try {
    await recorder.start()
  } catch (e) {
    error.value = e // доступ к микрофону запрещён или устройства нет
  }
}

async function upload(file: Blob, name: string) {
  if (!sessionId.value) return
  busy.value = true
  error.value = null
  try {
    const uploaded = await scribe.uploadAudio(sessionId.value, file, name)
    segments.value = uploaded.transcript ?? []
    transcript.value = uploaded.text ?? segments.value.map((s) => s.text).join(' ')
  } catch (e) {
    error.value = e
  } finally {
    busy.value = false
  }
}

async function onFile(event: Event) {
  const file = (event.target as HTMLInputElement).files?.[0]
  if (file) await upload(file, file.name)
}

async function useTyped() {
  if (!sessionId.value) return
  try {
    const result = await scribe.setTranscript(sessionId.value, typed.value)
    segments.value = result.transcript ?? []
    transcript.value = typed.value
    showTyped.value = false
  } catch (e) {
    error.value = e
  }
}

function applyTranscript(next: ScribeSegment[]) {
  segments.value = next
  transcript.value = next.map((s) => s.text).join(' ')
}

function editSegment(i: number) {
  if (approved.value || busy.value) return
  editingIndex.value = i
  editText.value = segments.value[i]?.text ?? ''
}

async function saveSegment(i: number, text: string) {
  if (!sessionId.value || !text.trim()) return
  savingSegment.value = true
  error.value = null
  try {
    applyTranscript((await scribe.editSegment(sessionId.value, i, text.trim())).transcript)
    editingIndex.value = null
  } catch (e) {
    error.value = e
  } finally {
    savingSegment.value = false
  }
}

async function correctTerms() {
  if (!sessionId.value) return
  correcting.value = true
  error.value = null
  try {
    const result = await scribe.correctTerms(sessionId.value)
    if (result.changed) applyTranscript(result.transcript)
    const summary = result.changed ? t('doctor.scribe.correctedToast', { n: result.changed }) : t('doctor.scribe.nothingToCorrect')
    // языковая модель недоступна — исправил только словарь, говорим об этом прямо
    toast.add({ severity: result.changed ? 'success' : 'info', life: 5000, summary, detail: result.aiError ? t('doctor.scribe.aiUnavailable') : undefined })
  } catch (e) {
    error.value = e
  } finally {
    correcting.value = false
  }
}

async function loadVocabulary() {
  try {
    const v = await scribe.vocabulary()
    vocabularyCount.value = v.words.length
    vocabularyBuiltIn.value = v.builtIn
    vocabularyGroups.value = v.groups ?? []
    vocabularyText.value = v.words.join('\n')
  } catch {
    // словарь — дополнительная функция, без него скрайб работает
  }
}

async function saveVocabulary() {
  vocabularySaving.value = true
  try {
    const v = await scribe.saveVocabulary(vocabularyText.value.split('\n').map((w) => w.trim()).filter(Boolean))
    vocabularyCount.value = v.words.length
    vocabularyText.value = v.words.join('\n')
    vocabularyOpen.value = false
    toast.add({ severity: 'success', summary: t('doctor.scribe.vocabularySaved', { n: v.words.length }), life: 3000 })
  } catch (e) {
    error.value = e
  } finally {
    vocabularySaving.value = false
  }
}

const LEAFLET_LINE = /(назнач|принима|таблет|\bмг\b|капл|контрол|явк|анализ|направ|повторн|диет|тағайында|қабылда|ішіңіз|жолдама|қайта)/iu

/** Памятка пациенту: назначения и контроль из стенограммы простым списком (на языке приёма); врач правит текст. */
function buildLeaflet(list: ScribeSegment[]): string {
  const m = (language.value === 'kk' ? kk : ru).doctor.scribe
  const lines = list.flatMap((seg) => seg.text.split(/(?<=[.!?…])\s+/u)).map((x) => x.trim()).filter((x) => x && LEAFLET_LINE.test(x))
  return [m.leafletIntro, ...(lines.length ? lines : [m.leafletNoPrescriptions]).map((x) => `- ${x}`), `- ${m.leafletSafety}`].join('\n')
}

function transcriptText(list: ScribeSegment[]): string {
  return list.map((seg) => seg.text).join('\n')
}

watch(segments, (list) => {
  if (approved.value) return
  if (!recordDirty.value) recordText.value = transcriptText(list)
  else transcriptChanged.value = recordText.value !== transcriptText(list)
  if (!leafletDirty.value) leaflet.value = list.length ? buildLeaflet(list) : ''
}, { deep: true })

function replaceRecord() {
  recordText.value = transcriptText(segments.value)
  recordDirty.value = false
  transcriptChanged.value = false
}
function rebuildLeaflet() {
  leaflet.value = buildLeaflet(segments.value)
  leafletDirty.value = false
}


async function approve() {
  if (!sessionId.value || !recordText.value.trim() || !leaflet.value.trim()) return
  try {
    const result = await scribe.approve(sessionId.value, [{ name: t('doctor.scribe.recordTitle'), text: recordText.value.trim() }], leaflet.value.trim())
    leafletUrl.value = `${window.location.origin}/leaflet/${result.leafletToken}`
    approved.value = true
    try {
      qrDataUrl.value = await QRCode.toDataURL(leafletUrl.value, { margin: 1, width: 180 })
    } catch {
      qrDataUrl.value = null // QR — вспомогательная функция, отсутствие картинки не должно ломать утверждение
    }
    toast.add({ severity: 'success', summary: t('doctor.scribe.approvedToast'), life: 3000 })
    await loadConsents()
  } catch (e) {
    error.value = e
  }
}

async function copyLink() {
  if (!leafletUrl.value) return
  try {
    await navigator.clipboard.writeText(leafletUrl.value)
    toast.add({ severity: 'info', summary: t('shell.copied'), life: 2000 })
  } catch {
    toast.add({ severity: 'warn', summary: leafletUrl.value, life: 5000 })
  }
}

watch(patientRef, (value) => {
  if (sessionId.value) return
  error.value = null // ошибка относилась к прошлому пациенту
  router.replace({ query: value ? { ...route.query, patientRef: value } : {} })
  loadConsents()
})
watch([consentState, sessionId], syncPolling)

/** Модель распознавания речи грузится в фоне при старте сервиса (первый запуск — скачивание, несколько минут):
 * пока она не готова, запись с микрофона и файл не распознать — подсказываем вставить текст. */
const transcriberNote = computed(() => {
  const state = health.value?.transcriberState
  if (state === 'loading') {
    const p = health.value?.transcriberProgress
    if (p && p.totalMb && p.downloadedMb > 0) {
      const pct = Math.min(99, Math.round((p.downloadedMb / p.totalMb) * 100))
      return t('doctor.scribe.modelDownloading', { pct, done: p.downloadedMb, total: p.totalMb })
    }
    return t('doctor.scribe.modelLoading')
  }
  if (state === 'error') return t('doctor.scribe.modelError')
  if (health.value?.transcriber === 'fake') return t('doctor.scribe.modelFake')
  return null
})
/** Пока модель не готова, запись и файл не распознать — кнопки неактивны, остаётся «Вставить текст». */
const modelNotReady = computed(() => health.value?.transcriberState === 'loading' || health.value?.transcriberState === 'error')
let healthPoll: ReturnType<typeof setInterval> | null = null
async function loadHealth() {
  try {
    health.value = await scribe.health()
  } catch {
    health.value = null
  }
  if (health.value?.transcriberState !== 'loading' && healthPoll !== null) {
    clearInterval(healthPoll)
    healthPoll = null
  }
}

onMounted(async () => {
  refdata.load()
  loadPatients()
  loadConsents()
  loadVocabulary()
  await loadHealth()
  if (health.value?.transcriberState === 'loading') healthPoll = setInterval(loadHealth, 5_000)
})
onBeforeUnmount(() => {
  recorder.dispose()
  if (poll !== null) clearInterval(poll)
  if (healthPoll !== null) clearInterval(healthPoll)
})
</script>

<template>
  <PageShell :title="t('doctor.scribe.title')">
    <template #subtitle>
      {{ patientRef ? t('doctor.scribe.subtitlePatient', { ref: patientRef }) : t('doctor.scribe.subtitleNoPatient') }} · {{ t('doctor.scribe.audioDeletedOnApprove') }}
    </template>
    <template #actions>
      <SelectButton v-model="language" :options="languageOptions" option-label="label" option-value="value" size="small" :allow-empty="false" :disabled="!!sessionId" />
      <StatusTag v-if="status" :value="t('doctor.scribe.state.' + status.key)" :tone="status.tone" />
    </template>
    <ErrorBox :error="error" />

    <!-- подготовка: пациент → согласие → запись -->
    <section v-if="!sessionId" class="card prep" data-testid="scribe-session">
      <div class="step">
        <span class="step-num">1</span>
        <div class="step-body">
          <span class="step-title">{{ t('doctor.scribe.stepPatient') }}</span>
          <SearchSelect v-model="patientRef" :options="patientOptions" option-label="label" option-value="value" :loading="patientsLoading"
            :placeholder="t('doctor.scribe.choosePatient')" :empty-message="t('doctor.scribe.noPatients')" class="patient-select" data-testid="scribe-patient" />
          <span class="step-hint">{{ t('doctor.scribe.patientHint') }}</span>
        </div>
      </div>

      <div class="step" :class="{ off: !patientRef }">
        <span class="step-num">2</span>
        <div class="step-body">
          <span class="step-title">{{ t('doctor.scribe.stepConsent') }}</span>
          <div class="consent-line" data-testid="scribe-consent" :data-status="consentState">
            <StatusTag :value="t('doctor.scribe.consentStatus.' + consentState)" :tone="CONSENT_TONES[consentState] ?? 'neutral'" />
            <span v-if="consent" class="step-hint">{{ dateShort(consent.answeredAt ?? consent.requestedAt) }}</span>
          </div>
          <span class="step-hint">{{ t('doctor.scribe.consentHint.' + consentState) }}</span>
          <div class="step-actions">
            <Button v-if="canAsk" :label="consentState === 'none' ? t('doctor.scribe.askConsent') : t('doctor.scribe.askAgain')" size="small"
              :severity="consentState === 'none' ? undefined : 'secondary'" :loading="consentBusy" :disabled="!patientRef" data-testid="scribe-ask" @click="askConsent" />
            <Button v-if="consentState === 'pending' || consentState === 'granted'" :label="t('doctor.scribe.cancelRequest')" icon="pi pi-times" size="small" severity="danger" outlined
              :loading="consentBusy" @click="cancelConsent" />
          </div>
        </div>
      </div>

      <div class="step" :class="{ off: consentState !== 'granted' && consentState !== 'recording' }">
        <span class="step-num">3</span>
        <div class="step-body">
          <span class="step-title">{{ t('doctor.scribe.stepRecord') }}</span>
          <ul class="what">
            <li>{{ t('doctor.scribe.what1') }}</li>
            <li>{{ t('doctor.scribe.what2') }}</li>
            <li>{{ t('doctor.scribe.what3') }}</li>
          </ul>
          <span v-if="!health" class="step-hint warn">{{ t('doctor.scribe.serviceDown') }}</span>
          <template v-if="consentState === 'recording'">
            <span class="step-hint" :class="{ warn: sessionLost }">{{ sessionLost ? t('doctor.scribe.sessionLost') : t('doctor.scribe.resumeHint') }}</span>
            <div class="step-actions">
              <Button v-if="!sessionLost" :label="t('doctor.scribe.resume')" icon="pi pi-play" size="small" :loading="resuming" :disabled="!health" data-testid="scribe-resume" @click="resume" />
              <Button :label="t('doctor.scribe.discardRecording')" icon="pi pi-trash" size="small" severity="danger" :outlined="!sessionLost" :loading="consentBusy" data-testid="scribe-discard" @click="discard" />
            </div>
          </template>
          <template v-else>
            <span v-if="consentState !== 'granted'" class="step-hint">{{ t('doctor.scribe.needConsent') }}</span>
            <div class="step-actions">
              <Button :label="t('doctor.scribe.startSession')" icon="pi pi-microphone" size="small" :disabled="consentState !== 'granted' || !health" data-testid="scribe-start" @click="start" />
            </div>
          </template>
        </div>
      </div>
    </section>

    <div v-else class="main-grid">
      <div class="col">
        <AppCard data-testid="scribe-session">
          <div class="rec-row">
            <span class="rec-dot" :class="{ live: recorder.recording.value }" aria-hidden="true" />
            <span class="rec-label">{{ t('doctor.scribe.recordingLabel') }}</span>
            <span class="timer tabular" :class="{ live: recorder.recording.value }">{{ timer }}</span>
            <span class="spacer" />
            <Button v-if="recorder.canRecord && !recorder.recording.value" :label="t('doctor.scribe.recordMic')" icon="pi pi-microphone" size="small" :disabled="approved || busy || modelNotReady" @click="record" />
            <Button v-if="recorder.recording.value" :label="t('doctor.scribe.stop')" icon="pi pi-stop" size="small" @click="recorder.stop()" />
            <label v-if="!approved" class="p-button p-button-secondary p-button-sm upload" :class="{ 'p-disabled': modelNotReady }">{{ t('doctor.scribe.uploadFile') }}<input type="file" accept="audio/*" hidden :disabled="modelNotReady" @change="onFile" /></label>
            <Button :label="t('doctor.scribe.pasteText')" size="small" severity="secondary" :disabled="approved" @click="showTyped = !showTyped" />
          </div>
          <p v-if="transcriberNote" class="model-note" data-testid="scribe-model-note"><i class="pi pi-info-circle" aria-hidden="true" />{{ transcriberNote }}</p>
          <div v-if="recorder.recording.value" class="wave live" aria-hidden="true">
            <span v-for="(level, i) in recorder.levels.value" :key="i" class="bar" :style="{ height: `${Math.max(8, level * 100)}%` }" />
          </div>
          <div v-if="showTyped" class="field typed">
            <label>{{ t('doctor.scribe.orType') }}</label>
            <Textarea v-model="typed" rows="4" auto-resize />
            <div class="actions">
              <Button :label="t('doctor.scribe.useText')" size="small" severity="secondary" :disabled="approved || !typed" @click="useTyped" />
              <Button :label="t('doctor.scribe.pasteSample')" size="small" text data-testid="scribe-sample" @click="typed = t('doctor.scribe.sampleTranscript')" />
            </div>
          </div>
          <div v-if="!approved" class="card-foot">
            <span class="caption">{{ t('doctor.scribe.discardHint') }}</span>
            <Button :label="t('doctor.scribe.discardRecording')" icon="pi pi-trash" size="small" severity="danger" outlined :loading="consentBusy" :disabled="recorder.recording.value" data-testid="scribe-discard-session" @click="discard" />
          </div>
        </AppCard>

        <AppCard :title="t('doctor.scribe.transcript')">
          <div v-if="segments.length" class="rows">
            <div v-for="(segment, i) in segments" :key="i" class="row segment" :class="{ fixed: !!segment.source }">
              <span class="stamp tabular">{{ stamp(segment.t0) }}–{{ stamp(segment.t1) }} · {{ segmentLang(segment.text).toUpperCase() }}
                <span v-if="segment.source" class="fix-tag" :class="segment.source">{{ t('doctor.scribe.fixedBy.' + segment.source) }}</span>
              </span>
              <div v-if="editingIndex === i" class="segment-edit">
                <Textarea v-model="editText" rows="5" auto-resize autofocus class="segment-input" @keydown.enter.exact.prevent="saveSegment(i, editText)" @keydown.esc="editingIndex = null" />
                <div class="actions">
                  <Button :label="t('common.save')" size="small" :loading="savingSegment" :disabled="!editText.trim()" @click="saveSegment(i, editText)" />
                  <Button :label="t('common.cancel')" size="small" severity="secondary" text @click="editingIndex = null" />
                </div>
              </div>
              <button v-else type="button" class="segment-text" :disabled="approved" :title="t('doctor.scribe.editHint')" @click="editSegment(i)">
                {{ segment.text }}<i v-if="!approved" class="pi pi-pencil edit-icon" aria-hidden="true" />
              </button>
              <div v-if="segment.original && editingIndex !== i" class="was">
                <div class="was-head">
                  <span class="was-label">{{ t('doctor.scribe.wasText') }}</span>
                  <Button v-if="!approved" :label="t('doctor.scribe.revert')" icon="pi pi-undo" size="small" severity="secondary" text @click="saveSegment(i, segment.original)" />
                </div>
                <p class="was-text">{{ segment.original }}</p>
              </div>
            </div>
          </div>
          <p v-if="segments.length && !approved" class="caption">{{ t('doctor.scribe.editHint') }}</p>
          <p v-else-if="transcript" style="white-space: pre-wrap">{{ transcript }}</p>
          <p v-else class="muted">{{ busy ? t('doctor.scribe.transcribing') : t('doctor.scribe.noTranscript') }}</p>
          <div class="actions">
            <Button v-if="segments.length && !approved" :label="t('doctor.scribe.correctTerms')" icon="pi pi-sparkles" size="small" severity="secondary" :loading="correcting" :disabled="busy" data-testid="scribe-correct" @click="correctTerms" />
            <span class="spacer" />
            <Button :label="t('doctor.scribe.vocabulary', { n: vocabularyBuiltIn + vocabularyCount })" icon="pi pi-book" size="small" severity="secondary" text data-testid="scribe-vocabulary" @click="vocabularyOpen = true" />
          </div>
        </AppCard>
      </div>

      <AppCard :title="tab === 'record' ? t('doctor.scribe.recordTitle') : t('doctor.scribe.leafletLabel')">
        <template #header>
          <SelectButton v-model="tab" :options="tabOptions" option-label="label" option-value="value" size="small" :allow-empty="false" />
        </template>
        <p v-if="!transcript && !recordText" class="muted">{{ t('doctor.scribe.noRecord') }}</p>
        <template v-else-if="tab === 'record'">
          <p class="caption">{{ t('doctor.scribe.recordHint') }}</p>
          <Textarea v-model="recordText" rows="4" auto-resize class="record-text" :disabled="approved" data-testid="scribe-record-text" @input="recordDirty = true" />
          <div v-if="transcriptChanged && !approved" class="stale-row">
            <span class="caption warn-text">{{ t('doctor.scribe.transcriptChanged') }}</span>
            <Button :label="t('doctor.scribe.replaceRecord')" size="small" severity="secondary" text @click="replaceRecord" />
          </div>
        </template>
        <div v-else class="field">
          <p class="caption">{{ t('doctor.scribe.leafletHint') }}</p>
          <Textarea v-model="leaflet" rows="8" auto-resize :disabled="approved" data-testid="scribe-leaflet-text" @input="leafletDirty = true" />
          <Button v-if="leafletDirty && !approved" :label="t('doctor.scribe.rebuildLeaflet')" size="small" severity="secondary" text @click="rebuildLeaflet" />
        </div>
        <div v-if="(transcript || recordText) && !approved" class="approve-row">
          <Button :label="t('doctor.scribe.approveAll')" icon="pi pi-check" size="small" :disabled="!recordText.trim() || !leaflet.trim() || busy || correcting" data-testid="scribe-approve" @click="approve" />
          <span class="caption">{{ t('doctor.scribe.approveHint') }}</span>
        </div>
        <div v-if="approved" class="result" data-testid="scribe-result">
          <p class="result-title"><i class="pi pi-check-circle" aria-hidden="true" /> {{ t('doctor.scribe.leafletSent') }}</p>
          <StatusTag :value="t('doctor.scribe.audioDeleted')" tone="ok" icon="pi pi-trash" />
          <div class="link-row">
            <a v-if="leafletUrl" :href="leafletUrl" target="_blank" class="mono">{{ leafletUrl }}</a>
            <Button :label="t('shell.copyLink')" icon="pi pi-copy" size="small" severity="secondary" text @click="copyLink" />
          </div>
          <div v-if="qrDataUrl" class="qr-block">
            <img :src="qrDataUrl" :alt="t('doctor.scribe.qrAlt')" width="140" height="140" />
            <p class="caption">{{ t('doctor.scribe.qrHint') }}</p>
          </div>
          <div class="actions">
            <Button :label="t('doctor.scribe.newVisit')" icon="pi pi-plus" size="small" severity="secondary" data-testid="scribe-new" @click="newVisit" />
            <RouterLink v-if="patientRef" class="link-arrow small" :to="{ name: 'patient-route', params: { patientRef } }">{{ t('doctor.scribe.openPatient') }}</RouterLink>
          </div>
        </div>
      </AppCard>
    </div>
    <Dialog v-model:visible="vocabularyOpen" modal :header="t('doctor.scribe.vocabularyTitle')" :style="{ width: 'min(640px, 94vw)' }">
      <p class="muted small vocab-hint">{{ t('doctor.scribe.vocabularyHint') }}</p>
      <div class="field vocab-field">
        <label>{{ t('doctor.scribe.vocabularyOwn', { n: vocabularyCount }) }}</label>
        <Textarea v-model="vocabularyText" rows="3" auto-resize class="vocab-text" :placeholder="t('doctor.scribe.vocabularyPlaceholder')" data-testid="scribe-vocabulary-text" />
      </div>
      <div class="field vocab-field">
        <label>{{ t('doctor.scribe.vocabularyBuiltIn', { n: vocabularyBuiltIn }) }}</label>
        <InputText v-model="vocabularySearch" size="small" :placeholder="t('doctor.scribe.vocabularySearch')" class="vocab-search" />
        <div class="vocab-list">
          <div v-for="group in filteredGroups" :key="group.language + group.name" class="vocab-group">
            <span class="vocab-group-name">{{ group.name }} · {{ group.terms.length }}</span>
            <div class="chips"><span v-for="term in group.terms" :key="term" class="chip">{{ term }}</span></div>
          </div>
          <p v-if="!filteredGroups.length" class="muted small">{{ t('doctor.scribe.vocabularyNothing') }}</p>
        </div>
      </div>
      <template #footer>
        <Button :label="t('common.cancel')" size="small" severity="secondary" text @click="vocabularyOpen = false" />
        <Button :label="t('common.save')" size="small" :loading="vocabularySaving" @click="saveVocabulary" />
      </template>
    </Dialog>
  </PageShell>
</template>

<style scoped>
.prep { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); padding: 0; overflow: hidden; }
.step { display: flex; gap: 12px; padding: 18px 20px; border-left: 1px solid var(--border-soft); min-width: 0; }
.step:first-child { border-left: 0; }
.step.off { opacity: 0.55; }
.step-num { width: 24px; height: 24px; flex: none; border-radius: 50%; display: grid; place-items: center; font-size: var(--fs-sm); font-weight: var(--fw-bold);
  background: var(--surface-muted); color: var(--text-secondary); }
.step-body { display: flex; flex-direction: column; gap: 8px; min-width: 0; flex: 1; }
.step-title { font-size: var(--fs-base); font-weight: var(--fw-bold); line-height: 24px; }
.step-hint { font-size: var(--fs-sm); color: var(--text-muted); line-height: 1.45; }
.step-hint.warn { color: var(--danger-text); }
.step-actions { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; margin-top: 2px; }
.patient-select { width: 100%; }
.consent-line { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
.what { margin: 0; padding-left: 18px; font-size: var(--fs-sm); color: var(--text-secondary); line-height: 1.5; display: flex; flex-direction: column; gap: 2px; }
.main-grid { display: grid; grid-template-columns: minmax(0, 1.1fr) minmax(0, 1fr); gap: var(--dm-space-4); align-items: start; }
.col { display: flex; flex-direction: column; gap: var(--dm-space-4); min-width: 0; }
.rec-row { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
.rec-dot { width: 10px; height: 10px; border-radius: 50%; background: var(--dm-dot-idle); flex: none; }
.rec-dot.live { background: var(--danger-strong); }
.rec-label { font-size: var(--fs-base); font-weight: var(--fw-bold); }
.timer { font-size: var(--fs-md); font-weight: var(--fw-bold); line-height: 1; }
.timer.live { color: var(--danger-strong); }
.spacer { flex: 1; }
.upload { cursor: pointer; }
.upload.p-disabled { pointer-events: none; opacity: 0.6; }
.wave { display: flex; align-items: center; gap: 3px; height: 32px; padding: 0 4px; margin-top: 12px; border-radius: var(--dm-radius-md); background: var(--dm-surface-2); }
.wave .bar { flex: 1; background: var(--dm-dot-idle); border-radius: 2px; transition: height 0.08s linear; }
.wave.live .bar { background: var(--dm-primary); }
.typed { margin-top: 12px; }
.model-note { display: flex; align-items: flex-start; gap: 8px; margin: 10px 0 0; font-size: var(--fs-sm); color: var(--text-secondary); line-height: 1.45; }
.model-note .pi { margin-top: 2px; color: var(--text-muted); }
.segment { display: flex; flex-direction: column; gap: 2px; align-items: flex-start; justify-content: flex-start; margin: 0; min-height: 40px; }
.stamp { flex: none; font-size: var(--fs-xs); color: var(--text-faint); letter-spacing: 0.02em; }
.segment-text { font: inherit; font-size: var(--fs-base); text-align: left; color: inherit; background: none; border: 0; padding: 2px 4px; margin: 0 -4px;
  border-radius: 6px; cursor: text; display: inline-flex; align-items: baseline; gap: 6px; }
.segment-text:not(:disabled):hover { background: var(--surface-muted); }
.segment-text:disabled { cursor: default; }
.edit-icon { font-size: 11px; color: var(--text-faint); opacity: 0; transition: opacity 0.15s; }
.segment-text:hover .edit-icon { opacity: 1; }
.segment-edit { width: 100%; display: flex; flex-direction: column; gap: 12px; margin: 6px 0 14px; }
.segment-input { width: 100%; min-height: 140px; padding: 12px 14px; line-height: 1.6; font-size: var(--fs-base); }
.segment-edit .actions { margin-top: 0; display: flex; gap: 8px; }
.fix-tag { margin-left: 6px; padding: 1px 6px; border-radius: 999px; font-size: 10px; font-weight: var(--fw-bold); letter-spacing: 0.02em; }
.fix-tag.ai { background: var(--accent-soft); color: var(--accent-strong); }
.fix-tag.doctor { background: var(--surface-muted); color: var(--text-secondary); }
.was { width: 100%; margin-top: 10px; padding: 10px 14px 12px; border-radius: 10px; background: var(--surface-muted); border: 1px solid var(--border-soft); }
.was-head { display: flex; align-items: center; justify-content: space-between; gap: 8px; }
.was-label { font-size: var(--fs-xs); font-weight: var(--fw-bold); color: var(--text-secondary); text-transform: uppercase; letter-spacing: 0.04em; }
.was-text { margin: 4px 0 0; font-size: var(--fs-sm); line-height: 1.55; color: var(--text-secondary); }
.link-btn { font: inherit; background: none; border: 0; padding: 0 0 0 6px; color: var(--accent); cursor: pointer; }
.link-btn:hover { text-decoration: underline; }
.warn-text { color: var(--warning-text); }
.vocab-hint { margin: 0 0 4px; line-height: 1.5; }
.vocab-field { display: flex; flex-direction: column; gap: 8px; margin: 18px 0 0; }
.vocab-text { width: 100%; font-family: inherit; }
.vocab-search { width: 100%; }
.vocab-list { max-height: 280px; overflow-y: auto; display: flex; flex-direction: column; gap: 12px; padding-right: 4px; }
.vocab-group { display: flex; flex-direction: column; gap: 6px; }
.vocab-group-name { font-size: var(--fs-xs); font-weight: var(--fw-bold); color: var(--text-secondary); text-transform: uppercase; letter-spacing: 0.04em; }
.chips { display: flex; flex-wrap: wrap; gap: 4px; }
.chip { padding: 2px 8px; border-radius: 999px; background: var(--surface-muted); font-size: var(--fs-xs); color: var(--text-secondary); }
.card-foot { display: flex; align-items: center; justify-content: space-between; gap: 12px; flex-wrap: wrap; margin-top: 14px; padding-top: 12px; border-top: 1px solid var(--border-soft); }
.record-text { width: 100%; margin-top: 8px; min-height: 120px; padding: 12px 14px; line-height: 1.6; }
.stale-row { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; margin-top: 6px; }
.section { margin-bottom: 8px; }
.approve-row { display: flex; align-items: center; gap: 12px; flex-wrap: wrap; margin-top: 12px; }
.result { margin-top: 12px; padding-top: 12px; border-top: 1px solid var(--border-soft); display: flex; flex-direction: column; gap: 8px; align-items: flex-start; }
.result-title { margin: 0; font-size: var(--fs-base); font-weight: var(--fw-semibold); display: flex; align-items: center; gap: 8px; }
.result-title i { color: var(--success-text); }
.link-row { display: flex; gap: 8px; align-items: center; flex-wrap: wrap; word-break: break-all; font-size: var(--fs-sm); }
.qr-block { display: flex; align-items: center; gap: 12px; }
.qr-block .caption { margin: 0; max-width: 260px; }
@media (max-width: 1000px) {
  .prep { grid-template-columns: 1fr; }
  .step { border-left: 0; border-top: 1px solid var(--border-soft); }
  .step:first-child { border-top: 0; }
  .main-grid { grid-template-columns: 1fr; }
}
</style>
