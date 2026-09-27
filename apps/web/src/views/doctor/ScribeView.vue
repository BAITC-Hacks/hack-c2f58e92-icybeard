<script setup lang="ts">
import QRCode from 'qrcode'
import Button from 'primevue/button'
import Checkbox from 'primevue/checkbox'
import InputText from 'primevue/inputtext'
import SelectButton from 'primevue/selectbutton'
import Tab from 'primevue/tab'
import TabList from 'primevue/tablist'
import TabPanel from 'primevue/tabpanel'
import TabPanels from 'primevue/tabpanels'
import Tabs from 'primevue/tabs'
import Textarea from 'primevue/textarea'
import { useToast } from 'primevue/usetoast'
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { kk } from '@/i18n/kk'
import { ru } from '@/i18n/ru'
import { useRouter } from 'vue-router'
import { scribe } from '@/api/endpoints'
import type { ScribeDraft, ScribeHealth, ScribeSegment } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import OriginTag from '@/components/OriginTag.vue'
import AppCard from '@/components/ui/AppCard.vue'
import PageShell from '@/components/ui/PageShell.vue'
import StatusTag from '@/components/ui/StatusTag.vue'
import { pickRecordingFormat } from '@/lib/audio'
import { useRecorder } from '@/composables/useRecorder'

// Простая эвристика для подсветки вероятных упоминаний препаратов в разделе «Назначения»:
// слово с заглавной буквы рядом с дозировкой (мг/мл/мкг/ЕД) или после характерных глаголов назначения.
// Это подсказка врачу для беглого просмотра, а не структурированное извлечение данных.
const DRUG_HINT_RE =
  /([A-ZА-ЯЁ][a-zа-яё]{2,}(?:\s+[a-zа-яё]{3,})?\s*\d+(?:[.,]\d+)?\s*(?:мг|мл|мкг|ед)\b)|((?:принимать|назначить|назначаю|таблетки|капли)\s+[A-ZА-ЯЁa-zа-яё][a-zа-яёA-ZА-ЯЁ-]{2,})/giu
/** Буквы, которые есть в казахском алфавите и нет в русском — метка языка сегмента стенограммы. */
const KK_LETTERS = /[әіңғүұқөһӘІҢҒҮҰҚӨҺ]/u

