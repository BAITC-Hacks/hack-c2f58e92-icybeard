<script setup lang="ts">
import Button from 'primevue/button'
import Checkbox from 'primevue/checkbox'
import Select from 'primevue/select'
import Textarea from 'primevue/textarea'
import { useToast } from 'primevue/usetoast'
import { onBeforeUnmount, onMounted, ref } from 'vue'
import { scribe } from '@/api/endpoints'
import type { ScribeDraft, ScribeHealth } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import OriginTag from '@/components/OriginTag.vue'

const toast = useToast()
const consent = ref(false)
const language = ref<'ru' | 'kk'>('ru')
const sessionId = ref<string | null>(null)
const health = ref<ScribeHealth | null>(null)
const transcript = ref('')
const typed = ref('Пациент жалуется на боль в груди при нагрузке. Давление 150 на 95. Диагноз гипертоническая болезнь. Назначаю амлодипин 5 мг утром.')
const draft = ref<ScribeDraft | null>(null)
const leaflet = ref('')
const leafletUrl = ref<string | null>(null)
const error = ref<unknown>(null)
const busy = ref(false)
const recording = ref(false)
let recorder: MediaRecorder | null = null
let chunks: Blob[] = []
const canRecord = typeof MediaRecorder !== 'undefined' && !!navigator.mediaDevices

async function start() {
  error.value = null
  try {
    sessionId.value = (await scribe.createSession(consent.value, language.value)).sessionId
    draft.value = null
    transcript.value = ''
    leafletUrl.value = null
  } catch (e) {
    error.value = e
  }
}

async function record() {
  if (!canRecord) return
  const stream = await navigator.mediaDevices.getUserMedia({ audio: true })
  recorder = new MediaRecorder(stream, { mimeType: 'audio/webm' })
  chunks = []
  recorder.ondataavailable = (e) => chunks.push(e.data)
  recorder.onstop = async () => {
    stream.getTracks().forEach((t) => t.stop())
    await upload(new Blob(chunks, { type: 'audio/webm' }), 'consult.webm')
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
    transcript.value = (await scribe.uploadAudio(sessionId.value, file, name)).text
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
    await scribe.setTranscript(sessionId.value, typed.value)
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
    leafletUrl.value = `${window.location.origin}/leaflet/${result.leafletToken}`
    toast.add({ severity: 'success', summary: 'Запись утверждена, аудио удалено', life: 3000 })
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
    <h1>AI-скрайб приёма</h1>
    <p class="lead">С согласия пациента приём записывается, стенограмма превращается в черновик записи по разделам. Врач правит и утверждает, пациент получает памятку по ссылке. Аудио удаляется при утверждении.</p>
    <p v-if="health" class="muted">стенограмма: {{ health.transcriber }} · черновик: {{ health.drafter }}</p>
    <p v-else class="muted">Сервис скрайба не запущен (make scribe-serve).</p>
    <div class="card">
      <div class="actions" style="align-items: center">
        <Checkbox v-model="consent" binary input-id="consent" /><label for="consent">Пациент дал согласие на запись</label>
        <Select v-model="language" :options="['ru', 'kk']" size="small" />
        <Button label="Начать сессию" icon="pi pi-play" :disabled="!consent" @click="start" />
        <span v-if="sessionId" class="muted">сессия {{ sessionId }}</span>
      </div>
      <ErrorBox :error="error" />
    </div>
    <div v-if="sessionId" class="grid cols-2" style="margin-top: 16px">
      <div class="card">
        <h2>Стенограмма</h2>
        <div class="actions">
          <Button v-if="canRecord && !recording" label="Записать с микрофона" icon="pi pi-microphone" severity="secondary" @click="record" />
          <Button v-if="recording" label="Остановить" icon="pi pi-stop" severity="danger" @click="stop" />
          <label class="p-button p-button-secondary p-button-sm" style="cursor: pointer">загрузить файл<input type="file" accept="audio/*" hidden @change="onFile" /></label>
        </div>
        <div class="field" style="margin-top: 12px"><label>или напечатайте текст приёма</label><Textarea v-model="typed" rows="4" auto-resize /></div>
        <div class="actions"><Button label="Использовать текст" size="small" severity="secondary" @click="useTyped" /></div>
        <p v-if="transcript" style="white-space: pre-wrap; margin-top: 12px">{{ transcript }}</p>
        <div class="actions"><Button label="Составить черновик" icon="pi pi-file-edit" :disabled="!transcript" :loading="busy" @click="makeDraft" /></div>
      </div>
      <div v-if="draft" class="card">
        <h2>Черновик записи ({{ draft.model }}) <OriginTag kind="ai" note="Черновик сгенерирован из стенограммы; в запись попадает только после утверждения врачом" /></h2>
        <div v-for="section in draft.sections" :key="section.name" class="field" style="margin-bottom: 8px">
          <label>{{ section.name }}</label>
          <Textarea v-model="section.text" rows="2" auto-resize />
        </div>
        <div class="field"><label>Памятка пациенту</label><Textarea v-model="leaflet" rows="5" auto-resize /></div>
        <div class="actions">
          <Button label="Утвердить и выдать памятку" icon="pi pi-check" @click="approve" />
          <a v-if="leafletUrl" :href="leafletUrl" target="_blank">{{ leafletUrl }}</a>
        </div>
      </div>
    </div>
  </main>
</template>
