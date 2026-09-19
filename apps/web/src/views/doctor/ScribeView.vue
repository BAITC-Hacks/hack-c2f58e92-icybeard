<script setup lang="ts">
import QRCode from 'qrcode'
import Button from 'primevue/button'
import Checkbox from 'primevue/checkbox'
import Select from 'primevue/select'
import Textarea from 'primevue/textarea'
import { useToast } from 'primevue/usetoast'
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRouter } from 'vue-router'
import { scribe } from '@/api/endpoints'
import type { ScribeDraft, ScribeHealth, ScribeSegment } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import OriginTag from '@/components/OriginTag.vue'
import { pickRecordingFormat } from '@/lib/audio'

// Простая эвристика для подсветки вероятных упоминаний препаратов в разделе «Назначения»:
// слово с заглавной буквы рядом с дозировкой (мг/мл/мкг/ЕД) или после характерных глаголов назначения.
// Это подсказка врачу для беглого просмотра, а не структурированное извлечение данных — mnnId так не получить
// (drug_mnn_id — непрозрачный код, надёжно сопоставить с текстом стенограммы нельзя).
const DRUG_HINT_RE =
  /([A-ZА-ЯЁ][a-zа-яё]{2,}(?:\s+[a-zа-яё]{3,})?\s*\d+(?:[.,]\d+)?\s*(?:мг|мл|мкг|ед)\b)|((?:принимать|назначить|назначаю|таблетки|капли)\s+[A-ZА-ЯЁa-zа-яё][a-zа-яёA-ZА-ЯЁ-]{2,})/giu

function escapeHtml(text: string): string {
  return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
}

function highlightDrugMentions(text: string): string {
  return escapeHtml(text).replace(DRUG_HINT_RE, (m) => `<mark class="drug-hint">${m}</mark>`)
}

const { t } = useI18n()
const toast = useToast()
const router = useRouter()
const consent = ref(false)
const language = ref<'ru' | 'kk'>('ru')
const languageOptions = computed(() => [
  { value: 'ru' as const, label: t('doctor.scribe.langRu') },
  { value: 'kk' as const, label: t('doctor.scribe.langKk') },
])
const sessionId = ref<string | null>(null)
const health = ref<ScribeHealth | null>(null)
const transcript = ref('')
const segments = ref<ScribeSegment[]>([])
const typed = ref(t('doctor.scribe.sampleTranscript'))
const draft = ref<ScribeDraft | null>(null)
const leaflet = ref('')
const leafletUrl = ref<string | null>(null)
const qrDataUrl = ref<string | null>(null)
// подсветка фрагментов стенограммы при наведении на раздел черновика (ссылки заданы span'ами t0/t1)
const hoveredSpans = ref<{ t0: number; t1: number }[] | null>(null)
const error = ref<unknown>(null)
const busy = ref(false)
const recording = ref(false)
let recorder: MediaRecorder | null = null
let chunks: Blob[] = []
const recordingFormat =
  typeof MediaRecorder !== 'undefined' && !!navigator.mediaDevices ? pickRecordingFormat((type) => MediaRecorder.isTypeSupported(type)) : null
const canRecord = recordingFormat !== null
// после утверждения аудио удалено, черновик и памятка зафиксированы: для нового приёма нужна новая сессия
const approved = ref(false)

async function start() {
  error.value = null
  try {
    sessionId.value = (await scribe.createSession(consent.value, language.value)).sessionId
    draft.value = null
    transcript.value = ''
    segments.value = []
    leafletUrl.value = null
    qrDataUrl.value = null
    hoveredSpans.value = null
    approved.value = false
  } catch (e) {
    error.value = e
  }
}

function isSegmentHighlighted(segment: ScribeSegment): boolean {
  if (!hoveredSpans.value) return false
  return hoveredSpans.value.some((span) => span.t0 < segment.t1 && span.t1 > segment.t0)
}

function hoverSection(spans: { t0: number; t1: number }[] | undefined) {
  hoveredSpans.value = spans && spans.length ? spans : null
}

function goCheckPrescription() {
  // mnnId нельзя надёжно вывести из свободного текста стенограммы (drug_mnn_id — непрозрачный код,
  // а не имя препарата), поэтому просто открываем проверку рецепта — врач выбирает МНН вручную
  router.push({ name: 'medicines' })
}

async function record() {
  if (!recordingFormat) return
  const format = recordingFormat
  error.value = null
  let stream: MediaStream
  try {
    stream = await navigator.mediaDevices.getUserMedia({ audio: true })
  } catch (e) {
    error.value = e // доступ к микрофону запрещён или устройства нет
    return
  }
  recorder = new MediaRecorder(stream, { mimeType: format.mimeType })
  chunks = []
  recorder.ondataavailable = (e) => chunks.push(e.data)
  recorder.onstop = async () => {
    stream.getTracks().forEach((t) => t.stop())
    await upload(new Blob(chunks, { type: format.mimeType }), `consult.${format.extension}`)
  }
  recorder.start()
  recording.value = true
}

function stop() {
  recorder?.stop()
  recording.value = false
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
  } catch (e) {
    error.value = e
  }
}

async function makeDraft() {
  if (!sessionId.value) return
  busy.value = true
  error.value = null
  try {
    const made = await scribe.draft(sessionId.value)
    draft.value = made
    leaflet.value = made.patientLeaflet.text
  } catch (e) {
    error.value = e
  } finally {
    busy.value = false
  }
}

