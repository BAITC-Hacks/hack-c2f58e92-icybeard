<script setup lang="ts">
import Checkbox from 'primevue/checkbox'
import { useToast } from 'primevue/usetoast'
import { computed, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute } from 'vue-router'
import { analytics, queue, refdata as refdataApi, route as routeApi } from '@/api/endpoints'
import type { AlternativesResponse, IndexItem, PredictResponse, RouteBenchmark, Seasonality } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import OriginTag from '@/components/OriginTag.vue'
import AppCard from '@/components/ui/AppCard.vue'
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

/** «Сколько ждать» (wait-new): фильтры-пилюли (регион, профиль койки) и чекбокс соседних регионов; во всю ширину
 * hero-карточка «половина ждёт не дольше» с нормативом МЗ и датой данных; ниже «Где быстрее в регионе» — бары 10px
 * (самое короткое — --accent, остальные --bar-neutral), цифра зелёная, если короче медианы региона; гражданин может
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
const indexTotal = ref(0)
const target = ref<RouteBenchmark | null>(null)
const seasonality = ref<Seasonality[]>([])
const error = ref<unknown>(null)
const busy = ref(false)
const requesting = ref<string | null>(null)
const requested = ref<string | null>(null)
const howOpen = ref(false)
const ready = computed(() => !!region.value && !!profile.value)
const isCitizen = computed(() => auth.can('route.own'))
const asOf = computed(() => prediction.value?.model.trainedThrough ?? '')

/** Бары «где быстрее»: срок читается по длине полосы (доля от самого долгого ожидания в списке), цвет у всех один;
 * «на N дн. быстрее, чем в среднем по региону» — словами, если больница короче медианы региона. */
