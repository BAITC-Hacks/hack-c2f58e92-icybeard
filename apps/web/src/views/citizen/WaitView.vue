<script setup lang="ts">
import Button from 'primevue/button'
import Checkbox from 'primevue/checkbox'
import { useToast } from 'primevue/usetoast'
import { computed, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute } from 'vue-router'
import { analytics, queue, refdata as refdataApi, route as routeApi } from '@/api/endpoints'
import type { AlternativesResponse, IndexItem, PredictResponse, RouteBenchmark, Seasonality } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import AppCard from '@/components/ui/AppCard.vue'
import CollapsibleSection from '@/components/ui/CollapsibleSection.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import HeroNumber from '@/components/ui/HeroNumber.vue'
import PageShell from '@/components/ui/PageShell.vue'
import SearchSelect from '@/components/ui/SearchSelect.vue'
import Skeleton from '@/components/ui/Skeleton.vue'
import StatusTag from '@/components/ui/StatusTag.vue'
import { days, pct, shortOrgName } from '@/lib/format'
import { dateShort } from '@/lib/route'
import { readPref, WAIT_PREFS, writePref } from '@/lib/prefs'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'

/** «Сколько ждут» (W-Wait): фильтры-пилюли (регион, профиль койки), слева hero-карточка «половина ждёт не дольше»,
 * справа «Где быстрее в регионе» — бары медианы по организациям (коралл — самое короткое ожидание); гражданин может
 * попросить врача рассмотреть организацию. Риск отказа гражданину не показывается. */
const { t } = useI18n()
const route = useRoute()
const auth = useAuthStore()
const toast = useToast()
const refdata = useRefdataStore()
const fromQuery = (name: string) => (typeof route.query[name] === 'string' && route.query[name] ? String(route.query[name]) : null)
// регион — из учётной записи, ссылки (?region=&profile=, в том числе с мобилки) или последнего выбора; ничего не зашито
const region = ref<string | null>(auth.region ?? fromQuery('region') ?? readPref(WAIT_PREFS.region))
const profile = ref<string | null>(fromQuery('profile') ?? readPref(WAIT_PREFS.profile))
const includeNeighbors = ref(false)
const prediction = ref<PredictResponse | null>(null)
const alternatives = ref<AlternativesResponse | null>(null)
const indexItem = ref<IndexItem | null>(null)
const target = ref<RouteBenchmark | null>(null)
const seasonality = ref<Seasonality[]>([])
const error = ref<unknown>(null)
const busy = ref(false)
const requesting = ref<string | null>(null)
const requested = ref<string | null>(null)
const ready = computed(() => !!region.value && !!profile.value)
const isCitizen = computed(() => auth.can('route.own'))
const asOf = computed(() => prediction.value?.model.trainedThrough ?? '')

/** Бары «где быстрее»: ширина — доля от самой длинной медианы, коралл — самое короткое ожидание. */
const bars = computed(() => {
  const items = alternatives.value?.items ?? []
  const max = Math.max(1, ...items.map((a) => a.p50Days))
  const min = Math.min(...items.map((a) => a.p50Days))
  return items.map((a) => ({ ...a, width: `${Math.max(2, (a.p50Days / max) * 100)}%`, shortest: a.p50Days === min }))
})

/** Сезонный ориентир: лист ожидания в ближайшие месяцы относительно текущего (форма NHS RTT). */
const seasonalHint = computed(() => {
  const wl = seasonality.value.filter((s) => s.seriesId === 'rtt_waiting_list')
  if (wl.length !== 12) return null
  const byMonth = new Map(wl.map((s) => [s.month, s.multiplier]))
  const now = new Date().getMonth() + 1
  const current = byMonth.get(now)
  if (!current) return null
  const names = t('citizen.wait.monthsIn').split(',')
  return [1, 2, 3]
    .map((step) => {
      const m = ((now - 1 + step) % 12) + 1
      const delta = ((byMonth.get(m)! - current) / current) * 100
      const sign = delta > 0.05 ? '+' : delta < -0.05 ? '−' : '±'
      return `${t('citizen.wait.inMonth')} ${names[m]} ${sign}${Math.abs(delta).toFixed(1)} %`
    })
    .join(', ')
})

