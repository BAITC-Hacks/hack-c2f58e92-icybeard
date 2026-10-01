<script setup lang="ts">
import Button from 'primevue/button'
import IconField from 'primevue/iconfield'
import InputIcon from 'primevue/inputicon'
import InputText from 'primevue/inputtext'
import Select from 'primevue/select'
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { journal } from '@/api/endpoints'
import type { Decision } from '@/api/types'
import AsyncState from '@/components/states/AsyncState.vue'
import AppCard from '@/components/ui/AppCard.vue'
import KpiRow from '@/components/ui/KpiRow.vue'
import KpiTile from '@/components/ui/KpiTile.vue'
import PageShell from '@/components/ui/PageShell.vue'
import SidePanel from '@/components/ui/SidePanel.vue'
import { useLocaleFormat } from '@/composables/useLocaleFormat'
import { downloadCsv } from '@/lib/csv'
import { describeChoice, describeSubject, organizationOf, roleLabel, SUBJECT_ANOMALY, SUBJECT_REFERRAL, SUBJECT_SCRIBE, subjectLabel, type DecisionNames } from '@/lib/decision'
import { shortOrgName } from '@/lib/format'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'

/** Журнал решений (W-Decisions): все решения врача (новые направления из ассистента, пациенты в очереди, сигналы
 * по данным) — что рекомендовала система, что выбрал человек и почему; для самопроверки, разбора и отчётности.
 * Фильтры — выпадающие списки (период, тип, роль) и поиск, три спокойных KPI, таблица с обрезкой длинного текста
 * (полный — при наведении и в панели по клику), экспорт CSV на русском с понятными колонками. */
const PERIODS = [7, 30, 90] as const
const { t } = useI18n()
const { dateTime } = useLocaleFormat()
const auth = useAuthStore()
const refdata = useRefdataStore()
const items = ref<Decision[]>([])
const total = ref(0)
const error = ref<unknown>(null)
const loading = ref(false)
/** 'all' — без фильтра (так в выпадающем списке сразу видно «Все решения»). */
const subject = ref<string>('all')
const role = ref<string>('all')
const period = ref<number | 0>(30)
const search = ref('')
const selected = ref<Decision | null>(null)
const panelOpen = ref(false)

const names: DecisionNames = {
  region: (kato) => refdata.regionName(kato),
  profile: (code) => refdata.profileName(code),
  organization: (moCode) => refdata.organizationName(moCode),
}
const shortChoice = (value: unknown) => {
  const code = organizationOf(value)
  return code ? shortOrgName(refdata.organizationName(code)) : describeChoice(value, names)
}
type Outcome = 'matched' | 'differ' | 'none'
/** Итог: рекомендация и выбор совпали, выбрано иначе или рекомендации не было. */
function outcome(d: Decision): Outcome {
  if (d.recommended === null || d.recommended === undefined) return 'none'
  return JSON.stringify(d.recommended) === JSON.stringify(d.chosen) ? 'matched' : 'differ'
}
const subjects = computed(() => [...new Set([SUBJECT_REFERRAL, SUBJECT_ANOMALY, ...items.value.map((d) => d.subject)])])
const roles = computed(() => [...new Set(items.value.map((d) => d.role))])
const inPeriod = computed(() => {
  const since = period.value ? Date.now() - period.value * 86_400_000 : 0
  return items.value.filter((d) => !since || new Date(d.recordedAt).getTime() >= since)
})
/** Текст строки для поиска: объект, выбор, рекомендация, причина, автор. */
const haystack = (d: Decision) =>
  [describeSubject(d.subject, d.subjectId, names), d.subjectId, describeChoice(d.chosen, names), describeChoice(d.recommended, names), d.reason ?? '', d.actor].join(' ').toLowerCase()
const visible = computed(() => {
  const q = search.value.trim().toLowerCase()
  return inPeriod.value.filter((d) => (subject.value === 'all' || d.subject === subject.value) && (role.value === 'all' || d.role === role.value) && (!q || haystack(d).includes(q)))
})
const periodOptions = computed(() => [...PERIODS.map((p) => ({ label: t('doctor.decisions.periodDays', { days: p }), value: p })), { label: t('doctor.decisions.periodAll'), value: 0 }])
const subjectOptions = computed(() => [
  { label: `${t('doctor.decisions.subjectAll')} · ${inPeriod.value.length}`, value: 'all' },
  ...subjects.value.map((s) => ({ label: `${subjectLabel(s)} · ${count((d) => d.subject === s)}`, value: s })),
])
const roleOptions = computed(() => [{ label: t('doctor.decisions.roleAll'), value: 'all' }, ...roles.value.map((r) => ({ label: roleLabel(r), value: r }))])
const count = (pred: (d: Decision) => boolean) => inPeriod.value.filter(pred).length
const matched = computed(() => count((d) => outcome(d) === 'matched'))
const differ = computed(() => count((d) => outcome(d) === 'differ'))

function resetFilters() {
  subject.value = 'all'
  role.value = 'all'
  period.value = 0
  search.value = ''
}

