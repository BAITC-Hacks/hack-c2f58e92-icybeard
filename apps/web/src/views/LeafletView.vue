<script setup lang="ts">
import QRCode from 'qrcode'
import Button from 'primevue/button'
import { useToast } from 'primevue/usetoast'
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute } from 'vue-router'
import { ApiError } from '@/api/client'
import { scribe } from '@/api/endpoints'
import BrandMark from '@/components/app/BrandMark.vue'
import ErrorBox from '@/components/ErrorBox.vue'
import OriginTag from '@/components/OriginTag.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import Skeleton from '@/components/ui/Skeleton.vue'
import { useLocaleFormat } from '@/composables/useLocaleFormat'

/** Памятка пациенту (W-Leaflet): документ 720 px на белом без навигации — шапка со знаком и номером памятки (хвост
 * токена), заголовок с датой утверждения, первый абзац — плашка «Что дальше», остальные секции — нумерованные блоки
 * (в тексте они помечены строкой с двоеточием), внизу QR и ссылка (QR строится на клиенте). API отдаёт только текст,
 * язык и дату утверждения: организации, врача и срока действия в ответе нет, они не показываются. Печать — средствами
 * браузера. Истёкший или чужой токен — сообщение без деталей. */
const { t } = useI18n()
const { dateTime } = useLocaleFormat()
const route = useRoute()
const toast = useToast()
const text = ref('')
const approvedAt = ref('')
const language = ref('')
const qrDataUrl = ref<string | null>(null)
const error = ref<unknown>(null)
const expired = ref(false)
const loading = ref(true)

const token = computed(() => String(route.params.token))
const number = computed(() => token.value.slice(-8).toUpperCase())
const link = computed(() => window.location.href)

/** Секции — абзацы через пустую строку; строка с двоеточием в конце или короткая заглавная — заголовок секции. */
const sections = computed(() =>
  text.value
    .split(/\n\s*\n/)
    .map((block) => block.trim())
    .filter(Boolean)
    .map((block) => {
      const lines = block.split('\n')
      const first = lines[0] ?? ''
      const heading = lines.length > 1 && (first.endsWith(':') || (first.length < 60 && first === first.toUpperCase()))
      return heading ? { title: first.replace(/:$/, ''), body: lines.slice(1).join('\n') } : { title: '', body: block }
    }),
)
/** Первый абзац без заголовка — плашка «Что дальше»; остальное — нумерованные блоки. */
const intro = computed(() => (sections.value[0] && !sections.value[0].title ? sections.value[0] : null))
const steps = computed(() => (intro.value ? sections.value.slice(1) : sections.value))

async function copyLink() {
  try {
    await navigator.clipboard.writeText(link.value)
    toast.add({ severity: 'info', summary: t('shell.copied'), life: 2000 })
  } catch {
    toast.add({ severity: 'warn', summary: link.value, life: 5000 })
  }
}

function print() {
  window.print()
}

onMounted(async () => {
  try {
    const leaflet = await scribe.leaflet(token.value)
    text.value = leaflet.text
    approvedAt.value = leaflet.approvedAt
    language.value = leaflet.language
    try {
      qrDataUrl.value = await QRCode.toDataURL(link.value, { margin: 1, width: 160 })
    } catch {
      qrDataUrl.value = null // QR — вспомогательный элемент, без него памятка читается
    }
  } catch (e) {
    if (e instanceof ApiError && (e.status === 404 || e.status === 410 || e.status === 403)) expired.value = true
    else error.value = e
  } finally {
    loading.value = false
  }
})
</script>

