<script setup lang="ts">
import Button from 'primevue/button'
import IconField from 'primevue/iconfield'
import InputIcon from 'primevue/inputicon'
import InputText from 'primevue/inputtext'
import Select from 'primevue/select'
import { computed, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { journal } from '@/api/endpoints'
import type { AuditEntry } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import AppCard from '@/components/ui/AppCard.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import KpiRow from '@/components/ui/KpiRow.vue'
import KpiTile from '@/components/ui/KpiTile.vue'
import PageShell from '@/components/ui/PageShell.vue'
import SidePanel from '@/components/ui/SidePanel.vue'
import Skeleton from '@/components/ui/Skeleton.vue'
import StatusTag from '@/components/ui/StatusTag.vue'
import { useLocaleFormat } from '@/composables/useLocaleFormat'
import { downloadCsv } from '@/lib/csv'
import { roleLabel } from '@/lib/decision'

/** Журнал аудита (W-Audit): фильтры роль/период/действие, четыре KPI (запросов за период, акторов, обращений к
 * персональным полям, отказов 403), таблица «время · пользователь · роль · действие · объект · результат»
 * с постраничной навигацией; панель записи справа. Актор — серверный фильтр, остальное — по загруженным страницам.
 * Региона в записи аудита нет (API отдаёт путь, роль, актор, статус, длительность, trace). */
const PAGE_SIZE = 200
const ROWS_PER_PAGE = 20
const PERIODS = [1, 7, 30] as const
/** Пути, где встречаются персональные поля: обращений к ним по правилу продукта быть не должно. */
const PERSONA_PATTERN = /iin|cardnumber|persona/i
const { t } = useI18n()
const { dateTime } = useLocaleFormat()

const items = ref<AuditEntry[]>([])
const total = ref(0)
const error = ref<unknown>(null)
const loading = ref(false)
const actor = ref('')
const role = ref<string>('')
const method = ref<string>('')
const period = ref<number>(7)
const pageIndex = ref(0)
const selected = ref<AuditEntry | null>(null)
const panelOpen = ref(false)
let page = 0

const tone = (status: number): 'ok' | 'neutral' | 'warn' | 'danger' => (status < 300 ? 'ok' : status < 400 ? 'neutral' : status < 500 ? 'warn' : 'danger')
const inPeriod = computed(() => {
  const since = Date.now() - period.value * 86_400_000
  return items.value.filter((e) => new Date(e.at).getTime() >= since)
})
const roleOptions = computed(() => [{ value: '', label: t('gov.audit.roleAll') }, ...[...new Set(items.value.map((e) => e.role))].map((r) => ({ value: r, label: roleLabel(r) }))])
const methodOptions = computed(() => [{ value: '', label: t('gov.audit.actionAll') }, ...[...new Set(items.value.map((e) => e.method))].map((m) => ({ value: m, label: m }))])
const visible = computed(() => inPeriod.value.filter((e) => (!role.value || e.role === role.value) && (!method.value || e.method === method.value)))
const pages = computed(() => Math.max(1, Math.ceil(visible.value.length / ROWS_PER_PAGE)))
const pageRows = computed(() => visible.value.slice(pageIndex.value * ROWS_PER_PAGE, (pageIndex.value + 1) * ROWS_PER_PAGE))
const kpis = computed(() => ({
  requests: inPeriod.value.length,
  actors: new Set(inPeriod.value.map((e) => e.actor)).size,
  persona: inPeriod.value.filter((e) => PERSONA_PATTERN.test(e.path) || PERSONA_PATTERN.test(e.query ?? '')).length,
  denied: inPeriod.value.filter((e) => e.status === 403).length,
}))
/** Объект запроса: параметры запроса, а без них — хвост пути после ресурса. */
const objectOf = (e: AuditEntry) => e.query ?? e.path.split('/').slice(4).join('/')

async function load(reset = true) {
  loading.value = true
  error.value = null
  if (reset) {
    page = 0
    pageIndex.value = 0
  }
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

async function next() {
  if (pageIndex.value + 1 < pages.value) pageIndex.value += 1
  else if (items.value.length < total.value) {
    await load(false)
    pageIndex.value += 1
  }
}

function open(entry: AuditEntry) {
  selected.value = entry
  panelOpen.value = true
}

function exportCsv() {
  downloadCsv('audit.csv', visible.value.map((e) => ({ at: e.at, actor: e.actor, role: e.role, method: e.method, path: e.path, query: e.query ?? '', status: e.status, durationMs: e.durationMs, traceId: e.traceId })))
}

watch([role, method, period], () => (pageIndex.value = 0))
onMounted(() => load())
</script>

<template>
  <PageShell :title="t('gov.audit.title')">
    <template #subtitle>{{ t('gov.audit.subtitle') }}</template>
    <template #actions>
      <IconField>
        <InputIcon class="pi pi-search" />
        <InputText v-model="actor" size="small" :placeholder="t('gov.audit.actorPlaceholder')" data-testid="audit-actor" @keyup.enter="load()" />
      </IconField>
      <Button :label="t('gov.audit.refresh')" icon="pi pi-refresh" size="small" severity="secondary" text :loading="loading" @click="load()" />
      <Button :label="t('shell.exportCsv')" icon="pi pi-download" size="small" severity="secondary" :disabled="visible.length === 0" @click="exportCsv" />
    </template>
    <div class="toolbar">
      <Select v-model="role" :options="roleOptions" option-label="label" option-value="value" size="small" :placeholder="t('gov.audit.roleAll')" />
      <div class="chips"><button v-for="p in PERIODS" :key="p" type="button" class="chip-filter" :class="{ active: period === p }" @click="period = p">{{ t('gov.audit.periodDays', { days: p }) }}</button></div>
      <Select v-model="method" :options="methodOptions" option-label="label" option-value="value" size="small" :placeholder="t('gov.audit.actionAll')" />
      <span class="spacer" />
      <span class="caption">{{ t('gov.audit.shown', { shown: pageRows.length, total: visible.length }) }} · {{ t('gov.audit.total') }}: {{ total }}</span>
    </div>
    <ErrorBox :error="error" />

    <KpiRow data-testid="audit-kpis">
      <KpiTile :value="kpis.requests" :label="t('gov.audit.kpiRequests', { days: period })" :loading="loading && items.length === 0" />
      <KpiTile :value="kpis.actors" :label="t('gov.audit.kpiActors')" :loading="loading && items.length === 0" />
      <KpiTile :value="kpis.persona" :label="t('gov.audit.kpiPersona')" :chip="kpis.persona === 0 ? t('gov.audit.kpiPersonaNorm') : undefined" chip-tone="ok" :tone="kpis.persona ? 'danger' : undefined" :loading="loading && items.length === 0" />
      <KpiTile :value="kpis.denied" :label="t('gov.audit.kpiDenied')" :loading="loading && items.length === 0" />
    </KpiRow>

    <AppCard>
      <Skeleton v-if="loading && items.length === 0" kind="table" :lines="8" />
      <EmptyState v-else-if="visible.length === 0" :title="t('gov.audit.empty')" icon="pi pi-history" />
      <div v-else class="table-wrap">
        <table class="dense-table" data-testid="audit-table">
          <thead><tr><th>{{ t('gov.audit.colWhen') }}</th><th>{{ t('gov.audit.colUser') }}</th><th>{{ t('gov.audit.colRole') }}</th><th>{{ t('gov.audit.colAction') }}</th><th>{{ t('gov.audit.colObject') }}</th><th>{{ t('gov.audit.colResult') }}</th><th class="num">{{ t('gov.audit.colDurationShort') }}</th></tr></thead>
          <tbody>
            <tr v-for="e in pageRows" :key="e.id" class="clickable" :class="{ selected: selected?.id === e.id && panelOpen }" @click="open(e)">
              <td class="nowrap muted">{{ dateTime(e.at) }}</td>
              <td class="strong">{{ e.actor }}</td>
              <td class="muted">{{ roleLabel(e.role) }}</td>
              <td class="mono path">{{ e.method }} {{ e.path.replace(/^\/api\/v1/, '') }}</td>
              <td class="mono muted object">{{ objectOf(e) || '—' }}</td>
              <td><StatusTag :value="String(e.status)" :tone="tone(e.status)" /></td>
              <td class="num muted">{{ e.durationMs }}</td>
            </tr>
          </tbody>
        </table>
      </div>
      <div v-if="visible.length" class="pager">
        <span class="caption">{{ t('gov.audit.pageOf', { page: pageIndex + 1, pages }) }}</span>
        <span class="spacer" />
        <Button :label="t('gov.audit.prev')" size="small" severity="secondary" :disabled="pageIndex === 0" @click="pageIndex -= 1" />
        <Button :label="t('gov.audit.next')" size="small" severity="secondary" :disabled="pageIndex + 1 >= pages && items.length >= total" :loading="loading" @click="next" />
      </div>
    </AppCard>

    <SidePanel v-model:visible="panelOpen" :title="selected ? `${selected.method} ${selected.status}` : ''" :subtitle="selected ? dateTime(selected.at) : ''">
      <dl v-if="selected" class="facts">
        <dt>{{ t('gov.audit.colUser') }}</dt><dd>{{ selected.actor }} · {{ roleLabel(selected.role) }}</dd>
        <dt>{{ t('gov.audit.colAction') }}</dt><dd class="mono break">{{ selected.method }} {{ selected.path }}</dd>
        <dt>{{ t('gov.audit.colObject') }}</dt><dd class="mono break">{{ selected.query || '—' }}</dd>
        <dt>{{ t('gov.audit.colResult') }}</dt><dd><StatusTag :value="String(selected.status)" :tone="tone(selected.status)" /></dd>
        <dt>{{ t('gov.audit.colDuration') }}</dt><dd class="tabular">{{ selected.durationMs }}</dd>
        <dt>{{ t('gov.audit.colRegion') }}</dt><dd class="muted">{{ t('gov.orgReferrals.notInOpenData') }}</dd>
        <dt>{{ t('gov.audit.colTrace') }}</dt><dd class="mono break">{{ selected.traceId }}</dd>
      </dl>
      <p class="caption" style="margin-top: 12px">{{ t('gov.audit.noPersona') }}</p>
      <RouterLink class="link-arrow small" :to="{ name: 'decisions' }" style="margin-top: 12px">{{ t('gov.audit.openDecisions') }}</RouterLink>
    </SidePanel>
  </PageShell>
</template>

<style scoped>
.nowrap { white-space: nowrap; }
.strong { font-weight: 500; }
.path { max-width: 300px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.object { max-width: 220px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.break { word-break: break-all; }
.pager { display: flex; align-items: center; gap: 8px; margin-top: 12px; }
.spacer { flex: 1; }
</style>
