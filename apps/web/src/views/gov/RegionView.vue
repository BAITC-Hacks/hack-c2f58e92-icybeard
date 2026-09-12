<script setup lang="ts">
import Select from 'primevue/select'
import { useToast } from 'primevue/usetoast'
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { ApiError } from '@/api/client'
import { analytics, queue } from '@/api/endpoints'
import type { Anomaly, ForecastResponse, OrganizationItem, OrganizationSeries } from '@/api/types'
import AnomalyFeed from '@/components/AnomalyFeed.vue'
import ErrorBox from '@/components/ErrorBox.vue'
import OriginTag from '@/components/OriginTag.vue'
import QueueChart from '@/components/QueueChart.vue'
import SeriesChart from '@/components/SeriesChart.vue'
import { days, pct } from '@/lib/format'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'

const route = useRoute()
const refdata = useRefdataStore()
const auth = useAuthStore()
const toast = useToast()

const kato = computed(() => String(route.params.kato))
const organizations = ref<OrganizationItem[]>([])
const moCode = ref<string | null>(null)
const profile = ref<string>('381')
const series = ref<OrganizationSeries | null>(null)
const forecast = ref<ForecastResponse | null>(null)
const anomalies = ref<Anomaly[]>([])
const error = ref<unknown>(null)
const seriesError = ref<unknown>(null)

async function loadRegion() {
  error.value = null
  try {
    organizations.value = await refdata.organizationsOf(kato.value, profile.value)
    moCode.value = organizations.value[0]?.moCode ?? null
    anomalies.value = (await analytics.anomalies({ regionKato: kato.value, status: 'open', size: 10 })).items
    forecast.value = null
    try {
      forecast.value = await analytics.forecast('admissions_monthly', { region_kato: kato.value, profile_code: profile.value }, 3)
    } catch (e) {
      if (!(e instanceof ApiError && e.status === 404)) throw e
    }
  } catch (e) {
    error.value = e
  }
}

async function loadSeries() {
  series.value = null
  seriesError.value = null
  if (!moCode.value) return
  try {
    series.value = await queue.organization(moCode.value, profile.value, 90)
  } catch (e) {
    if (e instanceof ApiError && e.status === 404) return
    seriesError.value = e
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
  await loadRegion()
  await loadSeries()
})
watch(kato, async () => {
  await loadRegion()
  await loadSeries()
})
watch(profile, async () => {
  await loadRegion()
  await loadSeries()
})
watch(moCode, loadSeries)
</script>

<template>
  <main class="page">
    <h1>{{ refdata.regionName(kato) }}</h1>
    <p class="lead">Организации региона, очередь за 90 дней, прогноз госпитализаций и сигналы.</p>
    <div class="actions" style="margin: 0 0 12px">
      <Select v-model="profile" :options="refdata.profiles" option-label="name" option-value="profileCode" filter size="small" style="min-width: 280px" />
      <Select v-model="moCode" :options="organizations" option-label="name" option-value="moCode" filter size="small" placeholder="Организация" style="min-width: 360px; max-width: 100%" />
    </div>
    <ErrorBox :error="error" />
    <div class="grid cols-2">
      <div>
        <ErrorBox :error="seriesError" />
        <div v-if="series" class="kpi" style="margin-bottom: 12px">
          <div class="item"><div class="value">{{ series.days.at(-1)?.queueLen ?? '—' }}</div><div class="label">в очереди сейчас</div></div>
          <div class="item"><div class="value">{{ days(series.throughput?.throughputPerDay, 1) }}</div><div class="label">госпитализаций в день, 4 нед.</div></div>
          <div class="item"><div class="value">{{ days(series.throughput?.waitP50Days) }} / {{ days(series.throughput?.waitP90Days) }}</div><div class="label">факт p50 / p90, дн.</div></div>
          <div class="item"><div class="value">{{ pct(series.throughput?.refusalRate4w) }}</div><div class="label">отказы, 4 нед.</div></div>
        </div>
        <QueueChart v-if="series" :days="series.days" title="Очередь организации по профилю" />
        <p v-else class="muted">Для этой организации и профиля нет ряда очереди.</p>
      </div>
      <div>
        <SeriesChart
          v-if="forecast"
          :history="forecast.history"
          :points="forecast.points"
          :title="`Госпитализации в регионе, профиль ${refdata.profileName(profile)}`"
          unit="случаев"
        />
        <p v-if="forecast" class="muted">
          Бэктест: sMAPE {{ pct(forecast.backtest.smape, 1) }} против наивного {{ pct(forecast.backtest.baselineSmape, 1) }}, MASE {{ forecast.backtest.mase.toFixed(2) }}.
          {{ forecast.model.name }} {{ forecast.model.version }}. <OriginTag kind="ml" />
          <span v-if="forecast.flat" class="synthetic" style="margin-left: 6px">уровень последнего месяца: модель выбрала константу, для планирования малоинформативно</span>
        </p>
        <p v-else class="muted">Прогноз для этого профиля в регионе не строился (мало истории).</p>
      </div>
    </div>
    <div class="card" style="margin-top: 16px">
      <h2>Сигналы региона <OriginTag kind="formula" /></h2>
      <AnomalyFeed :items="anomalies" :can-ack="auth.hasRole('chief', 'regulator')" @ack="ack" />
    </div>
  </main>
</template>