const capitalize = (s: string) => (s ? s[0]!.toUpperCase() + s.slice(1) : s)

function open(d: Decision) {
  selected.value = d
  panelOpen.value = true
}

/** CSV для Excel: русские заголовки, даты как на экране, понятные значения вместо кодов. */
function exportCsv() {
  const c = (key: string) => t(`doctor.decisions.csv.${key}`)
  const cols = ['when', 'type', 'object', 'recommended', 'chosen', 'matched', 'reason', 'actor', 'role', 'id'].map(c)
  const rows = visible.value.map((d) => {
    const o = outcome(d)
    return {
      [c('when')]: dateTime(d.recordedAt), [c('type')]: subjectLabel(d.subject), [c('object')]: describeSubject(d.subject, d.subjectId, names),
      [c('recommended')]: o === 'none' ? '' : describeChoice(d.recommended, names), [c('chosen')]: describeChoice(d.chosen, names),
      [c('matched')]: o === 'none' ? '' : o === 'matched' ? t('common.yes') : t('common.no'), [c('reason')]: d.reason ?? '',
      [c('actor')]: d.actor, [c('role')]: roleLabel(d.role), [c('id')]: d.decisionId,
    }
  })
  downloadCsv(`${t('doctor.decisions.csv.file')}-${new Date().toISOString().slice(0, 10)}.csv`, rows, cols)
}

async function load() {
  loading.value = true
  error.value = null
  try {
    const page = await journal.decisions({ actor: auth.can('decisions.all') ? undefined : 'me', size: 200 })
    // служебные события записи приёма (запрос согласия, сессия, памятка) — не решения врача: их видно в скрайбе и у пациента
    const hidden = page.items.filter((d) => d.subject === SUBJECT_SCRIBE).length
    page.items = page.items.filter((d) => d.subject !== SUBJECT_SCRIBE)
    page.total = Math.max(0, page.total - hidden)
    const codes = page.items.flatMap((d) => [organizationOf(d.recommended), organizationOf(d.chosen)]).filter((c): c is string => c !== null)
    await refdata.resolveOrganizations(codes)
    items.value = page.items
    total.value = page.total
  } catch (e) {
    error.value = e
  } finally {
    loading.value = false
  }
}

onMounted(async () => {
  await refdata.load()
  await load()
})
</script>

