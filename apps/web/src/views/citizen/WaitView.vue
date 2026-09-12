<script setup lang="ts">
import Button from 'primevue/button'
import Select from 'primevue/select'
import { onMounted, ref } from 'vue'
import { analytics, queue } from '@/api/endpoints'
import type { AlternativesResponse, IndexItem, PredictResponse } from '@/api/types'
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
