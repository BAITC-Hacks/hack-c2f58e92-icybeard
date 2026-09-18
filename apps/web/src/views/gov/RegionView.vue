<script setup lang="ts">
import Select from 'primevue/select'
import { useToast } from 'primevue/usetoast'
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { ApiError } from '@/api/client'
import { analytics, queue, refdata as refdataApi } from '@/api/endpoints'
import type { Anomaly, ForecastResponse, OrganizationItem, OrganizationSeries, Seasonality } from '@/api/types'
import AnomalyFeed from '@/components/AnomalyFeed.vue'
import ErrorBox from '@/components/ErrorBox.vue'
import OriginTag from '@/components/OriginTag.vue'
import QueueChart from '@/components/QueueChart.vue'
import SeriesChart from '@/components/SeriesChart.vue'
import { days, pct } from '@/lib/format'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'

/** Переключатель потока для прогноза справа (3.1): у каждого потока свой второй ключ сущности и единица измерения —
 * госпитализации по профилю, приёмный покой по конкретной организации региона (нужен entity.mo_key, не mo_code —
 * см. gold.anomalies/mo_registry.name_key), вакцинация по коду плана. */
const STREAMS = [
  { value: 'admissions', label: 'Госпитализации', streamId: 'admissions_monthly', unit: 'случаев' },
  { value: 'er_visits', label: 'Приёмный покой', streamId: 'er_visits_daily', unit: 'обращений' },
  { value: 'vac', label: 'Вакцинация', streamId: 'vac_monthly', unit: 'доз' },
] as const
type StreamKind = (typeof STREAMS)[number]['value']

const route = useRoute()
const refdata = useRefdataStore()
const auth = useAuthStore()
const toast = useToast()

const kato = computed(() => String(route.params.kato))
const organizations = ref<OrganizationItem[]>([])
const moCode = ref<string | null>(null)
const profile = ref<string>('381')
const streamKind = ref<StreamKind>('admissions')
const vaccinationPlans = ref<string[]>([])
const vaccinationPlan = ref<string | null>(null)
const series = ref<OrganizationSeries | null>(null)
const forecast = ref<ForecastResponse | null>(null)
const forecastHint = ref<string | null>(null)
const anomalies = ref<Anomaly[]>([])
const error = ref<unknown>(null)
const seriesError = ref<unknown>(null)
const seasonality = ref<Seasonality[]>([])

const streamMeta = computed(() => STREAMS.find((s) => s.value === streamKind.value)!)
const selectedOrganization = computed(() => organizations.value.find((o) => o.moCode === moCode.value) ?? null)

/** Для плоского прогноза: месяцы горизонта с сезонным множителем NHS (форма плановых госпитализаций). Ориентир
 * подобран только для потока госпитализаций — для приёмного покоя и вакцинации сезонность другая. */