function escapeHtml(text: string): string {
  return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
}
function highlightDrugMentions(text: string): string {
  return escapeHtml(text).replace(DRUG_HINT_RE, (m) => `<mark class="drug-hint">${m}</mark>`)
}
function segmentLang(text: string): 'kk' | 'ru' {
  return KK_LETTERS.test(text) ? 'kk' : 'ru'
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
// реф пациента — подпись сессии на экране врача; в сервис скрайба не передаётся (сессия анонимна)
const patientRef = ref('')
const sessionId = ref<string | null>(null)
const health = ref<ScribeHealth | null>(null)
const transcript = ref('')
const segments = ref<ScribeSegment[]>([])
const typed = ref('')
const showTyped = ref(false)
const prescriptionSections = [ru.doctor.scribe.sectionPrescriptions, kk.doctor.scribe.sectionPrescriptions]
const draft = ref<ScribeDraft | null>(null)
const leaflet = ref('')
const leafletUrl = ref<string | null>(null)
const qrDataUrl = ref<string | null>(null)
const hoveredSpans = ref<{ t0: number; t1: number }[] | null>(null)
const error = ref<unknown>(null)
const busy = ref(false)
const approved = ref(false)
const tab = ref('draft')

const recordingFormat = typeof MediaRecorder !== 'undefined' && !!navigator.mediaDevices ? pickRecordingFormat((type) => MediaRecorder.isTypeSupported(type)) : null
const recorder = useRecorder(recordingFormat, (blob, name) => upload(blob, name))

const status = computed(() => {
  if (approved.value) return { key: 'approved', tone: 'ok' as const }
  if (recorder.recording.value) return { key: 'recording', tone: 'danger' as const }
  if (busy.value) return { key: 'processing', tone: 'warn' as const }
  if (draft.value) return { key: 'draft', tone: 'accent' as const }
  if (transcript.value) return { key: 'transcribed', tone: 'accent' as const }
  if (sessionId.value) return { key: 'ready', tone: 'neutral' as const }
  return { key: 'none', tone: 'neutral' as const }
})
const timer = computed(() => {
  const s = recorder.elapsed.value
  return `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`
})

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
  return !!hoveredSpans.value?.some((span) => span.t0 < segment.t1 && span.t1 > segment.t0)
}
function hoverSection(spans: { t0: number; t1: number }[] | undefined) {
  hoveredSpans.value = spans && spans.length ? spans : null
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

async function makeDraft() {
  if (!sessionId.value) return
  busy.value = true
  error.value = null
  try {
    const made = await scribe.draft(sessionId.value)
    draft.value = made
    leaflet.value = made.patientLeaflet.text
    tab.value = 'draft'
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
    approved.value = true
    try {
      qrDataUrl.value = await QRCode.toDataURL(leafletUrl.value, { margin: 1, width: 200 })
    } catch {
      qrDataUrl.value = null // QR — вспомогательная функция, отсутствие картинки не должно ломать утверждение
    }
    toast.add({ severity: 'success', summary: t('doctor.scribe.approvedToast'), life: 3000 })
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

onMounted(async () => {
  try {
    health.value = await scribe.health()
  } catch {
    health.value = null
  }
})
onBeforeUnmount(() => recorder.dispose())
</script>

<template>
  <PageShell :title="t('doctor.scribe.title')" :lead="t('doctor.scribe.lead')">
    <AppCard dense class="session-row" data-testid="scribe-session">
      <div class="session">
        <div class="field"><label>{{ t('doctor.scribe.patientRef') }}</label><InputText v-model="patientRef" size="small" placeholder="SYN-…" :disabled="approved" /></div>
        <div class="field"><label>{{ t('doctor.scribe.language') }}</label><SelectButton v-model="language" :options="languageOptions" option-label="label" option-value="value" size="small" :allow-empty="false" :disabled="!!sessionId" /></div>
        <div class="field"><label>{{ t('doctor.scribe.timer') }}</label><span class="mono timer" :class="{ live: recorder.recording.value }">{{ timer }}</span></div>
        <div class="field"><label>{{ t('doctor.scribe.status') }}</label><StatusTag :value="t('doctor.scribe.state.' + status.key)" :tone="status.tone" /></div>
        <span v-if="sessionId" class="muted small session-id">{{ t('doctor.scribe.session') }} <span class="mono">{{ sessionId }}</span></span>
      </div>
    </AppCard>
    <ErrorBox :error="error" />

    <div class="grid cols-2">
      <div class="col">
        <AppCard v-if="!sessionId" :title="t('doctor.scribe.consentTitle')">
          <label class="consent-row"><Checkbox v-model="consent" binary input-id="consent" /> <span>{{ t('doctor.scribe.consent') }}</span></label>
          <ul class="muted small what">
            <li>{{ t('doctor.scribe.what1') }}</li>
            <li>{{ t('doctor.scribe.what2') }}</li>
            <li>{{ t('doctor.scribe.what3') }}</li>
          </ul>
          <p v-if="!health" class="muted small">{{ t('doctor.scribe.serviceDown') }}</p>
          <div class="actions"><Button :label="t('doctor.scribe.startSession')" icon="pi pi-play" :disabled="!consent || !health" data-testid="scribe-start" @click="start" /></div>
        </AppCard>

        <AppCard v-else :title="t('doctor.scribe.recording')">
          <div class="wave" :class="{ live: recorder.recording.value }" aria-hidden="true">
            <span v-for="(level, i) in recorder.levels.value" :key="i" class="bar" :style="{ height: `${Math.max(8, level * 100)}%` }" />
          </div>
          <div class="actions rec-actions">
            <Button v-if="recorder.canRecord && !recorder.recording.value" :label="t('doctor.scribe.recordMic')" icon="pi pi-microphone" :disabled="approved || busy" @click="record" />
            <Button v-if="recorder.recording.value" :label="t('doctor.scribe.stop')" icon="pi pi-stop" @click="recorder.stop()" />
            <label v-if="!approved" class="p-button p-button-secondary p-button-sm upload">{{ t('doctor.scribe.uploadFile') }}<input type="file" accept="audio/*" hidden @change="onFile" /></label>
            <Button :label="t('doctor.scribe.pasteText')" size="small" text severity="secondary" :disabled="approved" @click="showTyped = !showTyped" />
          </div>
          <div v-if="showTyped" class="field" style="margin-top: 12px">
            <label>{{ t('doctor.scribe.orType') }}</label>
            <Textarea v-model="typed" rows="4" auto-resize />
            <div class="actions">
              <Button :label="t('doctor.scribe.useText')" size="small" severity="secondary" :disabled="approved || !typed" @click="useTyped" />
              <Button :label="t('doctor.scribe.pasteSample')" size="small" text data-testid="scribe-sample" @click="typed = t('doctor.scribe.sampleTranscript')" />
            </div>
          </div>
        </AppCard>

        <AppCard v-if="sessionId" :title="t('doctor.scribe.transcript')">
          <div v-if="segments.length" class="transcript-segments">
            <p v-for="(segment, i) in segments" :key="i" class="segment" :class="{ 'segment-highlight': isSegmentHighlighted(segment) }">
              <span class="mono muted">[{{ segment.t0.toFixed(0) }}–{{ segment.t1.toFixed(0) }}]</span>
              <StatusTag :value="segmentLang(segment.text).toUpperCase()" tone="neutral" class="lang" />
              {{ segment.text }}
            </p>
          </div>
          <p v-else-if="transcript" style="white-space: pre-wrap">{{ transcript }}</p>
          <p v-else class="muted">{{ busy ? t('doctor.scribe.transcribing') : t('doctor.scribe.noTranscript') }}</p>
          <div class="actions"><Button :label="t('doctor.scribe.makeDraft')" icon="pi pi-file-edit" :disabled="!transcript || approved" :loading="busy && !!transcript" data-testid="scribe-draft" @click="makeDraft" /></div>
        </AppCard>
      </div>

      <div class="col">
        <AppCard>
          <Tabs v-model:value="tab">
            <TabList>
              <Tab value="draft">{{ t('doctor.scribe.draftTitle') }} <OriginTag kind="ai" :note="t('doctor.scribe.draftNote')" /></Tab>
              <Tab value="leaflet">{{ t('doctor.scribe.leafletLabel') }}</Tab>
            </TabList>
            <TabPanels>
              <TabPanel value="draft">
                <p v-if="!draft" class="muted">{{ t('doctor.scribe.noDraft') }}</p>
                <template v-else>
                  <div v-for="section in draft.sections" :key="section.name" class="field section" @mouseover="hoverSection(section.spans)" @mouseleave="hoverSection(undefined)">
                    <label>{{ section.name }}</label>
                    <Textarea v-model="section.text" rows="2" auto-resize :disabled="approved" />
                    <template v-if="prescriptionSections.includes(section.name) && section.text">
                      <p class="muted small drug-hints" v-html="highlightDrugMentions(section.text)"></p>
                      <p class="muted small">{{ t('doctor.scribe.drugHintNote') }}</p>
                      <Button :label="t('doctor.scribe.checkPrescription')" icon="pi pi-search" size="small" severity="secondary" text @click="router.push({ name: 'medicines' })" />
                    </template>
                  </div>
                  <p class="muted small">{{ t('common.model') }}: {{ draft.model }}</p>
                </template>
              </TabPanel>
              <TabPanel value="leaflet">
                <p v-if="!draft" class="muted">{{ t('doctor.scribe.noDraft') }}</p>
                <div v-else class="field"><label>{{ t('doctor.scribe.leafletLabel') }}</label><Textarea v-model="leaflet" rows="8" auto-resize :disabled="approved" /></div>
              </TabPanel>
            </TabPanels>
          </Tabs>
          <div class="actions">
            <Button :label="t('doctor.scribe.approveAll')" icon="pi pi-check" :disabled="!draft || approved" data-testid="scribe-approve" @click="approve" />
          </div>
          <div v-if="approved" class="result" data-testid="scribe-result">
            <StatusTag :value="t('doctor.scribe.audioDeleted')" tone="ok" icon="pi pi-trash" />
            <div class="link-row">
              <a v-if="leafletUrl" :href="leafletUrl" target="_blank" class="mono">{{ leafletUrl }}</a>
              <Button :label="t('shell.copyLink')" icon="pi pi-copy" size="small" severity="secondary" @click="copyLink" />
            </div>
            <div v-if="qrDataUrl" class="qr-block">
              <img :src="qrDataUrl" :alt="t('doctor.scribe.qrAlt')" width="200" height="200" />
              <p class="muted small">{{ t('doctor.scribe.qrHint') }}</p>
            </div>
          </div>
        </AppCard>
      </div>
    </div>
    <p class="muted small models">
      <template v-if="health">{{ t('doctor.scribe.transcriber') }}: {{ health.transcriber }} · {{ t('doctor.scribe.drafter') }}: {{ health.drafter }}</template>
      <template v-else>{{ t('doctor.scribe.serviceDown') }}</template>
    </p>
  </PageShell>
</template>

<style scoped>
.session { display: flex; gap: var(--dm-space-4); align-items: flex-end; flex-wrap: wrap; }
.session .field { min-width: 120px; }
.timer { font-size: var(--dm-text-kpi); font-weight: 600; letter-spacing: -0.02em; font-family: inherit; line-height: 1; }
.timer.live { color: var(--dm-danger); }
.session-id { margin-left: auto; }
.consent-row { display: flex; align-items: center; gap: 8px; font-weight: 500; cursor: pointer; }
.what { margin: 8px 0 0; padding-left: 20px; }
.wave { display: flex; align-items: center; gap: 3px; height: 56px; padding: 0 4px; border-radius: var(--dm-radius-md); background: var(--dm-surface-2); }
.wave .bar { flex: 1; background: var(--dm-dot-idle); border-radius: 2px; transition: height 0.08s linear; }
.wave.live .bar { background: var(--dm-ink); }
.rec-actions { align-items: center; }
.upload { cursor: pointer; }
.segment { display: flex; gap: 8px; align-items: baseline; flex-wrap: wrap; }
.lang { font-size: 0.65rem; padding: 3px 6px; }
.section { margin-bottom: 8px; }
.result { margin-top: 12px; display: flex; flex-direction: column; gap: 8px; }
.link-row { display: flex; gap: 8px; align-items: center; flex-wrap: wrap; word-break: break-all; }
.models { margin: 0; }
</style>