<template>
  <main class="page leaflet">
    <article class="doc card" data-testid="leaflet-doc">
      <header class="doc-brand">
        <span class="brand"><BrandMark :size="24" /> Darumen Health</span>
        <span class="spacer" />
        <span class="caption">{{ t('leaflet.number', { id: number }) }}<template v-if="language"> · {{ language.toUpperCase() }}</template></span>
      </header>
      <div class="doc-head">
        <h1>{{ t('leaflet.title') }}</h1>
        <p v-if="approvedAt" class="muted">{{ t('leaflet.approvedOn', { date: dateTime(approvedAt) }) }} · {{ t('leaflet.approvedBy').toLowerCase() }}</p>
      </div>
      <div class="doc-actions no-print">
        <Button :label="t('shell.copyLink')" icon="pi pi-link" size="small" severity="secondary" @click="copyLink" />
        <Button :label="t('shell.print')" icon="pi pi-print" size="small" severity="secondary" text @click="print" />
      </div>
      <ErrorBox :error="error" />
      <Skeleton v-if="loading" :lines="6" />
      <EmptyState v-else-if="expired" :title="t('leaflet.expiredTitle')" :text="t('leaflet.expiredText')" icon="pi pi-clock" />
      <template v-else>
        <div v-if="intro" class="what-next"><span class="strong">{{ t('leaflet.whatNext') }}:</span> {{ intro.body }}</div>
        <ol class="steps">
          <li v-for="(s, i) in steps" :key="i" class="step">
            <span class="step-num" aria-hidden="true">{{ i + 1 }}</span>
            <span class="step-body">
              <span v-if="s.title" class="step-title">{{ s.title }}</span>
              <span class="step-text">{{ s.body }}</span>
            </span>
          </li>
        </ol>
        <section class="talked">
          <div class="talked-head"><span class="strong">{{ t('leaflet.talked') }}</span><OriginTag kind="ai" /></div>
          <p class="caption">{{ t('leaflet.footer') }}</p>
        </section>
        <footer class="doc-foot">
          <img v-if="qrDataUrl" :src="qrDataUrl" :alt="t('leaflet.qrCaption')" width="120" height="120" class="qr" />
          <div class="foot-text">
            <a :href="link" class="mono link">{{ link.replace(/^https?:\/\//, '') }}</a>
            <span class="caption">{{ t('leaflet.audioDeleted') }}</span>
            <span class="caption">{{ t('leaflet.noPersona') }}</span>
            <span class="caption">{{ t('leaflet.synthetic') }}</span>
          </div>
        </footer>
      </template>
    </article>
  </main>
</template>

<style scoped>
.leaflet { padding-block: 24px; }
.doc { padding: 40px; display: flex; flex-direction: column; gap: 20px; font-size: var(--dm-text-base); line-height: 1.55; }
.doc-brand { display: flex; align-items: center; gap: 12px; }
.brand { display: inline-flex; align-items: center; gap: 8px; font-weight: 600; letter-spacing: -0.02em; color: var(--dm-ink); }
.spacer { flex: 1; }
.doc-head h1 { font-size: 29px; }
.doc-head p { margin: 4px 0 0; font-size: var(--dm-text-md); }
.doc-actions { display: flex; gap: 8px; }
.what-next { background: var(--dm-ok-soft); color: var(--dm-ink); border-radius: var(--dm-radius-md); padding: 14px 16px; }
.strong { font-weight: 500; }
.steps { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; gap: 16px; }
.step { display: flex; gap: 14px; }
.step-num { width: 28px; height: 28px; border-radius: 50%; background: var(--dm-primary); color: var(--dm-primary-contrast); display: grid; place-items: center; font-size: var(--dm-text-sm); font-weight: 500; flex: none; }
.step-body { display: flex; flex-direction: column; gap: 4px; }
.step-title { font-weight: 500; }
.step-text { white-space: pre-wrap; }
.talked { border-top: 1px solid var(--dm-hairline); padding-top: 16px; }
.talked-head { display: flex; align-items: center; gap: 10px; margin-bottom: 6px; }
.doc-foot { display: flex; gap: 20px; align-items: flex-start; border-top: 1px solid var(--dm-hairline); padding-top: 20px; }
.qr { flex: none; border-radius: var(--dm-radius-sm); }
.foot-text { display: flex; flex-direction: column; gap: 6px; min-width: 0; }
.link { word-break: break-all; font-size: var(--dm-text-sm); }
@media print {
  .no-print { display: none; }
  .doc { padding: 0; }
}
</style>