const flatSeasonHint = computed(() => {
  if (streamKind.value !== 'admissions' || !forecast.value?.flat) return null
  const adm = new Map(seasonality.value.filter((s) => s.seriesId === 'rtt_admitted_per_day').map((s) => [s.month, s.multiplier]))
  if (adm.size !== 12) return null
  const short = ['', 'янв', 'фев', 'мар', 'апр', 'май', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек']
  return forecast.value.points
    .map((p) => {
      const m = Number(p.period.slice(5, 7))
      const delta = (adm.get(m)! - 1) * 100
      return `${short[m]} ${delta > 0 ? '+' : '−'}${Math.abs(delta).toFixed(0)} %`
    })
    .join(', ')
})

/** Сущность для выбранного потока — null, если для неё ещё не выбран нужный второй ключ (организация/план). */
function forecastEntity(): Record<string, string> | null {
  if (streamKind.value === 'admissions') return { region_kato: kato.value, profile_code: profile.value }
  if (streamKind.value === 'er_visits') return selectedOrganization.value?.moKey ? { region_kato: kato.value, mo_key: selectedOrganization.value.moKey } : null
  return vaccinationPlan.value ? { region_kato: kato.value, vaccination_plan: vaccinationPlan.value } : null
}

async function loadForecast() {
  forecast.value = null
  forecastHint.value = null
  const entity = forecastEntity()
  if (!entity) {
    forecastHint.value = streamKind.value === 'er_visits' ? 'Выберите организацию, чтобы увидеть прогноз приёмного покоя.' : 'Выберите план вакцинации, чтобы увидеть прогноз.'
    return
  }
  try {
    forecast.value = await analytics.forecast(streamMeta.value.streamId, entity, 3)
  } catch (e) {
    if (e instanceof ApiError && e.status === 404) {
      forecastHint.value = 'Прогноз для этого выбора не строился (мало истории).'
      return
    }
    throw e
  }
}

async function loadRegion() {
  error.value = null
  try {
    organizations.value = await refdata.organizationsOf(kato.value, profile.value)
    moCode.value = organizations.value[0]?.moCode ?? null
    anomalies.value = (await analytics.anomalies({ regionKato: kato.value, status: 'open', size: 10 })).items
    await loadForecast()
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

async function loadVaccinationPlans() {
  try {
    vaccinationPlans.value = (await refdataApi.vaccinationPlans(kato.value)).items
    vaccinationPlan.value = vaccinationPlans.value[0] ?? null
  } catch {
    vaccinationPlans.value = [] // витрина ещё не опубликована
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
  await loadVaccinationPlans()
  await loadRegion()
  await loadSeries()
  try {
    seasonality.value = (await refdataApi.seasonality()).items
  } catch {
    seasonality.value = [] // подсказка сезонности опциональна
  }
})
watch(kato, async () => {
  await loadVaccinationPlans()
  await loadRegion()
  await loadSeries()
})
watch(profile, async () => {
  await loadRegion()
  await loadSeries()
})
watch(moCode, loadSeries)
watch(streamKind, loadForecast)
watch(vaccinationPlan, () => {
  if (streamKind.value === 'vac') loadForecast()
})
</script>

<template>
  <main class="page">
    <h1>{{ refdata.regionName(kato) }}</h1>
    <p class="lead">Организации региона, очередь за 90 дней, прогноз госпитализаций и сигналы.</p>
    <div class="actions" style="margin: 0 0 12px">
      <Select v-model="profile" :options="refdata.profiles" option-label="name" option-value="profileCode" filter size="small" style="min-width: 280px" />
      <Select v-model="moCode" :options="organizations" option-label="name" option-value="moCode" filter size="small" placeholder="Организация" style="min-width: 360px; max-width: 100%" />
      <RouterLink v-if="moCode" :to="{ name: 'organization', params: { moCode }, query: { kato, profile } }">кабинет организации →</RouterLink>
    </div>
    <ErrorBox :error="error" />
    <div class="grid cols-2">
      <div>
        <ErrorBox :error="seriesError" />
        <div v-if="series" class="kpi" style="margin-bottom: 12px">
          <div class="item"><div class="value">{{ series.days.at(-1)?.queueLen ?? '—' }}</div><div class="label">в очереди сейчас</div></div>
          <div class="item"><div class="value">{{ days(series.throughput?.throughputPerDay, 1) }}</div><div class="label">госпитализаций в день, 4 нед.</div></div>
          <div class="item"><div class="value">{{ days(series.throughput?.waitP50Days) }} / {{ days(series.throughput?.waitP90Days) }}</div><div class="label">факт p50 / p90 среди госпитализированных, дн.</div></div>
          <div class="item"><div class="value">{{ pct(series.throughput?.refusalRate4w) }}</div><div class="label">отказы, 4 нед.</div></div>
        </div>
        <QueueChart v-if="series" :days="series.days" title="Очередь организации по профилю" />
        <p v-else class="muted">Для этой организации и профиля нет ряда очереди.</p>
      </div>
      <div>
        <div class="actions" style="margin: 0 0 8px">
          <Select v-model="streamKind" :options="STREAMS" option-label="label" option-value="value" size="small" style="min-width: 220px" />
          <Select
            v-if="streamKind === 'vac'"
            v-model="vaccinationPlan"
            :options="vaccinationPlans"
            filter
            size="small"
            placeholder="План вакцинации"
            style="min-width: 240px"
          />
        </div>
        <SeriesChart
          v-if="forecast"
          :history="forecast.history"
          :points="forecast.points"
          :title="streamKind === 'admissions' ? `Госпитализации в регионе, профиль ${refdata.profileName(profile)}` : streamKind === 'er_visits' ? `Приёмный покой, ${selectedOrganization?.name ?? ''}` : `Вакцинация, ${vaccinationPlan ?? ''}`"
          :unit="streamMeta.unit"
        />
        <p v-else-if="forecastHint" class="muted">{{ forecastHint }}</p>
        <p v-if="forecast" class="muted">
          Бэктест: sMAPE {{ pct(forecast.backtest.smape, 1) }} против наивного {{ pct(forecast.backtest.baselineSmape, 1) }}, MASE {{ forecast.backtest.mase.toFixed(2) }}.
          {{ forecast.model.name }} {{ forecast.model.version }}. <OriginTag kind="ml" />
          <span v-if="forecast.flat" class="synthetic" style="margin-left: 6px">уровень последнего месяца: модель выбрала константу, для планирования малоинформативно</span>
        </p>
        <template v-if="streamKind === 'admissions'">
          <p v-if="flatSeasonHint" class="muted">
            Сезонная форма плановых госпитализаций в системах типа NHS для этих месяцев: {{ flatSeasonHint }} к среднему
            (NHS England RTT, 2017–2019 — внешний ориентир, не поправка модели).
          </p>
          <!-- коэффициент и источник: refdata/external_benchmarks.yaml (diagnostics.dm01_tests_per_admission) -->
          <p v-if="forecast && forecast.points.length" class="muted">
            Оценка нагрузки на диагностику: ≈ {{ Math.round((forecast.points.reduce((s, p) => s + p.yhat, 0) / forecast.points.length) * 1.5).toLocaleString('ru-RU') }}
            исследований в месяц по этому профилю (прогноз × 1,5 исследования на госпитализацию, производная NHS DM01, 2024 — внешний ориентир, не измерение; уточнится с данными ЕИП).
          </p>
          <p v-else-if="!forecast && !forecastHint" class="muted">Прогноз для этого профиля в регионе не строился (мало истории).</p>
        </template>
      </div>
    </div>
    <div class="card" style="margin-top: 16px">
      <h2>Сигналы региона <OriginTag kind="formula" /></h2>
      <AnomalyFeed :items="anomalies" :can-ack="auth.hasRole('chief', 'regulator')" @ack="ack" @dismiss="dismiss" />
    </div>
  </main>
</template>
