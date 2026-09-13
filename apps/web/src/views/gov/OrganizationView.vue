<script setup lang="ts">
import Select from 'primevue/select'
import { useToast } from 'primevue/usetoast'
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { ApiError } from '@/api/client'
import { analytics, queue } from '@/api/endpoints'
import type { Anomaly, OrganizationItem, OrganizationSeries, PredictResponse } from '@/api/types'
import AnomalyFeed from '@/components/AnomalyFeed.vue'
import ErrorBox from '@/components/ErrorBox.vue'
import OriginTag from '@/components/OriginTag.vue'
import QueueChart from '@/components/QueueChart.vue'
import { days, pct } from '@/lib/format'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'

const route = useRoute()
const refdata = useRefdataStore()
const auth = useAuthStore()
const toast = useToast()

const moCode = computed(() => String(route.params.moCode))
const kato = computed(() => String(route.query.kato ?? auth.region ?? ''))
const profile = ref<string>(String(route.query.profile ?? '381'))
const organizations = ref<OrganizationItem[]>([])
const series = ref<OrganizationSeries | null>(null)
const regionPrediction = ref<PredictResponse | null>(null)
const anomalies = ref<Anomaly[]>([])
const error = ref<unknown>(null)

const orgName = computed(() => organizations.value.find((o) => o.moCode === moCode.value)?.name ?? moCode.value)

/** Сигналы, в сущности которых встречается код организации (mo_key и т. п.). */
const orgAnomalies = computed(() => anomalies.value.filter((a) => Object.values(a.entity).includes(moCode.value)))

async function load() {
  error.value = null
  series.value = null
  regionPrediction.value = null
  try {
    organizations.value = await refdata.organizationsOf(kato.value, undefined)
    try {
      series.value = await queue.organization(moCode.value, profile.value, 90)
    } catch (e) {
      if (!(e instanceof ApiError && e.status === 404)) throw e
    }
    regionPrediction.value = await queue.predict({ regionKato: kato.value, profileCode: profile.value })
    anomalies.value = (await analytics.anomalies({ regionKato: kato.value, status: 'open', size: 50 })).items
  } catch (e) {
    error.value = e
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

async function dismiss(id: string, comment: string) {
  try {
    await analytics.ack(id, comment, 'dismissed')
    anomalies.value = anomalies.value.filter((a) => a.id !== id)
    toast.add({ severity: 'info', summary: 'Отмечен как ложный', life: 2500 })
  } catch (e) {
    error.value = e
  }
}

onMounted(async () => {
  await refdata.load()
  await load()
})
watch([moCode, profile], load)
</script>

<template>
  <main class="page">
    <h1>{{ orgName }}</h1>
    <p class="lead">
      Кабинет организации: очередь и пропускная способность по профилю, сравнение с регионом, сигналы.
      <RouterLink :to="`/gov/regions/${kato}`">← регион {{ refdata.regionName(kato) }}</RouterLink>
    </p>
    <div class="actions" style="margin: 0 0 12px">
      <Select v-model="profile" :options="refdata.profiles" option-label="name" option-value="profileCode" filter size="small" style="min-width: 280px" />
    </div>
    <ErrorBox :error="error" />
    <div class="grid cols-2">
      <div class="card">
        <h2>Организация · факт за 4 недели</h2>
        <template v-if="series">
          <div class="kpi">
            <div class="item"><div class="value">{{ series.days.at(-1)?.queueLen ?? '—' }}</div><div class="label">в очереди сейчас</div></div>
            <div class="item"><div class="value">{{ days(series.throughput?.throughputPerDay, 1) }}</div><div class="label">госпитализаций в день</div></div>
            <div class="item"><div class="value">{{ days(series.throughput?.waitP50Days) }} / {{ days(series.throughput?.waitP90Days) }}</div><div class="label">факт p50 / p90, дн.</div></div>
            <div class="item"><div class="value">{{ pct(series.throughput?.refusalRate4w) }}</div><div class="label">отказы</div></div>
          </div>
        </template>
        <p v-else class="muted">По этому профилю у организации нет ряда очереди.</p>
      </div>
      <div class="card">
        <h2>Регион для сравнения <OriginTag kind="ml" /></h2>
        <template v-if="regionPrediction">
          <div class="kpi">
            <div class="item"><div class="value">{{ days(regionPrediction.p50Days) }} / {{ days(regionPrediction.p90Days) }}</div><div class="label">прогноз p50 / p90 по региону, дн.</div></div>
            <div class="item"><div class="value">{{ pct(regionPrediction.pWithin30Days) }}</div><div class="label">попадают за 30 дней</div></div>
            <div class="item"><div class="value">{{ pct(regionPrediction.pRefusal) }}</div><div class="label">риск отказа по региону</div></div>
          </div>
          <p class="muted" style="margin-top: 8px">
            {{ (series?.throughput?.waitP50Days ?? 0) > regionPrediction.p50Days ? 'Организация ждёт дольше регионального прогноза — кандидат на перераспределение.' : 'Ожидание не хуже регионального прогноза.' }}
          </p>
        </template>
        <p v-else class="muted">Прогноз по региону недоступен.</p>
      </div>
    </div>
    <div style="margin-top: 16px">
      <QueueChart v-if="series" :days="series.days" title="Очередь организации за 90 дней" />
    </div>
    <div class="card" style="margin-top: 16px">
      <h2>Сигналы организации <OriginTag kind="formula" /></h2>
      <AnomalyFeed :items="orgAnomalies" :can-ack="auth.hasRole('chief', 'regulator')" @ack="ack" @dismiss="dismiss" />
      <p v-if="orgAnomalies.length === 0" class="muted">Открытых сигналов по этой организации нет.</p>
    </div>
  </main>
</template>
