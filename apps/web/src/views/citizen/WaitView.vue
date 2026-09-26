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
import RouteAlternatives from '@/components/route/RouteAlternatives.vue'
import AppCard from '@/components/ui/AppCard.vue'
import CollapsibleSection from '@/components/ui/CollapsibleSection.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import HeroNumber from '@/components/ui/HeroNumber.vue'
import PageShell from '@/components/ui/PageShell.vue'
import SearchSelect from '@/components/ui/SearchSelect.vue'
import Skeleton from '@/components/ui/Skeleton.vue'
import { days, pct } from '@/lib/format'
import { readPref, WAIT_PREFS, writePref } from '@/lib/prefs'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'

/** Ожидание для граждан: слева липкая форма (регион, профиль, соседи), справа одно главное число, ориентир МЗ,
 * организации «где быстрее» и свёрнутое «как считается». Результат считается при выборе обоих полей, без кнопки. */
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
const isCitizen = computed(() => auth.hasRole('citizen'))

const heroSub = computed(() =>
  prediction.value ? `${t('hero.nineOfTen', { days: days(prediction.value.p90Days) })} · ${t('hero.within30', { pct: pct(prediction.value.pWithin30Days) })}` : '',
)

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
    const [p, a, idx] = await Promise.all([queue.predict(body), queue.alternatives({ ...body, limit: 3, includeNeighbors: includeNeighbors.value }), analytics.index(undefined, profile.value)])
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
    <div class="split">
      <aside class="sticky">
        <AppCard>
          <div class="form-col">
            <div class="field">
              <label>{{ t('common.region') }}</label>
              <SearchSelect v-model="region" :options="refdata.regions" option-label="name" option-value="regionKato" :placeholder="t('common.region')" />
            </div>
            <div class="field">
              <label>{{ t('common.profile') }}</label>
              <SearchSelect v-model="profile" :options="refdata.profiles" option-label="name" option-value="profileCode" :placeholder="t('common.profile')" />
            </div>
            <div class="field checkbox">
              <Checkbox v-model="includeNeighbors" binary input-id="includeNeighbors" />
              <label for="includeNeighbors">{{ t('citizen.wait.includeNeighbors') }}</label>
            </div>
          </div>
          <ErrorBox :error="error" />
        </AppCard>
      </aside>

      <div>
        <AppCard v-if="!ready"><EmptyState :title="t('citizen.wait.pickTitle')" :text="t('citizen.wait.pickText')" icon="pi pi-search" /></AppCard>
        <template v-else>
          <AppCard data-testid="wait-result">
            <HeroNumber
              :loading="busy && !prediction"
              :value="prediction ? `≈ ${days(prediction.p50Days)}` : '—'"
              :unit="t('common.days')"
              :label="t('hero.half')"
              :sub="heroSub"
              origin="ml"
            />
            <p v-if="target" class="muted benchmark">{{ t('route.benchmark', { days: days(target.value), source: target.source }) }} <OriginTag kind="formula" /></p>
          </AppCard>

          <AppCard :title="t('citizen.wait.whereFaster')" :origin="alternatives ? 'ml' : undefined" style="margin-top: 16px">
            <Skeleton v-if="busy && !alternatives" :lines="3" />
            <template v-else-if="!alternatives || alternatives.items.length === 0">
              <p class="muted">{{ t('citizen.wait.noOrganizations') }}</p>
              <p class="muted small">{{ t('citizen.wait.changeProfileHint') }}</p>
            </template>
            <RouteAlternatives
              v-else
              :items="alternatives.items"
              audience="citizen"
              :acting="requesting"
              :pending-code="requested"
              :action-label="isCitizen ? t('route.requestConsider') : undefined"
              @act="request"
            />
            <p v-if="!isCitizen && alternatives?.items.length" class="muted small" style="margin-top: 8px">{{ t('citizen.wait.loginToRequest') }}</p>
          </AppCard>

          <div style="margin-top: 16px">
            <CollapsibleSection :title="t('citizen.wait.howComputed')" :summary="indexItem ? t('citizen.wait.indexShort', { value: indexItem.indexValue.toFixed(0), rank: indexItem.rank }) : ''" origin="formula">
              <p v-if="indexItem" class="muted">{{ t('citizen.wait.indexInfo', { value: indexItem.indexValue.toFixed(1), rank: indexItem.rank }) }}</p>
              <p v-else-if="prediction" class="muted">{{ t('citizen.wait.indexHidden') }}</p>
              <p v-if="seasonalHint" class="muted">{{ t('citizen.wait.seasonalHint') }} {{ seasonalHint }} {{ t('citizen.wait.seasonalHintSuffix') }}</p>
              <p v-if="prediction" class="muted small">{{ t('explanationCard.model', { name: prediction.model.name, version: prediction.model.version, through: prediction.model.trainedThrough }) }}</p>
            </CollapsibleSection>
          </div>
        </template>
      </div>
    </div>
  </PageShell>
</template>

<style scoped>
.checkbox { flex-direction: row; align-items: center; gap: 8px; }
.checkbox label { font-size: 0.9rem; color: var(--dm-ink); }
.benchmark { margin: 12px 0 0; }
</style>
