<script setup lang="ts">
import Button from 'primevue/button'
import IconField from 'primevue/iconfield'
import InputIcon from 'primevue/inputicon'
import InputText from 'primevue/inputtext'
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { journal } from '@/api/endpoints'
import type { AuditEntry } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import PageShell from '@/components/ui/PageShell.vue'
import SidePanel from '@/components/ui/SidePanel.vue'
import Skeleton from '@/components/ui/Skeleton.vue'
import StatusTag from '@/components/ui/StatusTag.vue'
import { useLocaleFormat } from '@/composables/useLocaleFormat'
import { downloadCsv } from '@/lib/csv'
import { roleLabel } from '@/lib/decision'

/** Журнал аудита: актор — серверный фильтр, роль / метод / статус / период — чипами на клиенте по загруженным
 * страницам; путь mono, параметры и trace — в панели справа; статус чипом цвета. */
const PAGE_SIZE = 200
const PERIODS = [1, 7, 30] as const
const STATUS_GROUPS = ['2xx', '3xx', '4xx', '5xx'] as const
const { t } = useI18n()
const { dateTime } = useLocaleFormat()

const items = ref<AuditEntry[]>([])
const total = ref(0)
const error = ref<unknown>(null)
const loading = ref(false)
const actor = ref('')
const role = ref<string | null>(null)
const method = ref<string | null>(null)
const statusGroup = ref<string | null>(null)
const period = ref<number | null>(null)
const selected = ref<AuditEntry | null>(null)
const panelOpen = ref(false)
let page = 0

const group = (status: number) => `${Math.floor(status / 100)}xx`
const tone = (status: number): 'ok' | 'neutral' | 'warn' | 'danger' => (status < 300 ? 'ok' : status < 400 ? 'neutral' : status < 500 ? 'warn' : 'danger')
const roles = computed(() => [...new Set(items.value.map((e) => e.role))])
const methods = computed(() => [...new Set(items.value.map((e) => e.method))])
const visible = computed(() => {
  const since = period.value ? Date.now() - period.value * 86_400_000 : 0
  return items.value.filter(
    (e) => (!role.value || e.role === role.value) && (!method.value || e.method === method.value) && (!statusGroup.value || group(e.status) === statusGroup.value) && (!since || new Date(e.at).getTime() >= since),
  )
})
const count = (pred: (e: AuditEntry) => boolean) => items.value.filter(pred).length

async function load(reset = true) {
  loading.value = true
  error.value = null
  if (reset) page = 0
  try {
    const response = await journal.audit({ actor: actor.value.trim() || undefined, page: page + 1, size: PAGE_SIZE })
    items.value = reset ? response.items : [...items.value, ...response.items]
    total.value = response.total
    page += 1
  } catch (e) {
    error.value = e
    if (reset) items.value = []
  } finally {
    loading.value = false
  }
}

function open(entry: AuditEntry) {
  selected.value = entry
  panelOpen.value = true
}

function exportCsv() {
  downloadCsv('audit.csv', visible.value.map((e) => ({ at: e.at, actor: e.actor, role: e.role, method: e.method, path: e.path, query: e.query ?? '', status: e.status, durationMs: e.durationMs, traceId: e.traceId })))
}

onMounted(() => load())
</script>

