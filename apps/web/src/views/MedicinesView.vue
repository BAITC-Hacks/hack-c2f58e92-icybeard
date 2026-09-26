<script setup lang="ts">
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
import KpiRow from '@/components/ui/KpiRow.vue'
import KpiTile from '@/components/ui/KpiTile.vue'
import PageShell from '@/components/ui/PageShell.vue'
import SearchSelect from '@/components/ui/SearchSelect.vue'
import Skeleton from '@/components/ui/Skeleton.vue'
import StatusTag from '@/components/ui/StatusTag.vue'
import { days, num, pct } from '@/lib/format'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'

/** Прогноз спроса (5.7 C) на потоке rx_weekly: gold.rx_weekly хранит region_kato как константу-заглушку
 * (build_rx_weekly в gold.py), потому что данные не разбиты по региону — ряд по факту общенациональный per-МНН.
 * Строка-заглушка должна совпадать с UNKNOWN из gold.py (сейчас — 'unknown'). */
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
  <PageShell :title="t('medicines.title')" :lead="t('medicines.lead')">
    <AppCard dense>
      <div class="searchbar" role="search">
        <div class="seg">
          <span class="seg-label">{{ t('medicines.nosology') }}</span>
          <SearchSelect v-model="nosologyId" :options="nosologies" :option-label="nosologyLabel" option-value="nosologyId" :option-title="nosologyTitle" :placeholder="t('medicines.nosology')" />
        </div>
        <div class="seg">
          <span class="seg-label">{{ t('medicines.mnn') }}</span>
          <SearchSelect v-model="mnnId" :options="mnns" :option-label="mnnLabel" option-value="mnnId" :option-title="mnnTitle" :placeholder="t('medicines.mnn')" :disabled="mnns.length === 0" />
        </div>
        <div class="seg">
          <span class="seg-label">{{ t('common.region') }}</span>
          <SearchSelect v-model="region" :options="refdata.regions" option-label="name" option-value="regionKato" show-clear :placeholder="t('medicines.wholeCountry')" />
        </div>
      </div>
      <ErrorBox :error="error" />
    </AppCard>

    <AppCard v-if="busy && !result" style="margin-top: 16px"><Skeleton kind="kpi" /><Skeleton :lines="3" style="margin-top: 12px" /></AppCard>
    <AppCard v-else-if="!result" style="margin-top: 16px"><EmptyState :title="t('medicines.pickMnn')" icon="pi pi-search" /></AppCard>
    <template v-else>
      <AppCard style="margin-top: 16px" origin="formula" :origin-note="t('medicines.coverageNote')" data-testid="rx-status">
        <template #header><span class="muted small">{{ result.basis }}</span></template>
        <div class="status-head">
          <StatusTag :value="result.covered ? t('medicines.covered') : t('medicines.notCovered')" :tone="result.covered ? 'ok' : 'warn'" :icon="result.covered ? 'pi pi-check' : 'pi pi-exclamation-triangle'" />
          <h2 class="status-title">{{ result.covered ? t('medicines.coveredBy', { program: result.program ?? '' }) : t('medicines.notCoveredTitle') }}</h2>
        </div>
        <p class="muted details">
          <template v-if="result.category">{{ t('medicines.category') }} {{ result.category }}</template>
          <template v-if="mnnId"> · {{ t('medicines.mnnShort', { id: mnnId }) }}</template>
          <template v-if="nosologyId"> · {{ t('medicines.nosologyShort', { id: nosologyId }) }}</template>
          <template v-if="region"> · {{ refdata.regionName(region) }}</template>
        </p>
        <h3 class="sub">{{ t('medicines.fillTiming') }}</h3>
        <KpiRow v-if="result.fillDaysP50 !== null || result.fillDaysP90 !== null || result.pFilled14d !== null">
          <KpiTile :value="days(result.fillDaysP50)" :label="`${t('medicines.median')}, ${t('common.days')}`" />
          <KpiTile :value="days(result.fillDaysP90)" :label="`p90, ${t('common.days')}`" />
          <KpiTile :value="pct(result.pFilled14d)" :label="t('medicines.within14')" />
        </KpiRow>
        <p v-else class="muted">{{ t('medicines.noTiming') }}</p>
        <p v-if="result.fillDaysP50Model !== null" class="muted small model-line">
          {{ t('medicines.modelP50') }}: <b class="tabular">{{ days(result.fillDaysP50Model) }} {{ t('common.days') }}</b> <OriginTag kind="ml" :note="t('medicines.modelP50Note')" />
        </p>
        <div class="shortage-line">
          <StatusTag :value="result.shortage.flag ? t('medicines.shortageFlag') : t('medicines.noShortageFlag')" :tone="result.shortage.flag ? 'danger' : 'ok'" />
          <span class="muted">{{ result.shortage.basis }}<template v-if="result.shortage.peerRatio !== null"> · {{ t('medicines.peerShortage') }}: {{ pct(result.shortage.peerRatio) }}</template></span>
        </div>
      </AppCard>

      <AppCard :title="t('medicines.otherMnn')" style="margin-top: 16px">
        <p v-if="result.alternatives.length === 0" class="muted">{{ t('common.empty') }}</p>
        <table v-else class="dense-table alt-table">
          <thead><tr><th>{{ t('medicines.mnn') }}</th><th class="num">{{ t('medicines.perYearCol') }}</th></tr></thead>
          <tbody>
            <tr v-for="a in result.alternatives" :key="a.mnnId" class="clickable" @click="mnnId = a.mnnId">
              <td>{{ a.name }}</td>
              <td class="num">{{ num(a.issued12m) }}</td>
            </tr>
          </tbody>
        </table>
        <p class="muted small" style="margin-top: 8px">{{ result.model.name }} {{ result.model.version }} · {{ t('medicines.dataThrough') }} {{ result.model.trainedThrough }} · {{ t('medicines.pharmaciesHint') }}</p>
      </AppCard>
    </template>

    <div v-if="canForecast" style="margin-top: 16px">
      <CollapsibleSection :title="t('medicines.demandForecast')" origin="ml" :summary="forecastMnnId ? t('medicines.mnnShort', { id: forecastMnnId }) : ''">
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
    </div>
  </PageShell>
</template>

<style scoped>
.searchbar { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 0; border: 1px solid var(--dm-hairline); border-radius: var(--dm-radius-md); overflow: hidden; }
.seg { padding: 8px 12px; border-right: 1px solid var(--dm-hairline); display: flex; flex-direction: column; gap: 2px; min-width: 0; }
.seg:last-child { border-right: 0; }
.seg-label { font-size: 0.75rem; color: var(--dm-muted); text-transform: uppercase; letter-spacing: 0.05em; }
.seg :deep(.p-select) { border: 0; box-shadow: none; padding-left: 0; background: transparent; }
.status-head { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
.status-title { margin: 0; font-size: 1.25rem; }
.details { margin: 4px 0 0; }
.sub { font-size: 0.95rem; margin: 16px 0 8px; }
.model-line { margin: 8px 0 0; }
.shortage-line { display: flex; align-items: center; gap: 10px; margin-top: 16px; flex-wrap: wrap; }
.alt-table { max-width: 560px; }
@media (max-width: 760px) { .searchbar { grid-template-columns: 1fr; } .seg { border-right: 0; border-bottom: 1px solid var(--dm-hairline); } .seg:last-child { border-bottom: 0; } }
</style>
