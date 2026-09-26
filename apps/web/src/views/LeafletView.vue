<script setup lang="ts">
import Button from 'primevue/button'
import { useToast } from 'primevue/usetoast'
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute } from 'vue-router'
import { ApiError } from '@/api/client'
import { scribe } from '@/api/endpoints'
import ErrorBox from '@/components/ErrorBox.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import Skeleton from '@/components/ui/Skeleton.vue'
import { useLocaleFormat } from '@/composables/useLocaleFormat'

/** Памятка пациенту: документ на 640 px без навигации приложения — шапка (организация, дата), секции крупным шрифтом,
 * «Скопировать ссылку» и печать средствами браузера. Истёкший или чужой токен — сообщение без деталей. */
const { t } = useI18n()
const { dateTime } = useLocaleFormat()
const route = useRoute()
const toast = useToast()
const text = ref('')
const approvedAt = ref('')
const language = ref('')
const error = ref<unknown>(null)
const expired = ref(false)
const loading = ref(true)

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

async function copyLink() {
  try {
    await navigator.clipboard.writeText(window.location.href)
    toast.add({ severity: 'info', summary: t('shell.copied'), life: 2000 })
  } catch {
    toast.add({ severity: 'warn', summary: window.location.href, life: 5000 })
  }
}

function print() {
  window.print()
}

onMounted(async () => {
  try {
    const leaflet = await scribe.leaflet(String(route.params.token))
    text.value = leaflet.text
    approvedAt.value = leaflet.approvedAt
    language.value = leaflet.language
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
    <header class="doc-head">
      <div>
        <div class="brand">Darumen Care</div>
        <h1>{{ t('leaflet.title') }}</h1>
        <p v-if="approvedAt" class="muted">{{ t('leaflet.approvedBy') }} · {{ dateTime(approvedAt) }}<template v-if="language"> · {{ language.toUpperCase() }}</template></p>
      </div>
      <div class="doc-actions no-print">
        <Button :label="t('shell.copyLink')" icon="pi pi-link" size="small" severity="secondary" outlined @click="copyLink" />
        <Button :label="t('shell.print')" icon="pi pi-print" size="small" severity="secondary" text @click="print" />
      </div>
    </header>
    <ErrorBox :error="error" />
    <Skeleton v-if="loading" :lines="6" />
    <EmptyState v-else-if="expired" :title="t('leaflet.expiredTitle')" :text="t('leaflet.expiredText')" icon="pi pi-clock" />
    <article v-else class="doc card" data-testid="leaflet-doc">
      <section v-for="(s, i) in sections" :key="i" class="section">
        <h2 v-if="s.title">{{ s.title }}</h2>
        <p>{{ s.body }}</p>
      </section>
      <p class="muted small foot">{{ t('leaflet.footer') }}</p>
    </article>
  </main>
</template>

<style scoped>
.doc-head { display: flex; justify-content: space-between; gap: 16px; align-items: flex-start; flex-wrap: wrap; margin-bottom: var(--dm-space-4); }
.brand { color: var(--dm-accent); font-weight: 700; font-size: 0.9rem; letter-spacing: 0.04em; text-transform: uppercase; }
.doc-actions { display: flex; gap: 8px; }
.doc { padding: var(--dm-space-5); font-size: 1.1rem; line-height: 1.6; }
.section + .section { margin-top: var(--dm-space-4); }
.section h2 { font-size: 1.1rem; margin: 0 0 6px; }
.section p { margin: 0; white-space: pre-wrap; }
.foot { margin-top: var(--dm-space-5); font-size: 0.85rem; line-height: 1.4; }
@media print {
  .no-print { display: none; }
  .doc { border: 0; padding: 0; }
}
</style>