async function approve() {
  if (!sessionId.value || !draft.value) return
  try {
    const result = await scribe.approve(sessionId.value, draft.value.sections.map((s) => ({ name: s.name, text: s.text })), leaflet.value)
    // ссылка на памятку строится из origin текущего фронтенда (тот же, что открыл врач), без хардкода домена
    leafletUrl.value = `${window.location.origin}/leaflet/${result.leafletToken}`
    approved.value = true
    try {
      qrDataUrl.value = await QRCode.toDataURL(leafletUrl.value, { margin: 1, width: 220 })
    } catch {
      qrDataUrl.value = null // QR — вспомогательная функция, отсутствие картинки не должно ломать утверждение
    }
    toast.add({ severity: 'success', summary: t('doctor.scribe.approvedToast'), life: 3000 })
  } catch (e) {
    error.value = e
  }
}

onMounted(async () => {
  try {
    health.value = await scribe.health()
  } catch {
    health.value = null
  }
})
onBeforeUnmount(() => recorder?.state === 'recording' && recorder.stop())
</script>

<template>
  <main class="page">
    <h1>{{ t('doctor.scribe.title') }}</h1>
    <p class="lead">{{ t('doctor.scribe.lead') }}</p>
    <p v-if="health" class="muted">{{ t('doctor.scribe.transcriber') }}: {{ health.transcriber }} · {{ t('doctor.scribe.drafter') }}: {{ health.drafter }}</p>
    <p v-else class="muted">{{ t('doctor.scribe.serviceDown') }}</p>
    <div class="card">
      <div class="actions" style="align-items: center">
        <Checkbox v-model="consent" binary input-id="consent" /><label for="consent">{{ t('doctor.scribe.consent') }}</label>
        <Select v-model="language" :options="languageOptions" option-label="label" option-value="value" size="small" />
        <Button :label="t('doctor.scribe.startSession')" icon="pi pi-play" :disabled="!consent" @click="start" />
        <span v-if="sessionId" class="muted">{{ t('doctor.scribe.session') }} {{ sessionId }}</span>
      </div>
      <ErrorBox :error="error" />
    </div>
    <div v-if="sessionId" class="grid cols-2" style="margin-top: 16px">
      <div class="card">
        <h2>{{ t('doctor.scribe.transcript') }}</h2>
        <div class="actions">
          <Button v-if="canRecord && !recording" :label="t('doctor.scribe.recordMic')" icon="pi pi-microphone" severity="secondary" :disabled="approved" @click="record" />
          <Button v-if="recording" :label="t('doctor.scribe.stop')" icon="pi pi-stop" severity="danger" @click="stop" />
          <label v-if="!approved" class="p-button p-button-secondary p-button-sm" style="cursor: pointer">{{ t('doctor.scribe.uploadFile') }}<input type="file" accept="audio/*" hidden @change="onFile" /></label>
        </div>
        <div class="field" style="margin-top: 12px"><label>{{ t('doctor.scribe.orType') }}</label><Textarea v-model="typed" rows="4" auto-resize /></div>
        <div class="actions"><Button :label="t('doctor.scribe.useText')" size="small" severity="secondary" :disabled="approved" @click="useTyped" /></div>
        <div v-if="segments.length" class="transcript-segments" style="margin-top: 12px">
          <p
            v-for="(segment, i) in segments"
            :key="i"
            class="segment"
            :class="{ 'segment-highlight': isSegmentHighlighted(segment) }"
          >
            <span class="muted" style="font-variant-numeric: tabular-nums">[{{ segment.t0.toFixed(0) }}–{{ segment.t1.toFixed(0) }}]</span>
            {{ segment.text }}
          </p>
        </div>
        <p v-else-if="transcript" style="white-space: pre-wrap; margin-top: 12px">{{ transcript }}</p>
        <div class="actions"><Button :label="t('doctor.scribe.makeDraft')" icon="pi pi-file-edit" :disabled="!transcript || approved" :loading="busy" @click="makeDraft" /></div>
      </div>
      <div v-if="draft" class="card">
        <h2>{{ t('doctor.scribe.draftTitle') }} ({{ draft.model }}) <OriginTag kind="ai" :note="t('doctor.scribe.draftNote')" /></h2>
        <div
          v-for="section in draft.sections"
          :key="section.name"
          class="field"
          style="margin-bottom: 8px"
          @mouseover="hoverSection(section.spans)"
          @mouseleave="hoverSection(undefined)"
        >
          <label>{{ section.name }}</label>
          <Textarea v-model="section.text" rows="2" auto-resize />
          <template v-if="section.name === 'Назначения' && section.text">
            <!-- эвристическая подсветка: подсказка врачу, не структурированные данные и не гарантия точности -->
            <p class="muted drug-hints" v-html="highlightDrugMentions(section.text)"></p>
            <p class="muted" style="font-size: 0.8rem">{{ t('doctor.scribe.drugHintNote') }}</p>
            <div class="actions">
              <Button :label="t('doctor.scribe.checkPrescription')" icon="pi pi-search" size="small" severity="secondary" @click="goCheckPrescription" />
            </div>
          </template>
        </div>
        <div class="field"><label>{{ t('doctor.scribe.leafletLabel') }}</label><Textarea v-model="leaflet" rows="5" auto-resize /></div>
        <div class="actions">
          <Button :label="t('doctor.scribe.approve')" icon="pi pi-check" :disabled="approved" @click="approve" />
          <a v-if="leafletUrl" :href="leafletUrl" target="_blank">{{ leafletUrl }}</a>
        </div>
        <div v-if="qrDataUrl" class="qr-block" style="margin-top: 12px">
          <p class="muted">{{ t('doctor.scribe.qrHint') }}</p>
          <img :src="qrDataUrl" :alt="t('doctor.scribe.qrAlt')" width="220" height="220" />
        </div>
      </div>
    </div>
  </main>
</template>
