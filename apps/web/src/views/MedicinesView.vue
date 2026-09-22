<script setup lang="ts">
import Button from 'primevue/button'
import Select from 'primevue/select'
import { onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { ApiError } from '@/api/client'
import { analytics, medicines } from '@/api/endpoints'
import type { CheckResponse, ForecastResponse, Mnn, Nosology } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import OriginTag from '@/components/OriginTag.vue'
import SeriesChart from '@/components/SeriesChart.vue'
import AppCard from '@/components/ui/AppCard.vue'
import KpiRow from '@/components/ui/KpiRow.vue'
import KpiTile from '@/components/ui/KpiTile.vue'
import PageShell from '@/components/ui/PageShell.vue'
import Section from '@/components/ui/Section.vue'
import Skeleton from '@/components/ui/Skeleton.vue'
import StatusTag from '@/components/ui/StatusTag.vue'
import { days, num, pct } from '@/lib/format'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'

/** Прогноз спроса (5.7 C) на потоке rx_weekly: gold.rx_weekly хранит region_kato как константу-заглушку
 * (build_rx_weekly в gold.py), потому что данные не разбиты по региону — это делает ряд по факту общенациональным
 * per-МНН, и forecast() уже работает сегодня без нового ML/бэкенда. Строка-заглушка region_kato должна совпадать
 * с UNKNOWN из gold.py (сейчас — 'unknown'). */
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

const topMnns = ref<Mnn[]>([])
const forecastMnnId = ref<string | null>(null)
const forecast = ref<ForecastResponse | null>(null)
const forecastHint = ref<string | null>(null)
const forecastBusy = ref(false)
const forecastError = ref<unknown>(null)

async function loadMnn() {
  if (!nosologyId.value) return
  mnns.value = (await medicines.mnn(nosologyId.value)).items
  mnnId.value = mnns.value[0]?.mnnId ?? null
}

async function check() {
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
  if (!forecastMnnId.value) return
  // /forecast/{streamId} открыт главврачу и регулятору: гостю и врачу вместо 401/403 — подпись, кому доступен прогноз
  if (!auth.hasRole('chief', 'regulator')) {
    forecast.value = null
    forecastError.value = null
    forecastHint.value = t('medicines.demandForecastForRoles')
    return
  }
  forecastBusy.value = true
  forecastError.value = null
  forecast.value = null
  forecastHint.value = null
  try {
    forecast.value = await analytics.forecast('rx_weekly', { region_kato: FORECAST_REGION_PLACEHOLDER, drug_mnn_id: forecastMnnId.value }, FORECAST_HORIZON)
  } catch (e) {
    if (e instanceof ApiError && e.status === 404) {
      forecastHint.value = t('medicines.demandForecastNotBuilt')
    } else {
      forecastError.value = e
    }
  } finally {
    forecastBusy.value = false
  }
}

onMounted(async () => {
  await refdata.load()
  try {
    nosologies.value = (await medicines.nosologies()).items
    nosologyId.value = nosologies.value[0]?.nosologyId ?? null
    await loadMnn()
    await check()
    topMnns.value = (await medicines.topMnn(50)).items
    forecastMnnId.value = topMnns.value[0]?.mnnId ?? null
    await loadDemandForecast()
  } catch (e) {
    error.value = e
  }
})
watch(nosologyId, loadMnn)
watch(forecastMnnId, loadDemandForecast)
</script>

<template>
  <PageShell :title="t('medicines.title')" :lead="t('medicines.lead')">
    <AppCard>
      <div class="form-grid">
        <div class="field"><label>{{ t('medicines.nosology') }}</label><Select v-model="nosologyId" :options="nosologies" option-value="nosologyId" filter :option-label="(n: Nosology) => t('medicines.nosologyOption', { id: n.nosologyId, count: num(n.issued12m) })" /></div>
        <div class="field"><label>{{ t('medicines.mnn') }}</label><Select v-model="mnnId" :options="mnns" option-value="mnnId" filter :option-label="(m: Mnn) => t('medicines.mnnOption', { id: m.mnnId, count: num(m.issued12m) })" /></div>
        <div class="field"><label>{{ t('common.region') }}</label><Select v-model="region" :options="refdata.regions" option-label="name" option-value="regionKato" filter show-clear :placeholder="t('common.region')" /></div>
      </div>
      <div class="actions"><Button :label="t('medicines.check')" icon="pi pi-check-circle" :loading="busy" @click="check" /></div>
      <ErrorBox :error="error" />
    </AppCard>
    <Section v-if="busy && !result" :cols="2"><AppCard><Skeleton kind="kpi" /></AppCard><AppCard><Skeleton :lines="4" /></AppCard></Section>
    <Section v-if="result" :cols="2">
      <AppCard :title="t('medicines.coverage')" origin="formula" :origin-note="t('medicines.coverageNote')">
        <p>
          <StatusTag :value="result.covered ? t('medicines.covered') : t('medicines.notCovered')" :tone="result.covered ? 'ok' : 'warn'" />
          <span v-if="result.program"> {{ result.program }}, {{ t('medicines.category') }} {{ result.category }}</span>
        </p>
        <h2 style="margin-top: 16px">{{ t('medicines.fillTiming') }}</h2>
        <KpiRow>
          <KpiTile :value="days(result.fillDaysP50)" :label="`${t('medicines.median')}, ${t('common.days')}`" />
          <KpiTile :value="days(result.fillDaysP90)" :label="`p90, ${t('common.days')}`" />
          <KpiTile :value="pct(result.pFilled14d)" :label="t('medicines.within14')" />
        </KpiRow>
        <p class="muted">{{ result.basis }}</p>
        <p v-if="result.fillDaysP50Model !== null" class="muted">
          {{ t('medicines.modelP50') }}: <strong class="tabular">{{ days(result.fillDaysP50Model) }} {{ t('common.days') }}</strong> <OriginTag kind="ml" :note="t('medicines.modelP50Note')" />
        </p>
      </AppCard>
      <AppCard :title="t('medicines.shortage')">
        <p>
          <StatusTag :value="result.shortage.flag ? t('medicines.shortageFlag') : t('medicines.noShortageFlag')" :tone="result.shortage.flag ? 'danger' : 'ok'" />
          {{ t('medicines.score') }} {{ result.shortage.score.toFixed(2) }}
        </p>
        <p class="muted">{{ result.shortage.basis }}</p>
        <p v-if="result.shortage.peerRatio !== null" class="muted">{{ t('medicines.peerShortage') }}: {{ pct(result.shortage.peerRatio) }} · {{ result.shortage.peerBasis }}</p>
        <h2 style="margin-top: 16px">{{ t('medicines.otherMnn') }}</h2>
        <p v-if="result.alternatives.length === 0" class="muted">{{ t('common.empty') }}</p>
        <div v-for="a in result.alternatives" :key="a.mnnId" class="factor"><span>{{ a.name }}</span><span class="contribution">{{ num(a.issued12m) }} / {{ t('medicines.perYear') }}</span></div>
        <p class="muted" style="margin-top: 8px">{{ t('medicines.pharmaciesHint') }} {{ result.model.name }} {{ result.model.version }}, {{ t('medicines.dataThrough') }} {{ result.model.trainedThrough }}.</p>
      </AppCard>
    </Section>
    <Section :cols="1">
      <AppCard :title="t('medicines.demandForecast')" origin="ml">
        <p class="lead">{{ t('medicines.demandForecastLead') }}</p>
        <div class="form-grid">
          <div class="field">
            <label>{{ t('medicines.topMnn') }}</label>
            <Select v-model="forecastMnnId" :options="topMnns" option-value="mnnId" filter :option-label="(m: Mnn) => t('medicines.mnnOption', { id: m.mnnId, count: num(m.issued12m) })" />
          </div>
        </div>
        <ErrorBox :error="forecastError" />
        <SeriesChart v-if="forecast" :history="forecast.history" :points="forecast.points" :title="t('medicines.demandForecast')" />
        <Skeleton v-else-if="forecastBusy" kind="chart" />
        <p v-else-if="forecastHint" class="muted">{{ forecastHint }}</p>
        <p v-if="forecast" class="muted">
          {{ t('gov.map.backtest') }}: sMAPE {{ pct(forecast.backtest.smape, 1) }} {{ t('gov.map.vsNaive') }} {{ pct(forecast.backtest.baselineSmape, 1) }}, MASE {{ forecast.backtest.mase.toFixed(2) }}.
          {{ forecast.model.name }} {{ forecast.model.version }}.
        </p>
      </AppCard>
    </Section>
  </PageShell>
</template>
