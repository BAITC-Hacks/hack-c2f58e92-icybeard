<script setup lang="ts">
import Button from 'primevue/button'
import Select from 'primevue/select'
import { computed, onMounted, ref } from 'vue'
import { analytics, queue, refdata as refdataApi } from '@/api/endpoints'
import type { AlternativesResponse, IndexItem, PredictResponse, Seasonality } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import OriginTag from '@/components/OriginTag.vue'
import { days, pct } from '@/lib/format'
import { useRefdataStore } from '@/stores/refdata'

const refdata = useRefdataStore()
const region = ref('75')
const profile = ref('381')
const prediction = ref<PredictResponse | null>(null)
const alternatives = ref<AlternativesResponse | null>(null)
const indexItem = ref<IndexItem | null>(null)
const error = ref<unknown>(null)
const busy = ref(false)
const seasonality = ref<Seasonality[]>([])

/** Сезонный ориентир: лист ожидания в ближайшие месяцы относительно текущего (форма NHS RTT). */
const seasonalHint = computed(() => {
  const wl = seasonality.value.filter((s) => s.seriesId === 'rtt_waiting_list')
  if (wl.length !== 12) return null
  const byMonth = new Map(wl.map((s) => [s.month, s.multiplier]))
  const now = new Date().getMonth() + 1
  const current = byMonth.get(now)
  if (!current) return null
  const names = ['', 'январе', 'феврале', 'марте', 'апреле', 'мае', 'июне', 'июле', 'августе', 'сентябре', 'октябре', 'ноябре', 'декабре']
  const parts = [1, 2, 3].map((step) => {
    const m = ((now - 1 + step) % 12) + 1
    const delta = ((byMonth.get(m)! - current) / current) * 100
    const sign = delta > 0.05 ? '+' : delta < -0.05 ? '−' : '±'
    return `в ${names[m]} ${sign}${Math.abs(delta).toFixed(1)} %`
  })
  return parts.join(', ')
})

async function run() {
  busy.value = true
  error.value = null
  try {
    const body = { regionKato: region.value, profileCode: profile.value }
    const [p, a, idx] = await Promise.all([queue.predict(body), queue.alternatives({ ...body, limit: 3 }), analytics.index(undefined, profile.value)])
    prediction.value = p
    alternatives.value = a
    indexItem.value = idx.items.find((i) => i.regionKato === region.value) ?? null
  } catch (e) {
    error.value = e
  } finally {
    busy.value = false
  }
}

onMounted(async () => {
  await refdata.load()
  await run()
  try {
    seasonality.value = (await refdataApi.seasonality()).items
  } catch {
    seasonality.value = [] // без витрины сезонности страница работает как раньше
  }
})
</script>

<template>
  <main class="page">
    <h1>Сколько ждать плановую госпитализацию</h1>
    <p class="lead">Оценка по региону и профилю койки на данных I квартала 2025 года. Без персональных данных.</p>
    <div class="card">
      <div class="form-grid">
        <div class="field"><label>Регион</label><Select v-model="region" :options="refdata.regions" option-label="name" option-value="regionKato" filter /></div>
        <div class="field"><label>Профиль койки</label><Select v-model="profile" :options="refdata.profiles" option-label="name" option-value="profileCode" filter /></div>
      </div>
      <div class="actions"><Button label="Узнать" icon="pi pi-search" :loading="busy" @click="run" /></div>
      <ErrorBox :error="error" />
    </div>
    <div v-if="prediction" class="grid cols-2" style="margin-top: 16px">
      <div class="card">
        <h2>В среднем по региону <OriginTag kind="ml" /></h2>
        <div class="kpi">
          <div class="item"><div class="value">{{ days(prediction.p50Days) }}</div><div class="label">половина пациентов ждёт не дольше, дн.</div></div>
          <div class="item"><div class="value">{{ days(prediction.p90Days) }}</div><div class="label">9 из 10 ждут не дольше, дн.</div></div>
          <div class="item"><div class="value">{{ pct(prediction.pWithin30Days) }}</div><div class="label">попадают за 30 дней</div></div>
        </div>
        <p v-if="indexItem" class="muted" style="margin-top: 8px">Индекс доступности региона {{ indexItem.indexValue.toFixed(1) }}, место {{ indexItem.rank }} среди регионов. <OriginTag kind="formula" /></p>
        <p v-if="seasonalHint" class="muted" style="margin-top: 8px">
          Сезонный ориентир: в системах типа NHS лист ожидания к текущему месяцу обычно меняется {{ seasonalHint }}
          (форма сезона NHS England RTT, 2017–2019 — внешний ориентир, наши данные пока покрывают один квартал).
        </p>
        <p v-else class="muted" style="margin-top: 8px">Индекс для региона не показан: слишком мало наблюдений (малые числа подавлены).</p>
      </div>
      <div class="card">
        <h2>Где быстрее</h2>
        <p v-if="!alternatives || alternatives.items.length === 0" class="muted">Данных об организациях с этим профилем нет.</p>
        <div v-for="a in alternatives?.items ?? []" :key="a.mo.moCode" class="factor">
          <span>{{ a.mo.name }}</span>
          <span class="contribution">{{ days(a.p50Days) }} дн.</span>
        </div>
      </div>
    </div>
  </main>
</template>
