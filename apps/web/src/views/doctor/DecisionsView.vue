<script setup lang="ts">
import Button from 'primevue/button'
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
import StatusTag from '@/components/ui/StatusTag.vue'
import { useLocaleFormat } from '@/composables/useLocaleFormat'
import { downloadCsv } from '@/lib/csv'
import { describeChoice, describeSubject, organizationOf, roleLabel, SUBJECT_ANOMALY, SUBJECT_REFERRAL, subjectLabel, type DecisionNames } from '@/lib/decision'
import { shortOrgName } from '@/lib/format'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'

/** Журнал решений (W-Decisions): подпись «рекомендация системы и выбор врача · актор · всего N», период пилюлями,
 * экспорт CSV, чипы по предмету, три KPI (решений, совпало, выбрано иначе), таблица «Когда · Объект · Рекомендовано ·
 * Выбрано · Итог · Причина»; клик по строке — панель с полными данными и ключом записи. */
const PERIODS = [7, 30, 90] as const
const { t } = useI18n()
const { dateTime } = useLocaleFormat()
const auth = useAuthStore()
const refdata = useRefdataStore()
const items = ref<Decision[]>([])
const total = ref(0)
const error = ref<unknown>(null)
const loading = ref(false)
const subject = ref<string | null>(null)
const role = ref<string | null>(null)
const period = ref<number | null>(30)
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
const OUTCOME_TONES: Record<Outcome, 'ok' | 'warn' | 'neutral'> = { matched: 'ok', differ: 'warn', none: 'neutral' }
const subjects = computed(() => [...new Set([SUBJECT_REFERRAL, SUBJECT_ANOMALY, ...items.value.map((d) => d.subject)])])
const roles = computed(() => [...new Set(items.value.map((d) => d.role))])
const inPeriod = computed(() => {
  const since = period.value ? Date.now() - period.value * 86_400_000 : 0
  return items.value.filter((d) => !since || new Date(d.recordedAt).getTime() >= since)
})
const visible = computed(() => inPeriod.value.filter((d) => (!subject.value || d.subject === subject.value) && (!role.value || d.role === role.value)))
const count = (pred: (d: Decision) => boolean) => inPeriod.value.filter(pred).length
const matched = computed(() => count((d) => outcome(d) === 'matched'))
const differ = computed(() => count((d) => outcome(d) === 'differ'))

function resetFilters() {
  subject.value = null
  role.value = null
  period.value = null
}

function open(d: Decision) {
  selected.value = d
  panelOpen.value = true
}

function exportCsv() {
  downloadCsv(
    'decisions.csv',
    visible.value.map((d) => ({
      recordedAt: d.recordedAt, actor: d.actor, role: d.role, subject: d.subject, subjectId: d.subjectId,
      recommended: describeChoice(d.recommended, names), chosen: describeChoice(d.chosen, names), reason: d.reason ?? '', decisionId: d.decisionId,
    })),
  )
}

