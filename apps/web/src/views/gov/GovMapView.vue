<script setup lang="ts">
import Select from 'primevue/select'
import { useToast } from 'primevue/usetoast'
import { onMounted, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import { analytics } from '@/api/endpoints'
import type { Anomaly, IndexResponse } from '@/api/types'
import AnomalyFeed from '@/components/AnomalyFeed.vue'
import ErrorBox from '@/components/ErrorBox.vue'
import IndexTable from '@/components/IndexTable.vue'
import RegionMap from '@/components/RegionMap.vue'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'

const refdata = useRefdataStore()
const auth = useAuthStore()
const router = useRouter()
const toast = useToast()

const month = ref<string | null>(null)
const profile = ref<string>('all')
const index = ref<IndexResponse | null>(null)
const anomalies = ref<Anomaly[]>([])
const error = ref<unknown>(null)
const loading = ref(false)

async function load() {
  loading.value = true
  error.value = null
  try {
    const [idx, an] = await Promise.all([
      analytics.index(month.value ?? undefined, profile.value === 'all' ? undefined : profile.value),
      analytics.anomalies({ status: 'open', size: 12 }),
    ])
    index.value = idx
    month.value = idx.month
    anomalies.value = an.items
  } catch (e) {
    error.value = e
  } finally {
    loading.value = false
  }
}

async function ack(id: string, comment: string) {
  try {
    await analytics.ack(id, comment)
    anomalies.value = anomalies.value.filter((a) => a.id !== id)
    toast.add({ severity: 'success', summary: 'Сигнал подтверждён', life: 2500 })
  } catch (e) {
    error.value = e
  }
}

onMounted(async () => {
  await refdata.load()
  await load()
})
watch([month, profile], load)
</script>

<template>
  <main class="page">
    <h1>Карта регионов</h1>
    <p class="lead">Индекс доступности плановой госпитализации по регионам и открытые сигналы аномалий. Клик по региону открывает организации, ряды и прогноз.</p>
    <div class="actions" style="margin: 0 0 12px">
      <Select v-model="month" :options="index?.months ?? []" placeholder="Месяц" size="small" />
      <Select
        v-model="profile"
        :options="[{ profileCode: 'all', name: 'Все профили' }, ...refdata.profiles]"
        option-label="name"
        option-value="profileCode"
        filter
        size="small"
        style="min-width: 280px"
      />
      <span v-if="loading" class="muted">Загрузка…</span>
    </div>
    <ErrorBox :error="error" />
    <div class="grid cols-2">
      <div>
        <RegionMap :regions="refdata.regions" :index="index?.items ?? []" @select="router.push({ name: 'region', params: { kato: $event } })" />
        <p class="muted" style="margin-top: 8px">{{ index?.method }}</p>
      </div>
      <div class="card">
        <h2>Индекс за {{ index?.month ?? '…' }}</h2>
        <IndexTable :items="index?.items ?? []" @select="router.push({ name: 'region', params: { kato: $event } })" />
      </div>
    </div>
    <div class="card" style="margin-top: 16px">
      <h2>Открытые сигналы</h2>
      <AnomalyFeed :items="anomalies" :can-ack="auth.hasRole('chief', 'regulator')" @ack="ack" />
    </div>
  </main>
</template>
