<script setup lang="ts">
import Button from 'primevue/button'
import Checkbox from 'primevue/checkbox'
import Select from 'primevue/select'
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { analytics, queue, refdata as refdataApi } from '@/api/endpoints'
import type { AlternativesResponse, IndexItem, PredictResponse, Seasonality } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import OriginTag from '@/components/OriginTag.vue'
import { days, pct } from '@/lib/format'
import { useRefdataStore } from '@/stores/refdata'

const { t } = useI18n()
const refdata = useRefdataStore()
const region = ref('75')
const profile = ref('381')
const prediction = ref<PredictResponse | null>(null)
const alternatives = ref<AlternativesResponse | null>(null)
const indexItem = ref<IndexItem | null>(null)
const error = ref<unknown>(null)
const busy = ref(false)
const seasonality = ref<Seasonality[]>([])
const includeNeighbors = ref(false)

/** Сезонный ориентир: лист ожидания в ближайшие месяцы относительно текущего (форма NHS RTT). */
const seasonalHint = computed(() => {
  const wl = seasonality.value.filter((s) => s.seriesId === 'rtt_waiting_list')
  if (wl.length !== 12) return null
  const byMonth = new Map(wl.map((s) => [s.month, s.multiplier]))
  const now = new Date().getMonth() + 1
  const current = byMonth.get(now)
  if (!current) return null
  const names = t('citizen.wait.monthsIn').split(',')
  const parts = [1, 2, 3].map((step) => {
    const m = ((now - 1 + step) % 12) + 1
    const delta = ((byMonth.get(m)! - current) / current) * 100
    const sign = delta > 0.05 ? '+' : delta < -0.05 ? '−' : '±'
    return `${t('citizen.wait.inMonth')} ${names[m]} ${sign}${Math.abs(delta).toFixed(1)} %`
  })
  return parts.join(', ')
})

async function run() {
  busy.value = true
  error.value = null
  try {
    const body = { regionKato: region.value, profileCode: profile.value }
    const [p, a, idx] = await Promise.all([
      queue.predict(body),
      queue.alternatives({ ...body, limit: 3, includeNeighbors: includeNeighbors.value }),
      analytics.index(undefined, profile.value),
    ])
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
    <h1>{{ t('citizen.wait.title') }}</h1>
    <p class="lead">{{ t('citizen.wait.lead') }}</p>
    <div class="card">
      <div class="form-grid">
        <div class="field"><label>{{ t('common.region') }}</label><Select v-model="region" :options="refdata.regions" option-label="name" option-value="regionKato" filter /></div>
        <div class="field"><label>{{ t('common.profile') }}</label><Select v-model="profile" :options="refdata.profiles" option-label="name" option-value="profileCode" filter /></div>
      </div>
      <div class="field" style="display: flex; align-items: center; gap: 8px">
        <Checkbox v-model="includeNeighbors" binary input-id="includeNeighbors" @change="run" />
        <label for="includeNeighbors">{{ t('citizen.wait.includeNeighbors') }}</label>
      </div>
      <div class="actions"><Button :label="t('citizen.wait.findOut')" icon="pi pi-search" :loading="busy" @click="run" /></div>
      <ErrorBox :error="error" />
    </div>
    <div v-if="prediction" class="grid cols-2" style="margin-top: 16px">
      <div class="card">
        <h2>{{ t('citizen.wait.regionAverage') }} <OriginTag kind="ml" /></h2>
        <div class="kpi">
          <div class="item"><div class="value">{{ days(prediction.p50Days) }}</div><div class="label">{{ t('citizen.wait.p50Label') }}</div></div>
          <div class="item"><div class="value">{{ days(prediction.p90Days) }}</div><div class="label">{{ t('citizen.wait.p90Label') }}</div></div>
          <div class="item"><div class="value">{{ pct(prediction.pWithin30Days) }}</div><div class="label">{{ t('citizen.wait.within30') }}</div></div>
        </div>
        <p v-if="indexItem" class="muted" style="margin-top: 8px">{{ t('citizen.wait.indexInfo', { value: indexItem.indexValue.toFixed(1), rank: indexItem.rank }) }} <OriginTag kind="formula" /></p>
        <p v-else class="muted" style="margin-top: 8px">{{ t('citizen.wait.indexHidden') }}</p>
        <p v-if="seasonalHint" class="muted" style="margin-top: 8px">{{ t('citizen.wait.seasonalHint') }} {{ seasonalHint }} {{ t('citizen.wait.seasonalHintSuffix') }}</p>
      </div>
      <div class="card">
        <h2>{{ t('citizen.wait.whereFaster') }}</h2>
        <p v-if="!alternatives || alternatives.items.length === 0" class="muted">{{ t('citizen.wait.noOrganizations') }}</p>
        <div v-for="a in alternatives?.items ?? []" :key="a.mo.moCode" class="factor">
          <span>{{ a.mo.name }} <span v-if="a.isNeighborRegion" class="muted">({{ t('citizen.wait.neighborRegion', { region: refdata.regionName(a.mo.regionKato) }) }})</span></span>
          <span class="contribution">{{ days(a.p50Days) }} {{ t('common.days') }}</span>
        </div>
      </div>
    </div>
  </main>
</template>