<template>
  <PageShell :title="t('gov.audit.title')" :lead="`${t('gov.audit.lead')} ${t('gov.audit.total')}: ${total}.`">
    <template #actions>
      <IconField>
        <InputIcon class="pi pi-search" />
        <InputText v-model="actor" size="small" :placeholder="t('gov.audit.actorPlaceholder')" data-testid="audit-actor" @keyup.enter="load()" />
      </IconField>
      <Button :label="t('gov.audit.refresh')" icon="pi pi-refresh" size="small" severity="secondary" text :loading="loading" @click="load()" />
      <Button :label="t('shell.exportCsv')" icon="pi pi-download" size="small" severity="secondary" outlined :disabled="visible.length === 0" @click="exportCsv" />
    </template>
    <div class="toolbar">
      <div class="chips"><button v-for="r in roles" :key="r" type="button" class="chip-filter" :class="{ active: role === r }" @click="role = role === r ? null : r">{{ roleLabel(r) }} <span class="count">{{ count((e) => e.role === r) }}</span></button></div>
      <div class="chips"><button v-for="m in methods" :key="m" type="button" class="chip-filter mono" :class="{ active: method === m }" @click="method = method === m ? null : m">{{ m }} <span class="count">{{ count((e) => e.method === m) }}</span></button></div>
      <div class="chips"><button v-for="s in STATUS_GROUPS" :key="s" type="button" class="chip-filter mono" :class="{ active: statusGroup === s }" @click="statusGroup = statusGroup === s ? null : s">{{ s }} <span class="count">{{ count((e) => group(e.status) === s) }}</span></button></div>
      <div class="chips"><button v-for="p in PERIODS" :key="p" type="button" class="chip-filter" :class="{ active: period === p }" @click="period = period === p ? null : p">{{ p === 1 ? t('shell.today') : t('shell.lastDays', { days: p }) }}</button></div>
    </div>
    <ErrorBox :error="error" />
    <Skeleton v-if="loading && items.length === 0" kind="table" :lines="8" />
    <EmptyState v-else-if="visible.length === 0" :title="t('gov.audit.empty')" icon="pi pi-history" />
    <div v-else class="table-wrap card dense-card">
      <table class="dense-table" data-testid="audit-table">
        <thead><tr><th>{{ t('gov.audit.colWhen') }}</th><th>{{ t('gov.audit.colActor') }}</th><th>{{ t('gov.audit.colMethod') }}</th><th>{{ t('gov.audit.colPath') }}</th><th>{{ t('gov.audit.colStatus') }}</th><th class="num">{{ t('gov.audit.colDurationShort') }}</th></tr></thead>
        <tbody>
          <tr v-for="e in visible" :key="e.id" class="clickable" :class="{ selected: selected?.id === e.id && panelOpen }" @click="open(e)">
            <td class="nowrap">{{ dateTime(e.at) }}</td>
            <td>{{ e.actor }} <span class="muted small">· {{ roleLabel(e.role) }}</span></td>
            <td class="mono">{{ e.method }}</td>
            <td class="mono path">{{ e.path }}<span v-if="e.query" class="muted"> ?…</span></td>
            <td><StatusTag :value="String(e.status)" :tone="tone(e.status)" /></td>
            <td class="num muted">{{ e.durationMs }}</td>
          </tr>
        </tbody>
      </table>
      <div v-if="items.length < total" class="actions" style="padding: 8px 4px 12px">
        <Button :label="t('shell.loadMore', { shown: items.length, total })" size="small" severity="secondary" text :loading="loading" @click="load(false)" />
      </div>
    </div>

    <SidePanel v-model:visible="panelOpen" :title="selected ? `${selected.method} ${selected.status}` : ''" :subtitle="selected ? dateTime(selected.at) : ''">
      <dl v-if="selected" class="facts">
        <dt>{{ t('gov.audit.colActor') }}</dt><dd>{{ selected.actor }} · {{ roleLabel(selected.role) }}</dd>
        <dt>{{ t('gov.audit.colPath') }}</dt><dd class="mono break">{{ selected.path }}</dd>
        <dt>{{ t('gov.audit.colQuery') }}</dt><dd class="mono break">{{ selected.query || '—' }}</dd>
        <dt>{{ t('gov.audit.colStatus') }}</dt><dd><StatusTag :value="String(selected.status)" :tone="tone(selected.status)" /></dd>
        <dt>{{ t('gov.audit.colDuration') }}</dt><dd class="tabular">{{ selected.durationMs }}</dd>
        <dt>{{ t('gov.audit.colTrace') }}</dt><dd class="mono break">{{ selected.traceId }}</dd>
      </dl>
    </SidePanel>
  </PageShell>
</template>

<style scoped>
.dense-card { padding: 0 var(--dm-space-2); }
.nowrap { white-space: nowrap; }
.path { max-width: 420px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.break { word-break: break-all; }
</style>
