<script setup lang="ts">
import Button from 'primevue/button'
import Checkbox from 'primevue/checkbox'
import Select from 'primevue/select'
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute } from 'vue-router'
import { analytics, queue, refdata as refdataApi } from '@/api/endpoints'
import type { AlternativesResponse, IndexItem, PredictResponse, RouteBenchmark, Seasonality } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import OriginTag from '@/components/OriginTag.vue'
import AppCard from '@/components/ui/AppCard.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import KpiRow from '@/components/ui/KpiRow.vue'
import KpiTile from '@/components/ui/KpiTile.vue'
import PageShell from '@/components/ui/PageShell.vue'
import Section from '@/components/ui/Section.vue'
import Skeleton from '@/components/ui/Skeleton.vue'
import { days, pct } from '@/lib/format'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'

const STORAGE = { region: 'darumen.wait.region', profile: 'darumen.wait.profile' }
function remembered(key: string): string | null {
  try {
    return localStorage.getItem(key)
  } catch {
    return null
  }
}
function remember(key: string, value: string) {
  try {
    localStorage.setItem(key, value)
  } catch {
    // приватный режим: выбор живёт до перезагрузки
  }
}

const { t } = useI18n()
const route = useRoute()
const auth = useAuthStore()
const refdata = useRefdataStore()
const fromQuery = (name: string) => (typeof route.query[name] === 'string' && route.query[name] ? String(route.query[name]) : null)
// регион — из учётной записи, ссылки (?region=&profile=, в том числе с мобилки) или последнего выбора; ничего не зашито
const region = ref<string | null>(auth.region ?? fromQuery('region') ?? remembered(STORAGE.region))
const profile = ref<string | null>(fromQuery('profile') ?? remembered(STORAGE.profile))
const prediction = ref<PredictResponse | null>(null)
const alternatives = ref<AlternativesResponse | null>(null)
const indexItem = ref<IndexItem | null>(null)
const target = ref<RouteBenchmark | null>(null)
const error = ref<unknown>(null)
const busy = ref(false)
const asked = ref(false)
const seasonality = ref<Seasonality[]>([])
const includeNeighbors = ref(false)
const ready = computed(() => !!region.value && !!profile.value)

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
  if (!region.value || !profile.value) return
  asked.value = true
  busy.value = true
  error.value = null
  remember(STORAGE.region, region.value)
  remember(STORAGE.profile, profile.value)
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
  if (ready.value) await run()
  try {
    seasonality.value = (await refdataApi.seasonality()).items
  } catch {
    seasonality.value = [] // без витрины сезонности страница работает как раньше
  }
  try {
    target.value = (await refdataApi.routeStandard()).benchmarks.find((b) => b.code === 'moh_target_wait_days') ?? null
  } catch {
    target.value = null // ориентир МЗ РК — из справочника, без него строка просто не показывается
  }
})
</script>

<template>
  <PageShell :title="t('citizen.wait.title')" :lead="t('citizen.wait.lead')">
    <AppCard>
      <div class="form-grid">
        <div class="field"><label>{{ t('common.region') }}</label><Select v-model="region" :options="refdata.regions" option-label="name" option-value="regionKato" filter :placeholder="t('common.region')" /></div>
        <div class="field"><label>{{ t('common.profile') }}</label><Select v-model="profile" :options="refdata.profiles" option-label="name" option-value="profileCode" filter :placeholder="t('common.profile')" /></div>
      </div>
      <div class="field" style="display: flex; align-items: center; gap: 8px">
        <Checkbox v-model="includeNeighbors" binary input-id="includeNeighbors" @change="run" />
        <label for="includeNeighbors">{{ t('citizen.wait.includeNeighbors') }}</label>
      </div>
      <div class="actions"><Button :label="t('citizen.wait.findOut')" icon="pi pi-search" :loading="busy" :disabled="!ready" data-testid="wait-run" @click="run" /></div>
      <ErrorBox :error="error" />
    </AppCard>
    <EmptyState v-if="!asked" :title="t('citizen.wait.pickTitle')" :text="t('citizen.wait.pickText')" icon="pi pi-search" />
    <Section v-else :cols="2">
      <AppCard :title="t('citizen.wait.regionAverage')" origin="ml">
        <KpiRow>
          <KpiTile :loading="busy && !prediction" :value="days(prediction?.p50Days)" :label="t('citizen.wait.p50Label')" />
          <KpiTile :loading="busy && !prediction" :value="days(prediction?.p90Days)" :label="t('citizen.wait.p90Label')" />
          <KpiTile :loading="busy && !prediction" :value="pct(prediction?.pWithin30Days)" :label="t('citizen.wait.within30')" />
        </KpiRow>
        <p v-if="target" class="muted" style="margin-top: 8px">{{ t('route.benchmark', { days: days(target.value), source: target.source }) }} <OriginTag kind="formula" /></p>
        <p v-if="indexItem" class="muted" style="margin-top: 8px">{{ t('citizen.wait.indexInfo', { value: indexItem.indexValue.toFixed(1), rank: indexItem.rank }) }} <OriginTag kind="formula" /></p>
        <p v-else-if="prediction" class="muted" style="margin-top: 8px">{{ t('citizen.wait.indexHidden') }}</p>
        <p v-if="seasonalHint" class="muted" style="margin-top: 8px">{{ t('citizen.wait.seasonalHint') }} {{ seasonalHint }} {{ t('citizen.wait.seasonalHintSuffix') }}</p>
      </AppCard>
      <AppCard :title="t('citizen.wait.whereFaster')" :origin="alternatives ? 'ml' : undefined">
        <Skeleton v-if="busy && !alternatives" :lines="3" />
        <p v-else-if="!alternatives || alternatives.items.length === 0" class="muted">{{ t('citizen.wait.noOrganizations') }}</p>
        <div v-for="a in alternatives?.items ?? []" :key="a.mo.moCode" class="factor">
          <span>{{ a.mo.name }} <span v-if="a.isNeighborRegion" class="muted">({{ t('citizen.wait.neighborRegion', { region: refdata.regionName(a.mo.regionKato) }) }})</span></span>
          <span class="contribution">{{ days(a.p50Days) }} {{ t('common.days') }}</span>
        </div>
      </AppCard>
    </Section>
  </PageShell>
</template>