const bars = computed(() => {
  const items = alternatives.value?.items ?? []
  const max = Math.max(1, ...items.map((a) => a.p50Days))
  const baseline = prediction.value?.p50Days ?? null
  return items.map((a) => {
    // разница — по округлённым дням, которые видит человек
    const d = baseline !== null ? Math.round(baseline) - Math.round(a.p50Days) : null
    const compare = d === null ? '' : d > 0 ? t('citizen.wait.fasterThanAvg', { days: d }) : d < 0 ? t('citizen.wait.slowerThanAvg', { days: -d }) : t('citizen.wait.sameAsAvg')
    return { ...a, width: `${Math.max(3, (a.p50Days / max) * 100)}%`, fasterBy: d !== null && d > 0 ? d : 0, compare }
  })
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
    indexTotal.value = idx.items.length
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
      <div class="field checkbox neighbors">
        <Checkbox v-model="includeNeighbors" binary input-id="includeNeighbors" />
        <label for="includeNeighbors">{{ t('citizen.wait.includeNeighbors') }}</label>
      </div>
    </div>
    <ErrorBox :error="error" />

    <AppCard v-if="!ready"><EmptyState :title="t('citizen.wait.pickTitle')" :text="t('citizen.wait.pickText')" icon="pi pi-search" /></AppCard>
    <template v-else>
      <AppCard :title="t('citizen.wait.regionAverage')" label origin="ml" data-testid="wait-result">
        <HeroNumber
          :loading="busy && !prediction"
          :value="prediction ? `≈ ${days(prediction.p50Days)}` : '—'"
          :unit="t('common.days')"
          :label="t('citizen.wait.heroLead')"
          :sub="prediction ? [t('citizen.wait.heroNine', { days: days(prediction.p90Days) }), t('citizen.wait.heroWithin30', { pct: pct(prediction.pWithin30Days) })].join('\n') : ''"
          label-first
        />
        <div class="hero-foot">
          <span v-if="target" class="benchmark">
            <span class="benchmark-text">{{ t('route.citizen.benchmark', { days: days(target.value) }) }} <OriginTag kind="formula" /></span>
            <details class="source">
              <summary>{{ t('route.citizen.sourceToggle') }} <i class="pi pi-chevron-down" aria-hidden="true" /></summary>
              <span class="caption">{{ t('route.citizen.benchmarkSource', { source: target.source }) }}</span>
            </details>
          </span>
          <span class="spacer" />
          <span class="caption">{{ t('citizen.wait.estimateNote') }}<template v-if="asOf"> · {{ t('shell.asOf', { date: dateShort(asOf) }) }}</template></span>
        </div>
      </AppCard>

      <AppCard :title="t('citizen.wait.whereFasterRegion')" label data-testid="wait-alternatives">
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
            <span class="track" aria-hidden="true"><span class="fill" :style="{ width: a.width }" /></span>
            <span class="bar-value" :class="{ faster: a.fasterBy }">
              <span class="bar-lead">{{ t('citizen.wait.columnHalf') }}</span>
              <span class="bar-days">≈ {{ days(a.p50Days) }} <span class="bar-unit">{{ t('common.days') }}</span></span>
              <span v-if="a.compare" class="bar-faster">{{ a.compare }}</span>
            </span>
            <span class="bar-action">
              <StatusTag v-if="requested === a.mo.moCode" :value="t('route.requestPending')" tone="accent" />
              <button v-else-if="isCitizen" type="button" class="ghost-link" :disabled="requesting !== null" data-testid="request" @click="request(a.mo.moCode)">
                <i v-if="requesting === a.mo.moCode" class="pi pi-spinner pi-spin" aria-hidden="true" /> {{ t('route.requestConsider') }}
              </button>
            </span>
          </div>
        </div>
        <div class="legend caption">
          <button type="button" class="how-toggle" :aria-expanded="howOpen" aria-controls="wait-how" data-testid="wait-how-toggle" @click="howOpen = !howOpen">
            {{ t('citizen.wait.howComputed') }}<template v-if="indexItem"> · {{ t('citizen.wait.indexSummary', { rank: indexItem.rank, total: indexTotal }) }}</template>
            <i class="pi" :class="howOpen ? 'pi-chevron-up' : 'pi-chevron-down'" aria-hidden="true" />
          </button>
          <OriginTag kind="formula" />
          <span class="spacer" />
          <span v-if="asOf">{{ t('shell.asOf', { date: dateShort(asOf) }) }}</span>
        </div>
        <div v-show="howOpen" id="wait-how" class="how">
          <p>{{ t('citizen.wait.howIntro') }}</p>
          <p>{{ t('citizen.wait.indexExplain') }}</p>
          <p v-if="indexItem" class="how-here">{{ t('citizen.wait.indexHere', { region: refdata.regionName(region ?? ''), value: indexItem.indexValue.toFixed(0), rank: indexItem.rank, total: indexTotal, share: pct(indexItem.shareOver30), p90: days(indexItem.p90Days) }) }}</p>
          <p v-else-if="prediction" class="muted">{{ t('citizen.wait.indexHiddenPlain') }}</p>
          <p v-if="seasonalHint" class="muted">{{ t('citizen.wait.seasonalPlain') }} {{ seasonalHint }}. {{ t('citizen.wait.seasonalPlainSuffix') }}</p>
        </div>
        <p v-if="!isCitizen && alternatives?.items.length" class="muted small login-hint">{{ t('citizen.wait.loginToRequest') }}</p>
      </AppCard>
    </template>

  </PageShell>
</template>

<style scoped>
/* карточки гражданина: padding 24/26 (wait-new) */
.card { padding: 24px 26px; }
.filters { display: flex; align-items: center; gap: 14px; flex-wrap: wrap; }
/* поле-пилюля 44px с рамкой 1.5 --border (field-pill) */
.pill-select { display: inline-flex; align-items: center; gap: 4px; background: var(--surface); border: 1.5px solid var(--border); border-radius: var(--radius-xl); padding: 0 6px 0 18px; min-height: 44px; box-sizing: border-box; }
.pill-label { font-size: var(--fs-base); color: var(--text-secondary); white-space: nowrap; }
.pill-select :deep(.p-select) { background: transparent; border: 0; min-height: 40px; min-width: 200px; font-weight: var(--fw-extrabold); font-size: var(--fs-base); }
.pill-select :deep(.p-select.p-focus) { box-shadow: none; }
.neighbors { padding: 0 6px; }
.neighbors label { font-weight: var(--fw-bold); font-size: var(--fs-md); }
.hero-foot { border-top: 1px solid var(--surface-muted); padding-top: 12px; margin-top: 14px; display: flex; align-items: baseline; gap: 12px; flex-wrap: wrap; }
.hero-foot .spacer { flex: 1; }
.benchmark { display: flex; flex-direction: column; gap: 4px; }
.source summary { display: inline-flex; align-items: center; gap: 6px; font-size: var(--fs-sm); color: var(--text-muted); cursor: pointer; list-style: none; }
.source summary::-webkit-details-marker { display: none; }
.source summary i { font-size: 0.6rem; transition: transform .15s; }
.source[open] summary i { transform: rotate(180deg); }
.source .caption { display: block; margin-top: 4px; }
.benchmark-text { font-size: var(--fs-base); font-weight: var(--fw-semibold); }
.faster-lead { margin: -4px 0 8px; line-height: 1.45; }
.how { display: flex; flex-direction: column; gap: 10px; margin-top: 12px; padding: 16px 18px; border-radius: var(--radius-lg); background: var(--surface-hover); font-size: var(--fs-base); color: var(--text); }
.how-toggle { display: inline-flex; align-items: center; gap: 8px; border: 0; background: none; padding: 0; font: inherit; font-size: var(--fs-base); font-weight: var(--fw-bold); color: var(--link); cursor: pointer; }
.how-toggle:hover { color: var(--accent-strong); }
.how-toggle i { font-size: 0.7rem; }
.legend :deep(.origin) { margin-left: 4px; }
.how p { margin: 0; line-height: 1.55; }
.how-here { font-weight: var(--fw-semibold); }
/* бары: трек 10px, лучшая — accent, остальные — bar-neutral; цифра зелёная — короче медианы региона */
.bars { display: flex; flex-direction: column; }
.bar-row { display: grid; grid-template-columns: minmax(220px, 1.1fr) minmax(0, 1fr) 200px 170px; align-items: center; gap: 18px; padding: 14px 0; border-bottom: 1px solid var(--border); }
.bar-lead { font-size: var(--fs-xs); color: var(--text-muted); line-height: 1.3; }
.bar-row:last-child { border-bottom: 0; }
.bar-label { display: flex; flex-direction: column; min-width: 0; }
.org { font-size: var(--fs-base); font-weight: var(--fw-bold); line-height: 1.35; overflow-wrap: anywhere; }
.track { height: 10px; border-radius: 5px; background: var(--surface-muted); overflow: hidden; }
.fill { display: block; height: 100%; background: var(--accent); opacity: .75; border-radius: 5px; }
.bar-value { display: flex; flex-direction: column; align-items: flex-end; text-align: right; gap: 2px; }
.bar-days { font-size: var(--fs-md); font-weight: var(--fw-extrabold); white-space: nowrap; }
.bar-unit { font-size: var(--fs-sm); font-weight: var(--fw-bold); color: var(--text-muted); }
.bar-faster { font-size: var(--fs-sm); color: var(--text-muted); line-height: 1.3; }
.bar-value.faster .bar-days { color: var(--success-text); }
.bar-action { min-width: 0; display: flex; justify-content: flex-end; }
.ghost-link { border: 0; background: none; padding: 0; font: inherit; font-size: var(--fs-base-sm); font-weight: var(--fw-bold); color: var(--link); cursor: pointer; white-space: nowrap; }
.ghost-link:hover:not(:disabled) { color: var(--accent-strong); }
.ghost-link:disabled { opacity: 0.45; cursor: default; }
.ghost-link i { font-size: 0.7rem; }
.legend { display: flex; align-items: center; gap: 16px; margin-top: 12px; padding-top: 12px; border-top: 1px solid var(--border); flex-wrap: wrap; }
.spacer { flex: 1; }
.login-hint { margin: 8px 0 0; }
@media (max-width: 900px) { .bar-row { grid-template-columns: 1fr auto; } .track { grid-column: 1 / -1; } .bar-action { grid-column: 1 / -1; justify-content: flex-start; } }
</style>
