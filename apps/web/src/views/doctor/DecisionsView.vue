<script setup lang="ts">
import Column from 'primevue/column'
import DataTable from 'primevue/datatable'
import { onMounted, ref } from 'vue'
import { journal } from '@/api/endpoints'
import type { Decision } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import { useAuthStore } from '@/stores/auth'

const auth = useAuthStore()
const items = ref<Decision[]>([])
const total = ref(0)
const error = ref<unknown>(null)

function json(value: unknown): string {
  return value === null || value === undefined ? '—' : JSON.stringify(value)
}

onMounted(async () => {
  try {
    const page = await journal.decisions({ actor: auth.hasRole('regulator') ? undefined : 'me', size: 100 })
    items.value = page.items
    total.value = page.total
  } catch (e) {
    error.value = e
  }
})
</script>

<template>
  <main class="page">
    <h1>Журнал решений</h1>
    <p class="lead">{{ auth.hasRole('regulator') ? 'Решения врачей и подтверждения сигналов: рекомендация системы и выбор человека.' : 'Ваши решения: рекомендация системы и ваш выбор.' }} Всего {{ total }}.</p>
    <ErrorBox :error="error" />
    <DataTable :value="items" size="small" paginator :rows="25">
      <Column field="recordedAt" header="Когда"><template #body="{ data }">{{ new Date(data.recordedAt).toLocaleString('ru-RU') }}</template></Column>
      <Column field="actor" header="Кто" />
      <Column field="role" header="Роль" />
      <Column field="subject" header="Предмет" />
      <Column field="subjectId" header="Объект" />
      <Column header="Рекомендовано"><template #body="{ data }"><code>{{ json(data.recommended) }}</code></template></Column>
      <Column header="Выбрано"><template #body="{ data }"><code>{{ json(data.chosen) }}</code></template></Column>
      <Column field="reason" header="Причина" />
    </DataTable>
  </main>
</template>