async function load() {
  loading.value = true
  error.value = null
  try {
    const page = await journal.decisions({ actor: auth.can('decisions.all') ? undefined : 'me', size: 200 })
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
    <template #subtitle>{{ auth.can('decisions.all') ? t('doctor.decisions.leadRegulator') : t('doctor.decisions.subtitle') }} · {{ auth.actor }} · {{ t('doctor.decisions.total').toLowerCase() }} {{ total }}</template>
    <template #actions>
      <Button :label="t('doctor.decisions.refresh')" icon="pi pi-refresh" size="small" severity="secondary" text :loading="loading" @click="load" />
      <Button :label="t('shell.exportCsv')" size="small" severity="secondary" :disabled="visible.length === 0" data-testid="decisions-export" @click="exportCsv" />
    </template>
    <div class="chips">
      <button v-for="p in PERIODS" :key="p" type="button" class="chip-filter" :class="{ active: period === p }" @click="period = period === p ? null : p">{{ t('doctor.decisions.periodLabel', { days: p }) }}</button>
      <span class="sep" />
      <button type="button" class="chip-filter" :class="{ active: subject === null }" @click="subject = null">{{ t('common.allShort') }} · {{ inPeriod.length }}</button>
      <button v-for="s in subjects" :key="s" type="button" class="chip-filter" :class="{ active: subject === s }" @click="subject = subject === s ? null : s">{{ subjectLabel(s) }} · {{ count((d) => d.subject === s) }}</button>
      <template v-if="roles.length > 1">
        <span class="sep" />
        <button v-for="r in roles" :key="r" type="button" class="chip-filter" :class="{ active: role === r }" @click="role = role === r ? null : r">{{ roleLabel(r) }} · {{ count((d) => d.role === r) }}</button>
      </template>
    </div>
    <KpiRow>
      <KpiTile :value="inPeriod.length" :label="period ? t('doctor.decisions.kpiPeriod', { days: period }) : t('doctor.decisions.kpiAll')" :loading="loading && items.length === 0" />
      <KpiTile :value="matched" :label="t('doctor.decisions.kpiMatched')" tone="ok" :loading="loading && items.length === 0" />
      <KpiTile :value="differ" :label="t('doctor.decisions.kpiDiffer')" tone="warn" :loading="loading && items.length === 0" />
    </KpiRow>

    <AppCard>
      <AsyncState :loading="loading" :error="error" :empty="visible.length === 0" :filtered="items.length > 0 && !!(subject || role || period)" :lines="6"
        :empty-title="t('doctor.decisions.empty')" :empty-text="t('doctor.decisions.emptyText')" empty-icon="pi pi-book" @retry="load" @reset="resetFilters">
      <div class="table-wrap">
        <table class="dense-table" data-testid="decisions-table">
          <thead>
            <tr><th>{{ t('doctor.decisions.when') }}</th><th>{{ t('doctor.decisions.object') }}</th><th>{{ t('doctor.decisions.recommended') }}</th><th>{{ t('doctor.decisions.chosen') }}</th><th>{{ t('doctor.decisions.colOutcome') }}</th><th>{{ t('doctor.decisions.reason') }}</th></tr>
          </thead>
          <tbody>
            <tr v-for="d in visible" :key="d.decisionId" class="clickable" :class="{ selected: selected?.decisionId === d.decisionId && panelOpen }" @click="open(d)">
              <td class="nowrap muted">{{ dateTime(d.recordedAt) }}</td>
              <td><span class="strong">{{ describeSubject(d.subject, d.subjectId, names) }}</span><div class="caption">{{ subjectLabel(d.subject) }} · {{ d.actor }} · {{ roleLabel(d.role) }}</div></td>
              <td class="clip muted">{{ outcome(d) === 'none' ? '—' : shortChoice(d.recommended) }}</td>
              <td class="clip">{{ outcome(d) === 'matched' ? t('doctor.decisions.keptAsRecommended') : shortChoice(d.chosen) }}</td>
              <td><StatusTag :value="t('doctor.decisions.outcome.' + outcome(d))" :tone="OUTCOME_TONES[outcome(d)]" /></td>
              <td class="reason muted">{{ d.reason ? `«${d.reason}»` : '—' }}</td>
            </tr>
          </tbody>
        </table>
      </div>
      </AsyncState>
      <p class="caption" style="margin: 12px 0 0">{{ t('doctor.decisions.keyNote') }}</p>
    </AppCard>

    <SidePanel v-model:visible="panelOpen" :title="selected ? subjectLabel(selected.subject) : ''" :subtitle="selected ? dateTime(selected.recordedAt) : ''">
      <dl v-if="selected" class="facts">
        <dt>{{ t('doctor.decisions.who') }}</dt><dd>{{ selected.actor }} · {{ roleLabel(selected.role) }}</dd>
        <dt>{{ t('doctor.decisions.object') }}</dt><dd>{{ describeSubject(selected.subject, selected.subjectId, names) }}<div class="mono muted small">{{ selected.subjectId }}</div></dd>
        <dt>{{ t('doctor.decisions.recommended') }}</dt><dd>{{ describeChoice(selected.recommended, names) }}</dd>
        <dt>{{ t('doctor.decisions.chosen') }}</dt><dd>{{ describeChoice(selected.chosen, names) }}</dd>
        <dt>{{ t('doctor.decisions.reason') }}</dt><dd>{{ selected.reason || '—' }}</dd>
        <dt>{{ t('doctor.decisions.key') }}</dt><dd class="mono">{{ selected.decisionId }}</dd>
      </dl>
      <p class="muted small" style="margin-top: 12px">{{ t('doctor.decisions.keyNote') }}</p>
    </SidePanel>
  </PageShell>
</template>

<style scoped>
.nowrap { white-space: nowrap; }
.clip { max-width: 260px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.strong { font-weight: var(--fw-bold); }
.reason { max-width: 280px; }
.sep { width: 1px; height: 24px; background: var(--dm-hairline); margin: 0 4px; }
</style>
