<script setup lang="ts">
import Button from 'primevue/button'
import Select from 'primevue/select'
import { useToast } from 'primevue/usetoast'
import { onMounted, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import { ApiError } from '@/api/client'
import { analytics, insight, queue } from '@/api/endpoints'
import type { Anomaly, ForecastResponse, IndexResponse, OverloadedOrganization } from '@/api/types'
import AnomalyFeed from '@/components/AnomalyFeed.vue'
import ErrorBox from '@/components/ErrorBox.vue'
import IndexTable from '@/components/IndexTable.vue'
import OriginTag from '@/components/OriginTag.vue'
import OverloadedTable from '@/components/OverloadedTable.vue'
import RegionMap from '@/components/RegionMap.vue'
import SeriesChart from '@/components/SeriesChart.vue'
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
const overloaded = ref<OverloadedOrganization[]>([])
const error = ref<unknown>(null)
const loading = ref(false)
/** 3.1: отдельная карточка по онкологии — поток onco_monthly не имеет региона в сущности (только локализация ЗН),
 * 'ALL' — зарезервированное значение локализации в build_onco_monthly (сумма по всем локализациям), не наша выдумка. */
const onco = ref<ForecastResponse | null>(null)
const oncoHint = ref<string | null>(null)

async function load() {
  loading.value = true
  error.value = null
  try {
    const [idx, an, ov] = await Promise.all([
      analytics.index(month.value ?? undefined, profile.value === 'all' ? undefined : profile.value),
      analytics.anomalies({ status: 'open', size: 12 }),
      queue.overloaded(undefined, profile.value === 'all' ? undefined : profile.value),
    ])
    index.value = idx
    month.value = idx.month
    anomalies.value = an.items
    overloaded.value = ov.items
  } catch (e) {
    error.value = e
  } finally {
    loading.value = false
  }
}

function goToOrganization(code: string) {
  router.push({ name: 'organization', params: { moCode: code } })
}

function goToSimulator(item: OverloadedOrganization) {
  router.push({ name: 'simulator', query: { region: item.regionKato, profile: item.profileCode } })
}

async function loadOnco() {
  onco.value = null
  oncoHint.value = null
  try {
    onco.value = await analytics.forecast('onco_monthly', { localization: 'ALL' }, 3)
  } catch (e) {
    if (e instanceof ApiError && e.status === 404) {
      oncoHint.value = 'Прогноз по онкологии не строился (мало истории).'
      return
    }
    oncoHint.value = 'Витрина по онкологии пока не опубликована.'
  }
}

const downloading = ref(false)

/** Отчёт по индексу за выбранный месяц и профиль — PDF или Excel. */
async function report(format: 'pdf' | 'xlsx') {
  downloading.value = true
  try {
    await insight.report(format, month.value ?? undefined, profile.value === 'all' ? undefined : profile.value)
  } catch (e) {
    error.value = e
  } finally {
    downloading.value = false
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
  await loadOnco()
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
      <Button label="Отчёт PDF" icon="pi pi-file-pdf" size="small" severity="secondary" :loading="downloading" @click="report('pdf')" />
      <Button label="Excel" icon="pi pi-file-excel" size="small" severity="secondary" :loading="downloading" @click="report('xlsx')" />
      <span v-if="loading" class="muted">Загрузка…</span>
    </div>
    <ErrorBox :error="error" />
    <div class="grid cols-2">
      <div>
        <RegionMap :regions="refdata.regions" :index="index?.items ?? []" @select="router.push({ name: 'region', params: { kato: $event } })" />
        <p class="muted" style="margin-top: 8px">{{ index?.method }}</p>
        <!-- значения и правило применения: refdata/external_benchmarks.yaml -->
        <p class="muted" style="margin-top: 4px">
          Внешние ориентиры для p90 ожидания: 112 дней — цель Канады, 90 % катаракт (CIHI, 2023); 126 дней — стандарт NHS
          «18 недель, 92 % пациентов» (2024). Ориентир, не норматив: индекс остаётся относительным.
        </p>
      </div>
      <div class="card">
        <h2>Индекс за {{ index?.month ?? '…' }} <OriginTag kind="formula" /></h2>
        <IndexTable :items="index?.items ?? []" @select="router.push({ name: 'region', params: { kato: $event } })" />
      </div>
    </div>
    <div class="grid cols-2" style="margin-top: 16px">
      <div class="card">
        <h2>Открытые сигналы <OriginTag kind="formula" /></h2>
        <AnomalyFeed :items="anomalies" :can-ack="auth.hasRole('chief', 'regulator')" @ack="ack" @dismiss="dismiss" />
      </div>
      <div class="card">
        <h2>Онкология: впервые выявленные случаи по РК <OriginTag kind="ml" /></h2>
        <SeriesChart v-if="onco" :history="onco.history" :points="onco.points" title="Все локализации, помесячно" unit="случаев" />
        <p v-else class="muted">{{ oncoHint }}</p>
        <p v-if="onco" class="muted">
          Бэктест: sMAPE {{ (onco.backtest.smape * 100).toFixed(1) }} % против наивного {{ (onco.backtest.baselineSmape * 100).toFixed(1) }} %.
          {{ onco.model.name }} {{ onco.model.version }}. Реестр накопительный, честная помесячная интенсивность только с 2024-09 — прогноз ориентировочный.
        </p>
      </div>
    </div>
    <div class="card" style="margin-top: 16px">
      <h2>Перегруженные организации <OriginTag kind="formula" /></h2>
      <OverloadedTable :items="overloaded" @organization="goToOrganization" @simulate="goToSimulator" />
    </div>
  </main>
</template>