<template>
  <PageShell :title="t('doctor.decisions.title')">
    <template #subtitle>{{ auth.can('decisions.all') ? t('doctor.decisions.leadRegulator') : t('doctor.decisions.leadSelf') }}</template>
    <template #actions>
      <Button :label="t('doctor.decisions.refresh')" icon="pi pi-refresh" size="small" severity="secondary" text :loading="loading" @click="load" />
      <Button :label="t('shell.exportCsv')" icon="pi pi-download" size="small" severity="secondary" :disabled="visible.length === 0" data-testid="decisions-export" @click="exportCsv" />
    </template>
    <KpiRow>
      <KpiTile :value="inPeriod.length" :label="period ? t('doctor.decisions.kpiPeriod', { days: period }) : t('doctor.decisions.kpiAll')" :loading="loading && items.length === 0" />
      <KpiTile :value="matched" :label="t('doctor.decisions.kpiMatched')" :loading="loading && items.length === 0" />
      <KpiTile :value="differ" :label="t('doctor.decisions.kpiDiffer')" :loading="loading && items.length === 0" />
    </KpiRow>

    <AppCard>
      <div class="toolbar list-toolbar">
        <span class="caption">{{ t('doctor.worklist.shown', { shown: visible.length, total: inPeriod.length }) }}</span>
        <span class="spacer" />
        <Select v-model="period" :options="periodOptions" option-label="label" option-value="value" class="f-select" :aria-label="t('doctor.decisions.period')" data-testid="decisions-period" />
        <Select v-model="subject" :options="subjectOptions" option-label="label" option-value="value" class="f-select" :aria-label="t('doctor.decisions.subject')" data-testid="decisions-subject" />
        <Select v-if="roles.length > 1" v-model="role" :options="roleOptions" option-label="label" option-value="value" class="f-select" :aria-label="t('doctor.decisions.role')" />
        <IconField class="search-field">
          <InputIcon class="pi pi-search" />
          <InputText v-model="search" :placeholder="t('doctor.decisions.search')" :aria-label="t('doctor.decisions.search')" data-testid="decisions-search" />
        </IconField>
      </div>
      <AsyncState :loading="loading" :error="error" :empty="visible.length === 0" :filtered="items.length > 0 && (subject !== 'all' || role !== 'all' || !!period || !!search)" :lines="6"
        :empty-title="t('doctor.decisions.empty')" :empty-text="t('doctor.decisions.emptyText')" empty-icon="pi pi-book" @retry="load" @reset="resetFilters">
      <div class="table-wrap">
        <table class="dense-table decisions" data-testid="decisions-table">
          <colgroup><col class="c-when" /><col class="c-object" /><col class="c-org" /><col class="c-org" /><col class="c-outcome" /><col class="c-reason" /></colgroup>
          <thead>
            <tr><th>{{ t('doctor.decisions.when') }}</th><th>{{ t('doctor.decisions.object') }}</th><th>{{ t('doctor.decisions.recommended') }}</th><th>{{ t('doctor.decisions.chosen') }}</th><th>{{ t('doctor.decisions.colOutcome') }}</th><th>{{ t('doctor.decisions.reason') }}</th></tr>
          </thead>
          <tbody>
            <tr v-for="d in visible" :key="d.decisionId" class="clickable" :class="{ selected: selected?.decisionId === d.decisionId && panelOpen }" @click="open(d)">
              <td class="when tabular">{{ dateTime(d.recordedAt) }}</td>
              <td class="cut"><span class="strong one" :title="describeSubject(d.subject, d.subjectId, names)">{{ describeSubject(d.subject, d.subjectId, names) }}</span><span class="sub one">{{ subjectLabel(d.subject) }}<template v-if="auth.can('decisions.all')"> · {{ d.actor }}</template></span></td>
              <td class="cut"><span class="one muted" :title="outcome(d) === 'none' ? '' : describeChoice(d.recommended, names)">{{ outcome(d) === 'none' ? '—' : shortChoice(d.recommended) }}</span></td>
              <td class="cut"><span class="one" :title="describeChoice(d.chosen, names)">{{ outcome(d) === 'matched' ? t('doctor.decisions.keptAsRecommended') : shortChoice(d.chosen) }}</span></td>
              <td><span class="outcome" :class="outcome(d)">{{ t('doctor.decisions.outcome.' + outcome(d)) }}</span></td>
              <td class="cut"><span class="two" :title="d.reason ?? ''">{{ d.reason || '—' }}</span></td>
            </tr>
          </tbody>
        </table>
      </div>
      </AsyncState>
    </AppCard>

    <SidePanel v-model:visible="panelOpen" :title="selected ? capitalize(subjectLabel(selected.subject)) : ''" :subtitle="selected ? dateTime(selected.recordedAt) : ''">
      <div v-if="selected" class="rows d-rows">
        <div class="row"><span class="row-main muted">{{ t('doctor.decisions.object') }}</span><span class="row-value wrap">{{ describeSubject(selected.subject, selected.subjectId, names) }}</span></div>
        <div class="row"><span class="row-main muted">{{ t('doctor.decisions.recommended') }}</span><span class="row-value wrap" :title="describeChoice(selected.recommended, names)">{{ outcome(selected) === 'none' ? '—' : shortChoice(selected.recommended) }}</span></div>
        <div class="row"><span class="row-main muted">{{ t('doctor.decisions.chosen') }}</span><span class="row-value wrap strong" :title="describeChoice(selected.chosen, names)">{{ shortChoice(selected.chosen) }}</span></div>
        <div class="row"><span class="row-main muted">{{ t('doctor.decisions.colOutcome') }}</span><span class="row-value">{{ t('doctor.decisions.outcome.' + outcome(selected)) }}</span></div>
        <div v-if="auth.can('decisions.all')" class="row"><span class="row-main muted">{{ t('doctor.decisions.who') }}</span><span class="row-value">{{ selected.actor }} · {{ roleLabel(selected.role) }}</span></div>
      </div>
      <div v-if="selected" class="d-reason">
        <span class="d-label">{{ t('doctor.decisions.reason') }}</span>
        <p class="long">{{ selected.reason || '—' }}</p>
      </div>
    </SidePanel>
  </PageShell>
</template>

<style scoped>
.list-toolbar { margin-bottom: var(--gap-cabinet); row-gap: 8px; }
.f-select { min-width: 240px; }
.search-field { flex: 0 1 380px; min-width: 300px; }
.search-field :deep(.p-inputtext) { width: 100%; }
.decisions { table-layout: fixed; min-width: 860px; }
.c-when { width: 150px; }
.c-object { width: 24%; }
.c-org { width: 18%; }
.c-outcome { width: 140px; }
.c-reason { width: auto; }
.when { color: var(--text-secondary); white-space: nowrap; font-size: var(--fs-base-sm); }
.cut { overflow: hidden; }
.cut > span { display: block; }
.one { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.two { display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; overflow-wrap: anywhere; line-height: 1.4; }
.sub { font-size: var(--fs-sm); color: var(--text-muted); margin-top: 2px; }
.strong { font-weight: var(--fw-semibold); }
.outcome { font-size: var(--fs-base-sm); color: var(--text-secondary); white-space: nowrap; }
.outcome.differ { color: var(--text); font-weight: var(--fw-semibold); }
.d-rows .row-value.wrap { white-space: normal; text-align: right; max-width: 65%; }
.d-reason { margin-top: 16px; padding: 12px 14px; border-radius: var(--radius-md); background: var(--surface-muted); }
.d-label { display: block; font-size: var(--fs-xs); font-weight: var(--fw-bold); color: var(--text-muted); margin-bottom: 4px; }
.long { margin: 0; white-space: pre-wrap; overflow-wrap: anywhere; line-height: 1.5; }
@media (max-width: 900px) { .f-select, .search-field { flex: 1 1 100%; } }
</style>
