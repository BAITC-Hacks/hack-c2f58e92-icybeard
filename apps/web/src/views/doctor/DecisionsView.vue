<script setup lang="ts">
import Button from 'primevue/button'
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { journal } from '@/api/endpoints'
import type { Decision } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import PageShell from '@/components/ui/PageShell.vue'
import SidePanel from '@/components/ui/SidePanel.vue'
import Skeleton from '@/components/ui/Skeleton.vue'
import StatusTag from '@/components/ui/StatusTag.vue'
import { useLocaleFormat } from '@/composables/useLocaleFormat'
import { downloadCsv } from '@/lib/csv'
import { describeChoice, describeSubject, organizationOf, roleLabel, SUBJECT_ANOMALY, SUBJECT_REFERRAL, subjectLabel, type DecisionNames } from '@/lib/decision'
import { shortOrgName } from '@/lib/format'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'

/** Журнал решений: фильтры чипами (предмет, роль, период) на клиенте, экспорт CSV, плотная таблица с короткими
 * именами; клик по строке — панель с полными данными и ключом записи. */
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
const period = ref<number | null>(null)
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
const subjects = computed(() => [...new Set([SUBJECT_REFERRAL, SUBJECT_ANOMALY, ...items.value.map((d) => d.subject)])])
const roles = computed(() => [...new Set(items.value.map((d) => d.role))])
const visible = computed(() => {
  const since = period.value ? Date.now() - period.value * 86_400_000 : 0
  return items.value.filter((d) => (!subject.value || d.subject === subject.value) && (!role.value || d.role === role.value) && (!since || new Date(d.recordedAt).getTime() >= since))
})
const count = (pred: (d: Decision) => boolean) => items.value.filter(pred).length

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
    const page = await journal.decisions({ actor: auth.hasRole('regulator') ? undefined : 'me', size: 200 })
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
  <PageShell :title="t('doctor.decisions.title')" :lead="`${auth.hasRole('regulator') ? t('doctor.decisions.leadRegulator') : t('doctor.decisions.leadSelf')} ${t('doctor.decisions.total')}: ${total}.`">
    <template #actions>
      <Button :label="t('doctor.decisions.refresh')" icon="pi pi-refresh" size="small" severity="secondary" text :loading="loading" @click="load" />
      <Button :label="t('shell.exportCsv')" icon="pi pi-download" size="small" severity="secondary" outlined :disabled="visible.length === 0" data-testid="decisions-export" @click="exportCsv" />
    </template>
    <div class="toolbar">
      <div class="chips">
        <button type="button" class="chip-filter" :class="{ active: subject === null }" @click="subject = null">{{ t('common.allShort') }} <span class="count">{{ items.length }}</span></button>
        <button v-for="s in subjects" :key="s" type="button" class="chip-filter" :class="{ active: subject === s }" @click="subject = subject === s ? null : s">{{ subjectLabel(s) }} <span class="count">{{ count((d) => d.subject === s) }}</span></button>
      </div>
      <div v-if="roles.length > 1" class="chips">
        <button v-for="r in roles" :key="r" type="button" class="chip-filter" :class="{ active: role === r }" @click="role = role === r ? null : r">{{ roleLabel(r) }} <span class="count">{{ count((d) => d.role === r) }}</span></button>
      </div>
      <div class="chips">
        <button v-for="p in PERIODS" :key="p" type="button" class="chip-filter" :class="{ active: period === p }" @click="period = period === p ? null : p">{{ t('shell.lastDays', { days: p }) }}</button>
      </div>
    </div>
    <ErrorBox :error="error" />
    <Skeleton v-if="loading && items.length === 0" kind="table" :lines="6" />
    <EmptyState v-else-if="visible.length === 0" :title="t('doctor.decisions.empty')" icon="pi pi-book" />
    <div v-else class="table-wrap card dense-card">
      <table class="dense-table" data-testid="decisions-table">
        <thead>
          <tr><th>{{ t('doctor.decisions.when') }}</th><th>{{ t('doctor.decisions.subject') }}</th><th>{{ t('doctor.decisions.object') }}</th><th>{{ t('doctor.decisions.recommendedChosen') }}</th><th>{{ t('doctor.decisions.reason') }}</th></tr>
        </thead>
        <tbody>
          <tr v-for="d in visible" :key="d.decisionId" class="clickable" :class="{ selected: selected?.decisionId === d.decisionId && panelOpen }" @click="open(d)">
            <td class="nowrap">{{ dateTime(d.recordedAt) }}<div class="muted small">{{ d.actor }} · {{ roleLabel(d.role) }}</div></td>
            <td><StatusTag :value="subjectLabel(d.subject)" :tone="d.subject === SUBJECT_ANOMALY ? 'warn' : 'accent'" /></td>
            <td><span class="mono">{{ describeSubject(d.subject, d.subjectId, names) }}</span></td>
            <td><span class="muted">{{ shortChoice(d.recommended) }}</span> → <b>{{ shortChoice(d.chosen) }}</b></td>
            <td class="reason">{{ d.reason ? `«${d.reason}»` : '—' }}</td>
          </tr>
        </tbody>
      </table>
    </div>

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
.dense-card { padding: 0 var(--dm-space-2); }
.nowrap { white-space: nowrap; }
.reason { max-width: 320px; }
</style>
