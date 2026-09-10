<script setup lang="ts">
import Column from 'primevue/column'
import DataTable from 'primevue/datatable'
import Select from 'primevue/select'
import Tag from 'primevue/tag'
import { onMounted, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import { journal } from '@/api/endpoints'
import type { WorklistItem } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'

const refdata = useRefdataStore()
const auth = useAuthStore()
const router = useRouter()
const items = ref<WorklistItem[]>([])
const flag = ref<string | null>(null)
const error = ref<unknown>(null)
const flags = [
  { label: 'все', value: null },
  { label: 'застрял дольше 30 дней', value: 'stuck_over_30' },
  { label: 'высокий риск отказа', value: 'refusal_risk' },
  { label: 'есть быстрее альтернатива', value: 'faster_alternative' },
]

async function load() {
  error.value = null
  try {
    items.value = (await journal.worklist({ regionKato: auth.region ?? undefined, flag: flag.value ?? undefined })).items
  } catch (e) {
    error.value = e
  }
}

const flagLabels: Record<string, string> = { stuck_over_30: '> 30 дней', refusal_risk: 'риск отказа', faster_alternative: 'есть быстрее' }

onMounted(async () => {
  await refdata.load()
  await load()
})
watch(flag, load)
</script>

<template>
  <main class="page">
    <h1>Рабочий список</h1>
    <p class="lead synthetic">Пациенты на маршруте плановой госпитализации. На кэмпе список синтетический: он собран из реальных очередей организаций без персональных данных.</p>
    <div class="actions" style="margin: 0 0 12px"><Select v-model="flag" :options="flags" option-label="label" option-value="value" size="small" /></div>
    <ErrorBox :error="error" />
    <DataTable :value="items" size="small" sort-field="priority" :sort-order="-1" paginator :rows="20">
      <Column field="patientRef" header="Пациент" />
      <Column header="Профиль"><template #body="{ data }">{{ refdata.profileName(data.profileCode) }}</template></Column>
      <Column field="stage" header="Этап" />
      <Column field="daysWaiting" header="Ждёт, дн." sortable />
      <Column field="expectedDate" header="Ожидаемая дата" />
      <Column header="Флаги"><template #body="{ data }"><Tag v-for="f in data.riskFlags" :key="f" :value="flagLabels[f] ?? f" severity="warn" style="margin-right: 4px" /></template></Column>
      <Column field="priority" header="Приоритет" sortable />
      <Column header="Следующий шаг"><template #body="{ data }"><span>{{ data.nextAction }}</span><br /><span class="muted">{{ data.explanation }}</span></template></Column>
      <Column header=""><template #body="{ data }"><a href="#" @click.prevent="router.push({ name: 'referral', query: { moCode: data.moCode, profileCode: data.profileCode } })">открыть направление</a></template></Column>
    </DataTable>
  </main>
</template>
