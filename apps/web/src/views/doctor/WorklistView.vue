<script setup lang="ts">
import Column from 'primevue/column'
import DataTable from 'primevue/datatable'
import Select from 'primevue/select'
import Tag from 'primevue/tag'
import { computed, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRouter } from 'vue-router'
import { journal } from '@/api/endpoints'
import type { WorklistItem } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import OriginTag from '@/components/OriginTag.vue'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'

const { t } = useI18n()
const refdata = useRefdataStore()
const auth = useAuthStore()
const router = useRouter()
const items = ref<WorklistItem[]>([])
const modelBacked = ref(false)
const flag = ref<string | null>(null)
const error = ref<unknown>(null)
const flags = computed(() => [
  { label: t('doctor.worklist.flagAll'), value: null },
  { label: t('doctor.worklist.flagStuck'), value: 'stuck_over_30' },
  { label: t('doctor.worklist.flagRisk'), value: 'refusal_risk' },
  { label: t('doctor.worklist.flagFaster'), value: 'faster_alternative' },
])

async function load() {
  error.value = null
  try {
    const response = await journal.worklist({ regionKato: auth.region ?? undefined, flag: flag.value ?? undefined })
    items.value = response.items
    modelBacked.value = response.modelBacked
  } catch (e) {
    error.value = e
  }
}

const flagLabels = computed<Record<string, string>>(() => ({ stuck_over_30: t('doctor.worklist.flagStuckShort'), refusal_risk: t('doctor.worklist.flagRiskShort'), faster_alternative: t('doctor.worklist.flagFasterShort') }))

onMounted(async () => {
  await refdata.load()
  await load()
})
watch(flag, load)
</script>

<template>
  <main class="page">
    <h1>{{ t('doctor.worklist.title') }} <OriginTag :kind="modelBacked ? 'ml' : 'formula'" :note="modelBacked ? t('doctor.worklist.note') : t('doctor.worklist.noteFallback')" /></h1>
    <p class="lead synthetic">{{ t('doctor.worklist.lead') }}</p>
    <div class="actions" style="margin: 0 0 12px"><Select v-model="flag" :options="flags" option-label="label" option-value="value" size="small" /></div>
    <ErrorBox :error="error" />
    <DataTable :value="items" size="small" sort-field="priority" :sort-order="-1" paginator :rows="20">
      <Column field="patientRef" :header="t('doctor.worklist.patient')" />
      <Column :header="t('common.profile')"><template #body="{ data }">{{ refdata.profileName(data.profileCode) }}</template></Column>
      <Column field="stage" :header="t('doctor.worklist.stage')" />
      <Column field="daysWaiting" :header="t('doctor.worklist.daysWaiting')" sortable />
      <Column field="expectedDate" :header="t('doctor.worklist.expectedDate')" />
      <Column :header="t('doctor.worklist.flags')"><template #body="{ data }"><Tag v-for="f in data.riskFlags" :key="f" :value="flagLabels[f] ?? f" severity="warn" style="margin-right: 4px" /></template></Column>
      <Column field="priority" :header="t('doctor.worklist.priority')" sortable />
      <Column :header="t('doctor.worklist.nextStep')"><template #body="{ data }"><span>{{ data.nextAction }}</span><br /><span class="muted">{{ data.explanation }}</span></template></Column>
      <Column header=""><template #body="{ data }"><a href="#" @click.prevent="router.push({ name: 'referral', query: { moCode: data.moCode, profileCode: data.profileCode } })">{{ t('doctor.worklist.openReferral') }}</a></template></Column>
    </DataTable>
  </main>
</template>
