<script setup lang="ts">
import Column from 'primevue/column'
import DataTable from 'primevue/datatable'
import Select from 'primevue/select'
import { computed, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { journal } from '@/api/endpoints'
import type { WorklistItem } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import PageShell from '@/components/ui/PageShell.vue'
import Skeleton from '@/components/ui/Skeleton.vue'
import StatusTag from '@/components/ui/StatusTag.vue'
import { dateShort, nextActionKey } from '@/lib/route'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'

const { t, te } = useI18n()
const refdata = useRefdataStore()
const auth = useAuthStore()
const items = ref<WorklistItem[]>([])
const modelBacked = ref(false)
const asOf = ref('')
const flag = ref<string | null>(null)
const error = ref<unknown>(null)
const busy = ref(true)
const flags = computed(() => [
  { label: t('doctor.worklist.flagAll'), value: null },
  { label: t('doctor.worklist.flagSignal'), value: 'patient_signal' },
  { label: t('doctor.worklist.flagStuck'), value: 'stuck_over_30' },
  { label: t('doctor.worklist.flagRisk'), value: 'refusal_risk' },
  { label: t('doctor.worklist.flagFaster'), value: 'faster_alternative' },
])

const flagLabels = computed<Record<string, string>>(() => ({
  stuck_over_30: t('doctor.worklist.flagStuckShort'), refusal_risk: t('doctor.worklist.flagRiskShort'), faster_alternative: t('doctor.worklist.flagFasterShort'),
  patient_signal: t('doctor.worklist.flagSignalShort'),
}))
const flagTones: Record<string, 'warn' | 'danger' | 'accent'> = { stuck_over_30: 'warn', refusal_risk: 'danger', faster_alternative: 'accent', patient_signal: 'accent' }

/** Стадия по коду (registered | waiting | called) на языке интерфейса; незнакомый код — русская подпись API как есть. */
function stageLabel(item: WorklistItem): string {
  const key = `doctor.worklist.stageCode.${item.stageCode}`
  return te(key) ? t(key) : item.stage
}

/** Следующий шаг по коду из API на языке интерфейса; незнакомый код — русская подпись API как есть. */
function nextAction(item: WorklistItem): string {
  const key = nextActionKey(item.nextActionCode)
  return key ? t(key) : item.nextAction
}

async function load() {
  error.value = null
  busy.value = true
  try {
    const response = await journal.worklist({ regionKato: auth.region ?? undefined, flag: flag.value ?? undefined })
    items.value = response.items
    modelBacked.value = response.modelBacked
    asOf.value = response.asOf
  } catch (e) {
    error.value = e
  } finally {
    busy.value = false
  }
}

onMounted(async () => {
  await refdata.load()
  await load()
})
watch(flag, load)
</script>

<template>
  <PageShell
    :title="t('doctor.worklist.title')"
    :origin="modelBacked ? 'ml' : 'formula'"
    :origin-note="modelBacked ? t('doctor.worklist.note') : t('doctor.worklist.noteFallback')"
    :synthetic="asOf ? `${t('doctor.worklist.lead')} · ${t('doctor.worklist.asOf', { date: asOf })}` : t('doctor.worklist.lead')"
  >
    <template #actions><Select v-model="flag" :options="flags" option-label="label" option-value="value" size="small" /></template>
    <ErrorBox :error="error" />
    <Skeleton v-if="busy && items.length === 0" kind="table" :lines="8" />
    <EmptyState v-else-if="items.length === 0" :title="t('doctor.worklist.empty')" />
    <DataTable v-else :value="items" size="small" sort-field="priority" :sort-order="-1" paginator :rows="20">
      <Column :header="t('doctor.worklist.patient')">
        <template #body="{ data }"><RouterLink :to="{ name: 'patient-route', params: { patientRef: data.patientRef } }" class="mono" data-testid="worklist-patient">{{ data.patientRef }}</RouterLink></template>
      </Column>
      <Column :header="t('common.profile')"><template #body="{ data }">{{ refdata.profileName(data.profileCode) }}</template></Column>
      <Column :header="t('doctor.worklist.stage')"><template #body="{ data }">{{ stageLabel(data) }}</template></Column>
      <Column field="daysWaiting" :header="t('doctor.worklist.daysWaiting')" sortable />
      <Column :header="t('doctor.worklist.expectedDate')"><template #body="{ data }"><span class="tabular">{{ dateShort(data.expectedDate) }}</span></template></Column>
      <Column :header="t('doctor.worklist.flags')">
        <template #body="{ data }"><StatusTag v-for="f in data.riskFlags" :key="f" :value="flagLabels[f] ?? f" :tone="flagTones[f] ?? 'neutral'" style="margin-right: 4px" /></template>
      </Column>
      <Column field="priority" :header="t('doctor.worklist.priority')" sortable />
      <Column :header="t('doctor.worklist.nextStep')">
        <template #body="{ data }">
          <div v-if="data.patientSignal" class="signal" data-testid="worklist-signal">
            {{ t('route.patientSignal.' + data.patientSignal.kind, { name: data.patientSignal.toMoName ?? '' }) }}
            <span v-if="data.patientSignal.comment" class="muted"> · «{{ data.patientSignal.comment }}»</span>
          </div>
          <span>{{ nextAction(data) }}</span><br /><span class="muted">{{ data.explanation }}</span>
        </template>
      </Column>
      <Column header=""><template #body="{ data }"><RouterLink :to="{ name: 'referral', query: { moCode: data.moCode, profileCode: data.profileCode } }">{{ t('doctor.worklist.openReferral') }}</RouterLink></template></Column>
    </DataTable>
  </PageShell>
</template>

<style scoped>
.mono { font-family: 'IBM Plex Mono', ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 0.9em; }
.signal { font-weight: 600; margin-bottom: 4px; }
</style>
