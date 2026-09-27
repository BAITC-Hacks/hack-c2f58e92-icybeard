<script setup lang="ts">
import Button from 'primevue/button'
import { onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { ApiError } from '@/api/client'
import { analytics, medicines } from '@/api/endpoints'
import type { CheckResponse, ForecastResponse, Mnn, Nosology } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import OriginTag from '@/components/OriginTag.vue'
import SeriesChart from '@/components/SeriesChart.vue'
import AppCard from '@/components/ui/AppCard.vue'
import CollapsibleSection from '@/components/ui/CollapsibleSection.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import PageShell from '@/components/ui/PageShell.vue'
import SearchSelect from '@/components/ui/SearchSelect.vue'
import Skeleton from '@/components/ui/Skeleton.vue'
import StatusTag from '@/components/ui/StatusTag.vue'
import { days, num, pct } from '@/lib/format'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'

/** «Проверка рецепта» (W-Medicines): поля нозологии и МНН на soft, регион пилюлей, «Проверить»; слева карточка
 * результата (МНН крупно, чип покрытия, строки сроков, «Как считается»), справа «Другие МНН при этой нозологии».
 * Прогноз спроса (5.7 C) на потоке rx_weekly — главврачу и регулятору, свёрнутой секцией. gold.rx_weekly хранит
 * region_kato как константу-заглушку (build_rx_weekly в gold.py), потому что данные не разбиты по региону. */
const FORECAST_REGION_PLACEHOLDER = 'unknown'
const FORECAST_HORIZON = 8

const { t } = useI18n()
const refdata = useRefdataStore()
const auth = useAuthStore()
const nosologies = ref<Nosology[]>([])
const mnns = ref<Mnn[]>([])
const nosologyId = ref<string | null>(null)
const mnnId = ref<string | null>(null)
// регион — из учётной записи; без него проверка идёт по стране
const region = ref<string | null>(auth.region ?? null)
const result = ref<CheckResponse | null>(null)
const error = ref<unknown>(null)
const busy = ref(false)
const canForecast = auth.hasRole('chief', 'regulator')

const topMnns = ref<Mnn[]>([])
const forecastMnnId = ref<string | null>(null)
const forecast = ref<ForecastResponse | null>(null)
const forecastHint = ref<string | null>(null)
const forecastBusy = ref(false)
const forecastError = ref<unknown>(null)

const nosologyLabel = (n: Nosology) => t('medicines.nosologyShort', { id: n.nosologyId })
const nosologyTitle = (n: Nosology) => t('medicines.nosologyOption', { id: n.nosologyId, count: num(n.issued12m) })
const mnnLabel = (m: Mnn) => t('medicines.mnnShort', { id: m.mnnId })
const mnnTitle = (m: Mnn) => t('medicines.mnnOption', { id: m.mnnId, count: num(m.issued12m) })

async function loadMnn() {
  if (!nosologyId.value) return
  mnns.value = (await medicines.mnn(nosologyId.value)).items
  silentMnn = true // первый МНН подставляется без повторной проверки: check() вызывается явно
  mnnId.value = mnns.value[0]?.mnnId ?? null
}

async function check() {
  if (!nosologyId.value && !mnnId.value) {
    result.value = null
    return
  }
  busy.value = true
  error.value = null
  try {
    result.value = await medicines.check({ mnnId: mnnId.value, nosologyId: nosologyId.value, regionKato: region.value })
  } catch (e) {
    error.value = e
    result.value = null
  } finally {
    busy.value = false
  }
}

async function loadDemandForecast() {
  if (!forecastMnnId.value || !canForecast) return
  forecastBusy.value = true
  forecastError.value = null
  forecast.value = null
  forecastHint.value = null
  try {
    forecast.value = await analytics.forecast('rx_weekly', { region_kato: FORECAST_REGION_PLACEHOLDER, drug_mnn_id: forecastMnnId.value }, FORECAST_HORIZON)
  } catch (e) {
    if (e instanceof ApiError && e.status === 404) forecastHint.value = t('medicines.demandForecastNotBuilt')
    else forecastError.value = e
  } finally {
    forecastBusy.value = false
  }
}

onMounted(async () => {
  await refdata.load()
  try {
    nosologies.value = (await medicines.nosologies()).items
    silentNosology = true
    nosologyId.value = nosologies.value[0]?.nosologyId ?? null
    await loadMnn()
    await check()
    if (canForecast) {
      topMnns.value = (await medicines.topMnn(50)).items
      forecastMnnId.value = topMnns.value[0]?.mnnId ?? null
      await loadDemandForecast()
    }
  } catch (e) {
    error.value = e
  }
})
let silentNosology = false
let silentMnn = false
watch(nosologyId, async () => {
  if (silentNosology) {
    silentNosology = false
    return
  }
  await loadMnn()
  await check()
})
watch([mnnId, region], () => {
  if (silentMnn) {
    silentMnn = false
    return
  }
  check()
})
watch(forecastMnnId, loadDemandForecast)
</script>

<template>
  <PageShell :title="t('medicines.title')" :lead="t('medicines.leadShort')">
    <div class="searchbar" role="search">
      <div class="field">
        <label>{{ t('medicines.nosology') }}</label>
        <SearchSelect v-model="nosologyId" :options="nosologies" :option-label="nosologyLabel" option-value="nosologyId" :option-title="nosologyTitle" :placeholder="t('medicines.nosology')" />
      </div>
      <div class="field">
        <label>{{ t('medicines.mnn') }}</label>
        <SearchSelect v-model="mnnId" :options="mnns" :option-label="mnnLabel" option-value="mnnId" :option-title="mnnTitle" :placeholder="t('medicines.mnn')" :disabled="mnns.length === 0" />
      </div>
      <label class="pill-select">
        <span class="pill-label">{{ t('common.region') }}</span>
        <SearchSelect v-model="region" :options="refdata.regions" option-label="name" option-value="regionKato" show-clear :placeholder="t('medicines.wholeCountry')" />
      </label>
      <Button :label="t('medicines.check')" :loading="busy" :disabled="!nosologyId && !mnnId" @click="check" />
    </div>
    <ErrorBox :error="error" />

    <AppCard v-if="busy && !result"><Skeleton kind="kpi" /><Skeleton :lines="3" style="margin-top: 12px" /></AppCard>
    <AppCard v-else-if="!result"><EmptyState :title="t('medicines.pickMnn')" icon="pi pi-search" /></AppCard>
    <div v-else class="result-grid">
      <AppCard data-testid="rx-status">
        <div class="status-head">
          <span class="mnn-title">{{ mnnId ? t('medicines.mnnShort', { id: mnnId }) : t('medicines.nosologyShort', { id: nosologyId ?? '' }) }}</span>
          <StatusTag :value="result.covered ? t('medicines.covered') : t('medicines.notCovered')" :tone="result.covered ? 'ok' : 'warn'" />
          <span class="spacer" />
          <OriginTag :kind="result.fillDaysP50Model !== null ? 'ml' : 'formula'" :note="t('medicines.coverageNote')" />
        </div>
        <p class="muted small details">
          {{ result.covered ? t('medicines.coveredBy', { program: result.program ?? '' }) : t('medicines.notCoveredTitle') }}
          <template v-if="result.category"> · {{ t('medicines.category') }} {{ result.category }}</template>
          <template v-if="nosologyId"> · {{ t('medicines.nosologyShort', { id: nosologyId }).toLowerCase() }}</template>
          <template v-if="region"> · {{ refdata.regionName(region) }}</template>
        </p>
        <div class="rows">
          <div class="row"><span class="row-main muted">{{ t('home.rxMedian') }}</span><span class="row-value strong">{{ result.fillDaysP50 !== null ? `${days(result.fillDaysP50)} ${t('common.days')}` : '—' }}</span></div>
          <div class="row"><span class="row-main muted">{{ t('home.rxNineOfTen') }}</span><span class="row-value strong">{{ result.fillDaysP90 !== null ? t('home.rxUpTo', { days: days(result.fillDaysP90) }) : '—' }}</span></div>
          <div class="row"><span class="row-main muted">{{ t('medicines.within14Row') }}</span><span class="row-value strong">{{ pct(result.pFilled14d) }}</span></div>
          <div v-if="result.fillDaysP50Model !== null" class="row"><span class="row-main muted">{{ t('medicines.modelP50') }} <OriginTag kind="ml" :note="t('medicines.modelP50Note')" /></span><span class="row-value strong">{{ days(result.fillDaysP50Model) }} {{ t('common.days') }}</span></div>
          <div class="row">
            <span class="row-main muted">{{ t('medicines.shortage') }}</span>
            <span class="row-value">
              <span v-if="result.shortage.peerRatio !== null" class="caption">{{ t('medicines.peerShortage') }} {{ pct(result.shortage.peerRatio) }}</span>
              <StatusTag :value="result.shortage.flag ? t('medicines.shortageFlag') : t('medicines.noShortageFlag')" :tone="result.shortage.flag ? 'danger' : 'ok'" />
            </span>
          </div>
        </div>
        <div class="how">
          <span class="how-title">{{ t('citizen.wait.howComputed') }}</span>
          <span>{{ t('medicines.howComputed', { model: result.model.name, version: result.model.version, through: result.model.trainedThrough }) }} {{ result.basis }}<template v-if="result.shortage.basis"> · {{ result.shortage.basis }}</template></span>
        </div>
      </AppCard>

      <AppCard :title="t('medicines.otherMnn')">
        <p v-if="result.alternatives.length === 0" class="muted">{{ t('common.empty') }}</p>
        <div v-else class="rows">
          <button v-for="a in result.alternatives" :key="a.mnnId" type="button" class="row row-button" @click="mnnId = a.mnnId">
            <span class="row-main">{{ a.name }}</span>
            <span class="row-value muted small">{{ num(a.issued12m) }} {{ t('medicines.perYearCol') }}</span>
          </button>
        </div>
        <p class="caption" style="margin: 12px 0 0">{{ t('medicines.pharmaciesHint') }}</p>
      </AppCard>
    </div>

    <CollapsibleSection v-if="canForecast" :title="t('medicines.demandForecast')" origin="ml" :summary="forecastMnnId ? t('medicines.mnnShort', { id: forecastMnnId }) : ''">
      <p class="muted small">{{ t('medicines.demandForecastLead') }}</p>
      <div class="field" style="max-width: 360px">
        <label>{{ t('medicines.topMnn') }}</label>
        <SearchSelect v-model="forecastMnnId" :options="topMnns" :option-label="mnnLabel" option-value="mnnId" :option-title="mnnTitle" />
      </div>
      <ErrorBox :error="forecastError" />
      <SeriesChart v-if="forecast" :history="forecast.history" :points="forecast.points" :title="t('medicines.demandForecast')" />
      <Skeleton v-else-if="forecastBusy" kind="chart" />
      <p v-else-if="forecastHint" class="muted">{{ forecastHint }}</p>
      <p v-if="forecast" class="muted small">
        {{ t('gov.map.backtest') }}: sMAPE {{ pct(forecast.backtest.smape, 1) }} {{ t('gov.map.vsNaive') }} {{ pct(forecast.backtest.baselineSmape, 1) }}, MASE {{ forecast.backtest.mase.toFixed(2) }}. {{ forecast.model.name }} {{ forecast.model.version }}.
      </p>
    </CollapsibleSection>
  </PageShell>
</template>

<style scoped>
.searchbar { display: flex; align-items: flex-end; gap: 12px; flex-wrap: wrap; }
.searchbar .field { flex: 1 1 240px; max-width: 360px; }
.pill-select { display: inline-flex; align-items: center; gap: 4px; background: var(--dm-surface); border-radius: var(--dm-radius-pill); padding: 0 6px 0 20px; min-height: 44px; }
.pill-label { font-size: var(--dm-text-sm); color: var(--dm-muted); white-space: nowrap; }
.pill-select :deep(.p-select) { background: transparent; min-height: 40px; min-width: 180px; font-weight: 500; font-size: var(--dm-text-sm); }
.result-grid { display: grid; grid-template-columns: minmax(0, 1.4fr) minmax(0, 1fr); gap: var(--dm-space-4); align-items: start; }
.status-head { display: flex; align-items: center; gap: 12px; flex-wrap: wrap; }
.mnn-title { font-size: var(--dm-text-xl); font-weight: 500; letter-spacing: -0.01em; }
.spacer { flex: 1; }
.details { margin: 4px 0 8px; }
.strong { font-weight: 500; font-size: var(--dm-text-base); }
.how { border-top: 1px solid var(--dm-hairline); margin-top: 8px; padding-top: 14px; display: flex; flex-direction: column; gap: 4px; font-size: 13px; color: var(--dm-faint); }
.how-title { font-weight: 500; color: var(--dm-ink); }
.row-button { width: 100%; background: none; border: 0; border-bottom: 1px solid var(--dm-hairline); font: inherit; color: inherit; text-align: left; cursor: pointer; padding: 12px 0; }
.row-button:last-child { border-bottom: 0; }
.row-button:hover .row-main { color: var(--dm-accent-hover); }
@media (max-width: 900px) { .result-grid { grid-template-columns: 1fr; } }
</style>