let runId = 0
async function run() {
  if (!region.value || !profile.value) return
  const id = ++runId
  busy.value = true
  error.value = null
  writePref(WAIT_PREFS.region, region.value)
  writePref(WAIT_PREFS.profile, profile.value)
  try {
    const body = { regionKato: region.value, profileCode: profile.value }
    const [p, a, idx] = await Promise.all([queue.predict(body), queue.alternatives({ ...body, limit: 5, includeNeighbors: includeNeighbors.value }), analytics.index(undefined, profile.value)])
    if (id !== runId) return // выбор успели поменять
    prediction.value = p
    alternatives.value = a
    indexItem.value = idx.items.find((i) => i.regionKato === region.value) ?? null
  } catch (e) {
    if (id === runId) error.value = e
  } finally {
    if (id === runId) busy.value = false
  }
}

/** Вошедший гражданин: просьба рассмотреть организацию — сигнал по своему маршруту, врач увидит его в списке. */
async function request(moCode: string) {
  requesting.value = moCode
  try {
    await routeApi.signal({ kind: 'request_redirect', toMoCode: moCode }, crypto.randomUUID())
    requested.value = moCode
    toast.add({ severity: 'success', summary: t('route.requestSent'), life: 4000 })
  } catch (e) {
    error.value = e
  } finally {
    requesting.value = null
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
watch([region, profile, includeNeighbors], run)
</script>

<template>
  <PageShell :title="t('citizen.wait.title')" :lead="t('citizen.wait.lead')">
    <div class="filters">
      <label class="pill-select">
        <span class="pill-label">{{ t('common.region') }}</span>
        <SearchSelect v-model="region" :options="refdata.regions" option-label="name" option-value="regionKato" :placeholder="t('common.region')" />
      </label>
      <label class="pill-select">
        <span class="pill-label">{{ t('common.profile') }}</span>
        <SearchSelect v-model="profile" :options="refdata.profiles" option-label="name" option-value="profileCode" :placeholder="t('common.profile')" />
      </label>
      <div class="field checkbox">
        <Checkbox v-model="includeNeighbors" binary input-id="includeNeighbors" />
        <label for="includeNeighbors">{{ t('citizen.wait.includeNeighbors') }}</label>
      </div>
    </div>
    <ErrorBox :error="error" />

    <AppCard v-if="!ready"><EmptyState :title="t('citizen.wait.pickTitle')" :text="t('citizen.wait.pickText')" icon="pi pi-search" /></AppCard>
    <div v-else class="result-grid">
      <AppCard data-testid="wait-result">
        <HeroNumber
          :loading="busy && !prediction"
          :value="prediction ? `≈ ${days(prediction.p50Days)}` : '—'"
          :unit="t('common.days')"
          :caption="t('hero.half')"
          :label="prediction ? t('hero.nineOfTen', { days: days(prediction.p90Days) }) : ''"
          :sub="prediction ? t('hero.within30', { pct: pct(prediction.pWithin30Days) }) : ''"
          origin="ml"
        />
        <div class="notes">
          <span v-if="target">{{ t('route.benchmark', { days: days(target.value), source: target.source }) }}</span>
          <span>{{ t('citizen.wait.estimateNote') }}<template v-if="asOf"> · {{ t('shell.asOf', { date: dateShort(asOf) }) }}</template></span>
        </div>
      </AppCard>

      <AppCard :title="t('citizen.wait.whereFasterRegion')" data-testid="wait-alternatives">
        <template #header><span class="caption">{{ t('citizen.wait.medianDays') }}</span></template>
        <Skeleton v-if="busy && !alternatives" :lines="4" />
        <template v-else-if="!alternatives || alternatives.items.length === 0">
          <p class="muted">{{ t('citizen.wait.noOrganizations') }}</p>
          <p class="muted small">{{ t('citizen.wait.changeProfileHint') }}</p>
        </template>
        <div v-else class="bars tabular">
          <div v-for="a in bars" :key="a.mo.moCode" class="bar-row" :title="a.mo.name">
            <span class="bar-label">
              <span class="org">{{ shortOrgName(a.mo.name) }}</span>
              <span class="caption">{{ a.mo.moCode }}<template v-if="a.isNeighborRegion"> · {{ t('citizen.wait.neighborRegion', { region: refdata.regionName(a.mo.regionKato) }) }}</template></span>
            </span>
            <span class="track" aria-hidden="true"><span class="fill" :class="{ shortest: a.shortest }" :style="{ width: a.width }" /></span>
            <span class="bar-value" :class="{ shortest: a.shortest }">≈ {{ days(a.p50Days) }}</span>
            <span class="bar-action">
              <StatusTag v-if="requested === a.mo.moCode" :value="t('route.requestPending')" tone="accent" />
              <Button v-else-if="isCitizen" :label="t('route.requestConsider')" size="small" severity="secondary" :loading="requesting === a.mo.moCode" :disabled="requesting !== null" data-testid="request" @click="request(a.mo.moCode)" />
            </span>
          </div>
        </div>
        <div v-if="alternatives?.items.length" class="legend caption">
          <span class="legend-item"><span class="swatch accent" />{{ t('citizen.wait.legendShortest') }}</span>
          <span class="legend-item"><span class="swatch ink" />{{ t('citizen.wait.legendOthers') }}</span>
          <span class="spacer" />
          <span v-if="asOf">{{ t('shell.asOf', { date: dateShort(asOf) }) }}</span>
        </div>
        <p v-if="!isCitizen && alternatives?.items.length" class="muted small" style="margin: 8px 0 0">{{ t('citizen.wait.loginToRequest') }}</p>
      </AppCard>
    </div>

    <CollapsibleSection v-if="ready" :title="t('citizen.wait.howComputed')" :summary="indexItem ? t('citizen.wait.indexShort', { value: indexItem.indexValue.toFixed(0), rank: indexItem.rank }) : ''" origin="formula">
      <p v-if="indexItem" class="muted">{{ t('citizen.wait.indexInfo', { value: indexItem.indexValue.toFixed(1), rank: indexItem.rank }) }}</p>
      <p v-else-if="prediction" class="muted">{{ t('citizen.wait.indexHidden') }}</p>
      <p v-if="seasonalHint" class="muted">{{ t('citizen.wait.seasonalHint') }} {{ seasonalHint }} {{ t('citizen.wait.seasonalHintSuffix') }}</p>
      <p v-if="prediction" class="muted small">{{ t('explanationCard.model', { name: prediction.model.name, version: prediction.model.version, through: prediction.model.trainedThrough }) }}</p>
    </CollapsibleSection>
  </PageShell>
</template>

<style scoped>
.filters { display: flex; align-items: center; gap: 12px; flex-wrap: wrap; }
.pill-select { display: inline-flex; align-items: center; gap: 4px; background: var(--dm-surface); border-radius: var(--dm-radius-pill); padding: 0 6px 0 20px; min-height: 44px; }
.pill-label { font-size: var(--dm-text-sm); color: var(--dm-muted); white-space: nowrap; }
.pill-select :deep(.p-select) { background: transparent; min-height: 40px; min-width: 200px; font-weight: 500; font-size: var(--dm-text-sm); }
.pill-select :deep(.p-select:focus-within) { outline: 0; box-shadow: none; }
.result-grid { display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1.6fr); gap: var(--dm-space-4); align-items: start; }
.notes { border-top: 1px solid var(--dm-hairline); padding-top: 12px; margin-top: 12px; display: flex; flex-direction: column; gap: 6px; font-size: 13px; color: var(--dm-muted); }
.bars { display: flex; flex-direction: column; gap: 12px; font-size: var(--dm-text-sm); }
.bar-row { display: grid; grid-template-columns: 220px minmax(0, 1fr) 56px auto; align-items: center; gap: 12px; }
.bar-label { display: flex; flex-direction: column; min-width: 0; }
.org { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.track { height: 28px; border-radius: 4px; background: var(--dm-surface-2); overflow: hidden; }
.fill { display: block; height: 100%; background: var(--dm-map-3); border-radius: 4px; }
.fill.shortest { background: var(--dm-primary); }
.bar-value { text-align: right; font-weight: 500; white-space: nowrap; }
.bar-value.shortest { color: var(--dm-danger); }
.bar-action { min-width: 0; display: flex; justify-content: flex-end; }
.legend { display: flex; align-items: center; gap: 16px; margin-top: 14px; flex-wrap: wrap; }
.legend-item { display: inline-flex; align-items: center; gap: 6px; }
.swatch { width: 12px; height: 12px; border-radius: 3px; display: inline-block; }
.swatch.accent { background: var(--dm-primary); }
.swatch.ink { background: var(--dm-map-3); }
.spacer { flex: 1; }
@media (max-width: 900px) { .result-grid { grid-template-columns: 1fr; } .bar-row { grid-template-columns: 1fr 56px; } .track { grid-column: 1 / -1; } .bar-action { grid-column: 1 / -1; justify-content: flex-start; } }
</style>
