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
import AsyncState from '@/components/states/AsyncState.vue'
import AppCard from '@/components/ui/AppCard.vue'
import KpiRow from '@/components/ui/KpiRow.vue'
import KpiTile from '@/components/ui/KpiTile.vue'
import PageShell from '@/components/ui/PageShell.vue'
import SidePanel from '@/components/ui/SidePanel.vue'
import StatusTag from '@/components/ui/StatusTag.vue'
import { useLocaleFormat } from '@/composables/useLocaleFormat'
import { downloadCsv } from '@/lib/csv'
import { roleLabel } from '@/lib/decision'
import { shortOrgName } from '@/lib/format'
import { useRefdataStore } from '@/stores/refdata'

/** Журнал аудита (W-Audit): кто и что делал в системе. Действие показано словами («Открыл список врачей»), а не
 * адресом API; фоновые запросы (колокольчик, статус сервисов) по умолчанию скрыты. Над таблицей — роль, период,
 * тип действия, поиск по логину, обновить и экспорт. Технические подробности (метод, путь, время ответа, trace) —
 * в боковой панели. Главврач видит только сотрудников своей организации (scope own на сервере). */
const PAGE_SIZE = 200
const ROWS_PER_PAGE = 20
const PERIODS = [1, 7, 30] as const
/** Пути, где встречаются персональные поля: обращений к ним по правилу продукта быть не должно. */
const PERSONA_PATTERN = /iin|cardnumber|persona/i
/** Запросы, которые приложение делает само (опрос колокольчика, статус сервисов), — не действия человека. */
const BACKGROUND = /\/(notifications\/bell|public\/service-status|scribe\/health)|\/route\/me\/notifications$/
/** Путь → что сделал человек (ключ gov.audit.act.*); первое совпадение. */
const ACTIONS: [RegExp, string, string?][] = [
  [/\/notifications/, 'notifications'], [/service-status|scribe\/health/, 'status'],
  [/\/admin\/doctors\/[^/]+\/verification/, 'verifyDoctor'], [/\/admin\/doctors/, 'doctors'],
  [/\/admin\/users\/[^/]+/, 'user', 'userChange'], [/\/admin\/users/, 'users', 'invite'], [/\/admin\/invitations/, 'invitations', 'invite'],
  [/\/admin\/roles|\/admin\/matrix/, 'roles', 'rolesChange'], [/\/admin/, 'admin', 'adminChange'],
  [/\/journal\/audit/, 'audit'], [/\/journal\/worklist/, 'worklist'], [/\/journal\/referrals\/incoming/, 'incoming', 'incomingChange'],
  [/\/journal\/decisions/, 'decisions', 'decisionWrite'], [/\/route\/me/, 'myRoute', 'myRouteChange'], [/\/route\//, 'patientRoute', 'routeChange'],
  [/\/scribe-consents|\/scribe/, 'scribe', 'scribeChange'], [/\/queue|\/forecast|\/predict/, 'queue'], [/\/anomal/, 'signals', 'signalChange'],
  [/\/medicines|\/rx/, 'medicines'], [/\/insight|\/ask/, 'insight'], [/\/refdata|\/organizations|\/regions/, 'refdata'], [/\/me\b|\/account/, 'account', 'accountChange'],
]
const { t, te } = useI18n()
const refdata = useRefdataStore()
const { dateTime } = useLocaleFormat()

const items = ref<AuditEntry[]>([])
const total = ref(0)
const error = ref<unknown>(null)
const loading = ref(false)
const actor = ref('')
const role = ref<string>('all')
/** Тип действия: по умолчанию — действия людей без фоновых запросов. */
const kind = ref<'people' | 'changes' | 'views' | 'denied' | 'all'>('people')
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
const roleOptions = computed(() => [{ value: 'all', label: t('gov.audit.roleAll') }, ...[...new Set(items.value.map((e) => e.role))].map((r) => ({ value: r, label: roleLabel(r) }))])
const KINDS = ['people', 'changes', 'views', 'denied', 'all'] as const
const kindOptions = computed(() => KINDS.map((k) => ({ value: k, label: t('gov.audit.kind.' + k) })))
const periodOptions = computed(() => PERIODS.map((p) => ({ value: p, label: t('gov.audit.periodOption', { days: p }) })))
const isBackground = (e: AuditEntry) => BACKGROUND.test(e.path)
const isChange = (e: AuditEntry) => e.method !== 'GET' && e.method !== 'HEAD'
function matchesKind(e: AuditEntry): boolean {
  switch (kind.value) {
    case 'people': return !isBackground(e)
    case 'changes': return isChange(e)
    case 'views': return !isChange(e) && !isBackground(e)
    case 'denied': return e.status === 401 || e.status === 403
    default: return true
  }
}
const visible = computed(() => inPeriod.value.filter((e) => (role.value === 'all' || e.role === role.value) && matchesKind(e)))
/** «Открыл список врачей» / «Изменил пользователя»: по пути и методу; неизвестное — «Просмотр» / «Изменение данных». */
function actionOf(e: AuditEntry): string {
  const found = ACTIONS.find(([re]) => re.test(e.path))
  if (!found) return t(isChange(e) ? 'gov.audit.act.otherChange' : 'gov.audit.act.other')
  return t('gov.audit.act.' + (isChange(e) && found[2] ? found[2] : found[1]))
}
const resultOf = (status: number) => t(status < 400 ? 'gov.audit.result.ok' : status === 401 || status === 403 ? 'gov.audit.result.denied' : status < 500 ? 'gov.audit.result.rejected' : 'gov.audit.result.error')
const pages = computed(() => Math.max(1, Math.ceil(visible.value.length / ROWS_PER_PAGE)))
const pageRows = computed(() => visible.value.slice(pageIndex.value * ROWS_PER_PAGE, (pageIndex.value + 1) * ROWS_PER_PAGE))
const kpis = computed(() => ({
  requests: inPeriod.value.filter((e) => !isBackground(e)).length,
  actors: new Set(inPeriod.value.map((e) => e.actor)).size,
  persona: inPeriod.value.filter((e) => PERSONA_PATTERN.test(e.path) || PERSONA_PATTERN.test(e.query ?? '')).length,
  denied: inPeriod.value.filter((e) => e.status === 401 || e.status === 403).length,
}))
/** О ком было действие: номер пациента из пути, если он есть (параметры запроса — в технических подробностях). */
const objectOf = (e: AuditEntry) => (e.path + (e.query ?? '')).match(/SYN-[\w-]+/)?.[0] ?? ''

/** Подробности записи словами: о каком пациенте, какой организации, какие фильтры были выбраны. Неизвестные
 * технические параметры не показываются — они есть в «Технических подробностях». */
function details(e: AuditEntry): { label: string; value: string }[] {
  const out: { label: string; value: string }[] = []
  const patient = e.path.match(/SYN-[\w-]+/)?.[0]
  if (patient) out.push({ label: t('gov.audit.param.patient'), value: patient })
  const params = new URLSearchParams((e.query ?? '').replace(/^\?/, ''))
  for (const [key, raw] of params) {
    if (!te('gov.audit.param.' + key) || raw === '' || key === 'page' || key === 'size') continue
    let value = raw
    if (key === 'moCode') value = `${shortOrgName(refdata.organizationName(raw))} (${raw})`
    else if (key === 'regionKato' || key === 'region') value = refdata.regionName(raw)
    else if (key === 'profileCode' || key === 'profile') value = refdata.profileName(raw)
    else if (raw === 'true') value = t('common.yes')
    else if (raw === 'false') value = t('common.no')
    else if (key === 'verification' && te('admin.doctors.verification.' + raw)) value = t('admin.doctors.verification.' + raw)
    else if (key === 'status' && te('admin.users.status.' + raw)) value = t('admin.users.status.' + raw)
    else if (key === 'role') value = roleLabel(raw)
    out.push({ label: t('gov.audit.param.' + key), value })
  }
  return out
}
const kindText = (e: AuditEntry) => t(isChange(e) ? 'gov.audit.typeChange' : isBackground(e) ? 'gov.audit.typeBackground' : 'gov.audit.typeView')
const resultText = (status: number) => t(status < 400 ? 'gov.audit.resultText.ok' : status === 401 || status === 403 ? 'gov.audit.resultText.denied' : status < 500 ? 'gov.audit.resultText.rejected' : 'gov.audit.resultText.error')

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

function resetFilters() {
  role.value = 'all'
  kind.value = 'people'
  period.value = PERIODS[PERIODS.length - 1]!
}

function open(entry: AuditEntry) {
  selected.value = entry
  panelOpen.value = true
}

function exportCsv() {
  // заголовки по-русски (или по-казахски), дата — как на экране; технические поля — в конце для разбора инцидентов
  const c = (k: string) => t('gov.audit.csv.' + k)
  downloadCsv(`audit-${new Date().toISOString().slice(0, 10)}.csv`, visible.value.map((e) => ({
    [c('when')]: dateTime(e.at), [c('user')]: e.actor, [c('role')]: roleLabel(e.role), [c('action')]: actionOf(e), [c('result')]: resultOf(e.status),
    [c('request')]: `${e.method} ${e.path}${e.query ?? ''}`, [c('status')]: e.status, [c('duration')]: e.durationMs, [c('trace')]: e.traceId,
  })))
}

watch([role, kind, period], () => (pageIndex.value = 0))
onMounted(() => load())
</script>

<template>
  <PageShell :title="t('gov.audit.title')">
    <template #subtitle>{{ t('gov.audit.subtitle') }}</template>
    <template #actions>
      <Button :label="t('gov.audit.refresh')" icon="pi pi-refresh" size="small" severity="secondary" :loading="loading" @click="load()" />
      <Button :label="t('shell.exportCsv')" icon="pi pi-download" size="small" severity="secondary" :disabled="visible.length === 0" @click="exportCsv" />
    </template>
    <KpiRow data-testid="audit-kpis">
      <KpiTile label-first :value="kpis.requests" :label="t('gov.audit.kpiRequestsLabel', { days: period })" :hint="t('gov.audit.kpiRequestsHint')" :loading="loading && items.length === 0" />
      <KpiTile label-first :value="kpis.actors" :label="t('gov.audit.kpiActorsLabel')" :hint="t('gov.audit.kpiActorsHint')" :loading="loading && items.length === 0" />
      <KpiTile label-first :value="kpis.persona" :label="t('gov.audit.kpiPersonaLabel')" :hint="t('gov.audit.kpiPersonaHint')" :chip="kpis.persona === 0 ? t('gov.audit.kpiPersonaNorm') : undefined" chip-tone="ok" :tone="kpis.persona ? 'danger' : undefined" :loading="loading && items.length === 0" />
      <KpiTile label-first :value="kpis.denied" :label="t('gov.audit.kpiDeniedLabel')" :hint="t('gov.audit.kpiDeniedHint')" :tone="kpis.denied ? 'danger' : undefined" :loading="loading && items.length === 0" />
    </KpiRow>

    <AppCard>
      <div class="toolbar list-toolbar">
        <span class="list-count">{{ t('gov.audit.found', { n: visible.length }) }}</span>
        <span class="spacer" />
        <Select v-model="period" :options="periodOptions" option-label="label" option-value="value" class="f-select" :aria-label="t('gov.audit.period')" data-testid="audit-period" />
        <Select v-model="kind" :options="kindOptions" option-label="label" option-value="value" class="f-select" :aria-label="t('gov.audit.colAction')" data-testid="audit-kind" />
        <Select v-model="role" :options="roleOptions" option-label="label" option-value="value" class="f-select" :placeholder="t('gov.audit.roleAll')" :aria-label="t('gov.audit.colRole')" />
        <IconField class="search-field">
          <InputIcon class="pi pi-search" />
          <InputText v-model="actor" :placeholder="t('gov.audit.actorPlaceholder')" :aria-label="t('gov.audit.actorPlaceholder')" data-testid="audit-actor" @keyup.enter="load()" />
        </IconField>
      </div>
      <AsyncState :loading="loading" :error="error" :empty="visible.length === 0" :filtered="items.length > 0 && !!(role !== 'all' || kind !== 'people' || period !== PERIODS[PERIODS.length - 1])" :lines="8"
        :empty-title="t('gov.audit.empty')" empty-icon="pi pi-history" @retry="load()" @reset="resetFilters">
      <div class="table-wrap">
        <table class="dense-table" data-testid="audit-table">
          <thead><tr><th>{{ t('gov.audit.colWhen') }}</th><th>{{ t('gov.audit.colUser') }}</th><th>{{ t('gov.audit.colAction') }}</th><th>{{ t('gov.audit.colResult') }}</th></tr></thead>
          <tbody>
            <tr v-for="e in pageRows" :key="e.id" class="clickable" :class="{ selected: selected?.id === e.id && panelOpen }" @click="open(e)">
              <td class="nowrap muted">{{ dateTime(e.at) }}</td>
              <td><span class="strong">{{ e.actor }}</span><div class="caption">{{ roleLabel(e.role) }}</div></td>
              <td>{{ actionOf(e) }}<div v-if="objectOf(e)" class="caption mono object">{{ objectOf(e) }}</div></td>
              <td><StatusTag :value="resultOf(e.status)" :tone="tone(e.status)" /></td>
            </tr>
          </tbody>
        </table>
      </div>
      </AsyncState>
      <div v-if="visible.length" class="pager">
        <span class="caption">{{ t('gov.audit.pageOf', { page: pageIndex + 1, pages }) }} · {{ t('gov.audit.total') }}: {{ total }}</span>
        <span class="spacer" />
        <Button :label="t('gov.audit.prev')" size="small" severity="secondary" :disabled="pageIndex === 0" @click="pageIndex -= 1" />
        <Button :label="t('gov.audit.next')" size="small" severity="secondary" :disabled="pageIndex + 1 >= pages && items.length >= total" :loading="loading" @click="next" />
      </div>
    </AppCard>

    <SidePanel v-model:visible="panelOpen" :title="selected ? actionOf(selected) : ''" :subtitle="selected ? dateTime(selected.at) : ''">
      <dl v-if="selected" class="facts rows-facts">
        <dt>{{ t('gov.audit.colUser') }}</dt><dd>{{ selected.actor }} · {{ roleLabel(selected.role) }}</dd>
        <dt>{{ t('gov.audit.colWhen') }}</dt><dd>{{ dateTime(selected.at) }}</dd>
        <dt>{{ t('gov.audit.colAction') }}</dt><dd>{{ actionOf(selected) }}</dd>
        <dt>{{ t('gov.audit.type') }}</dt><dd>{{ kindText(selected) }}</dd>
        <dt>{{ t('gov.audit.colResult') }}</dt><dd><StatusTag :value="resultOf(selected.status)" :tone="tone(selected.status)" /><div class="caption result-text">{{ resultText(selected.status) }}</div></dd>
        <template v-for="d in details(selected)" :key="d.label"><dt>{{ d.label }}</dt><dd>{{ d.value }}</dd></template>
      </dl>
      <p class="caption" style="margin-top: 12px">{{ t('gov.audit.noPersona') }}</p>
      <div v-if="selected" class="tech">
        <div class="tech-title">{{ t('gov.audit.techTitle') }}</div>
        <p class="caption">{{ t('gov.audit.techHint') }}</p>
        <dl class="facts">
          <dt>{{ t('gov.audit.techRequest') }}</dt><dd class="mono break">{{ selected.method }} {{ selected.path }}{{ selected.query ?? '' }}</dd>
          <dt>{{ t('gov.audit.techStatus') }}</dt><dd class="tabular">{{ selected.status }}</dd>
          <dt>{{ t('gov.audit.techDuration') }}</dt><dd class="tabular">{{ t('gov.audit.ms', { n: selected.durationMs }) }}</dd>
          <dt>{{ t('gov.audit.colTrace') }}</dt><dd class="mono break">{{ selected.traceId }}</dd>
        </dl>
      </div>
    </SidePanel>
  </PageShell>
</template>

<style scoped>
.nowrap { white-space: nowrap; }
.strong { font-weight: var(--fw-bold); }
.list-toolbar { margin-bottom: var(--gap-cabinet, 16px); row-gap: 8px; }
.f-select { min-width: 190px; }
.search-field { flex: 0 1 380px; min-width: 260px; }
.search-field :deep(.p-inputtext) { width: 100%; }
.object { max-width: 420px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.break { word-break: break-all; }
.pager { display: flex; align-items: center; gap: 8px; margin-top: 12px; }
.spacer { flex: 1; }
.result-text { margin-top: 4px; }
.list-count { font-size: var(--fs-base); color: var(--text-secondary); }
.rows-facts { gap: 0; }
.rows-facts dt, .rows-facts dd { padding: 11px 0; border-bottom: 1px solid var(--border-soft); }
.rows-facts dt { padding-right: 16px; }
.rows-facts dt:last-of-type, .rows-facts dd:last-of-type { border-bottom: 0; }
.tech .facts dt, .tech .facts dd { padding: 6px 0; }
.tech { margin-top: 20px; padding: 14px 16px; border-radius: 12px; background: var(--surface-muted); }
.tech-title { font-weight: var(--fw-bold); margin-bottom: 2px; }
.tech .caption { margin: 0 0 8px; }
@media (max-width: 900px) { .f-select, .search-field { flex: 1 1 100%; } }
</style>
