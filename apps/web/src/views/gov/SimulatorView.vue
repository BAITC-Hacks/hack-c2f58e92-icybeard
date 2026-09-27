<script setup lang="ts">
import Button from 'primevue/button'
import InputNumber from 'primevue/inputnumber'
import Slider from 'primevue/slider'
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute } from 'vue-router'
import { analytics, simulation } from '@/api/endpoints'
import type { LosItem, RedistributeResponse, SimulateResponse } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import BeforeAfterChart from '@/components/gov/BeforeAfterChart.vue'
import AppCard from '@/components/ui/AppCard.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import HeroNumber from '@/components/ui/HeroNumber.vue'
import PageShell from '@/components/ui/PageShell.vue'
import SearchSelect from '@/components/ui/SearchSelect.vue'
import Skeleton from '@/components/ui/Skeleton.vue'
import { useLocaleFormat } from '@/composables/useLocaleFormat'
import { days, shortOrgName, signed } from '@/lib/format'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'

/** Симулятор: слайдеры с числовым полем рядом, результат «было → станет» одной большой парой с дельтой,
 * график «до / после» с интервалом чувствительности, перераспределение — ранжированный список переносов. */
interface Control { key: 'capacity' | 'redirect' | 'horizon' | 'maxShare' | 'beds'; min: number; max: number; step: number; suffix: string }
const CONTROLS: Control[] = [
  { key: 'capacity', min: -30, max: 60, step: 1, suffix: '%' },
  { key: 'redirect', min: 0, max: 50, step: 1, suffix: '%' },
  { key: 'horizon', min: 30, max: 180, step: 30, suffix: '' },
  { key: 'maxShare', min: 5, max: 50, step: 5, suffix: '%' },
  { key: 'beds', min: 0, max: 100, step: 5, suffix: '' },
]

const { t } = useI18n()
const { num } = useLocaleFormat()
const refdata = useRefdataStore()
const auth = useAuthStore()
const route = useRoute()
// регион — из ссылки или учётной записи, профиль — только из ссылки; без обоих расчёт не запускается
const region = ref<string | null>(typeof route.query.region === 'string' ? route.query.region : (auth.region ?? null))
const profile = ref<string | null>(typeof route.query.profile === 'string' ? route.query.profile : null)
const scenario = ref({ capacity: 15, redirect: 0, horizon: 90, maxShare: 20, beds: 0 })
const result = ref<SimulateResponse | null>(null)
const moves = ref<RedistributeResponse | null>(null)
const los = ref<LosItem | null>(null)
const error = ref<unknown>(null)
const busy = ref(false)

const delta = computed(() => result.value?.deltaDays ?? 0)
const interval = computed<[number, number]>(() => {
  const r = result.value
  return r ? [r.scenario.meanWaitDays + (r.ci[0] ?? 0) - r.deltaDays, r.scenario.meanWaitDays + (r.ci[1] ?? 0) - r.deltaDays] : [0, 0]
})
const controlLabel = (key: Control['key']) => (key === 'horizon' ? `${t('gov.simulator.horizon')}, ${t('common.days')}` : t(`gov.simulator.${key}`))

async function run() {
  const regionKato = region.value
  const profileCode = profile.value
  if (!regionKato || !profileCode) return
  busy.value = true
  error.value = null
  const s = scenario.value
  try {
    ;[result.value, moves.value] = await Promise.all([
      simulation.simulate(regionKato, profileCode, { capacityDeltaPct: s.capacity, redistributeSharePct: s.redirect, horizonDays: s.horizon, bedsDelta: s.beds }),
      simulation.redistribute(regionKato, profileCode, { maxShareMovedPct: s.maxShare, horizonDays: s.horizon }),
    ])
    // длительность лечения — отдельная витрина; её отсутствие не должно ломать расчёт
    los.value = (await analytics.los(regionKato, profileCode)).items[0] ?? null
  } catch (e) {
    if (result.value === null) error.value = e
  } finally {
    busy.value = false
  }
}

onMounted(async () => {
  await refdata.load()
  // автозапуск только по ссылке с региона/организации; иначе регулятор выбирает сам
  if (typeof route.query.region === 'string' && typeof route.query.profile === 'string') await run()
})
</script>

<template>
  <PageShell :title="t('gov.simulator.title')" :lead="t('gov.simulator.lead')">
    <div class="split">
      <AppCard :title="t('gov.simulator.scenario')" class="sticky">
        <div class="form-col">
          <div class="field"><label>{{ t('common.region') }}</label><SearchSelect v-model="region" :options="refdata.regions" option-label="name" option-value="regionKato" :placeholder="t('common.region')" /></div>
          <div class="field"><label>{{ t('common.profile') }}</label><SearchSelect v-model="profile" :options="refdata.profiles" option-label="name" option-value="profileCode" :placeholder="t('common.profile')" /></div>
          <div v-for="c in CONTROLS" :key="c.key" class="field control">
            <label>{{ controlLabel(c.key) }}</label>
            <div class="control-row">
              <Slider v-model="scenario[c.key]" :min="c.min" :max="c.max" :step="c.step" class="slider" />
              <InputNumber v-model="scenario[c.key]" :min="c.min" :max="c.max" :step="c.step" :suffix="c.suffix ? ` ${c.suffix}` : undefined" size="small" show-buttons button-layout="stacked" input-class="num-input" />
            </div>
          </div>
        </div>
        <div class="actions"><Button :label="t('common.apply')" icon="pi pi-play" :loading="busy" :disabled="!region || !profile" data-testid="simulate-run" @click="run" /></div>
        <ErrorBox :error="error" />
      </AppCard>

      <div>
        <AppCard v-if="busy && !result"><Skeleton kind="kpi" /><Skeleton kind="chart" style="margin-top: 12px" /></AppCard>
        <AppCard v-else-if="!result"><EmptyState :title="t('gov.simulator.pickTitle')" icon="pi pi-sliders-h" /></AppCard>
        <template v-else>
          <AppCard :title="`${t('gov.simulator.resultFor')} ${result.organisations} ${t('gov.simulator.organisations')}`" origin="formula" data-testid="simulate-result">
            <div class="pair-row">
              <HeroNumber :value="days(result.baseline.meanWaitDays, 1)" :unit="t('common.days')" :label="t('gov.simulator.before')" compact />
              <i class="pi pi-arrow-right arrow" aria-hidden="true" />
              <HeroNumber :value="days(result.scenario.meanWaitDays, 1)" :unit="t('common.days')" :label="t('gov.simulator.after')" compact :tone="delta < 0 ? 'ok' : delta > 0 ? 'danger' : undefined" />
              <div class="delta" :class="delta < 0 ? 'delta-down' : delta > 0 ? 'delta-up' : ''">
                <div class="delta-value tabular">{{ signed(delta) }} {{ t('common.days') }}</div>
                <div class="muted small">{{ t('gov.simulator.sensitivity') }}: {{ signed(result.ci[0] ?? 0) }} … {{ signed(result.ci[1] ?? 0) }}</div>
                <div v-if="result.admissionsPerDay !== null" class="muted small">{{ num(result.admissionsPerDay, 1) }} {{ t('gov.simulator.admissionsPerDayShort') }}</div>
              </div>
            </div>
            <BeforeAfterChart :before="result.baseline.meanWaitDays" :after="result.scenario.meanWaitDays" :interval="interval" />
            <ul class="muted small assumptions"><li v-for="a in result.assumptions" :key="a">{{ a }}</li></ul>
            <p v-if="los && los.losMedianFact > 0" class="muted small">
              {{ t('gov.simulator.losIntro') }}: {{ los.losMedianFact.toFixed(1) }} {{ t('common.days') }} ({{ t('gov.simulator.losMedianCaveat') }}, {{ num(los.n) }} {{ t('gov.simulator.cases') }}<template v-if="los.losP50Model !== null">; p50 LOS: {{ los.losP50Model.toFixed(1) }} {{ t('common.days') }}</template>) —
              {{ t('gov.simulator.oneBed') }} ≈ {{ (1 / los.losMedianFact).toFixed(2) }} {{ t('gov.simulator.admissionsPerDayShort') }}<template v-if="scenario.beds > 0">, {{ t('gov.simulator.soBedsDelta') }} +{{ scenario.beds }} {{ t('gov.simulator.bedsUnit') }} ≈ +{{ (scenario.beds / los.losMedianFact).toFixed(2) }} {{ t('gov.simulator.admissionsPerDayShort') }}</template>.
            </p>
            <p v-else-if="scenario.beds > 0" class="muted small">{{ t('gov.simulator.losMissing', { beds: scenario.beds }) }}</p>
            <!-- значения и источники: refdata/external_benchmarks.yaml (beds) -->
            <p class="muted small">{{ result.model.name }} {{ result.model.version }} · {{ t('gov.simulator.bedsBenchmark') }}</p>
          </AppCard>

          <AppCard v-if="moves" :title="t('gov.simulator.redistributeTitle', { moves: moves.moves.length, days: num(-moves.totalDeltaDays), horizon: moves.horizonDays })" origin="formula">
            <p v-if="moves.moves.length === 0" class="muted">{{ t('gov.simulator.noMoves') }}</p>
            <div v-else class="rows">
              <div v-for="(m, i) in moves.moves" :key="m.fromMo.moCode + m.toMo.moCode" class="row">
                <div class="row-main">
                  <span class="muted">{{ i + 1 }}.</span>
                  <span :title="m.fromMo.name">{{ shortOrgName(m.fromMo.name) }}</span> → <span :title="m.toMo.name">{{ shortOrgName(m.toMo.name) }}</span>
                  <div class="row-sub">
                    {{ t('gov.simulator.share') }} {{ m.sharePct.toFixed(0) }} % · {{ t('gov.simulator.waitAtSource') }} {{ days(m.waitFromBefore) }} → {{ days(m.waitFromAfter) }} · {{ t('gov.simulator.waitAtDestination') }} {{ days(m.waitToBefore) }} → {{ days(m.waitToAfter) }}
                  </div>
                </div>
                <div class="row-value" :class="m.waitFromAfter < m.waitFromBefore ? 'delta-down' : ''">{{ signed(m.waitFromAfter - m.waitFromBefore, 0) }} {{ t('common.days') }}</div>
              </div>
            </div>
          </AppCard>
        </template>
      </div>
    </div>
  </PageShell>
</template>

<style scoped>
.control-row { display: grid; grid-template-columns: 1fr 120px; gap: 10px; align-items: center; }
.slider { margin: 0 6px; }
.control :deep(.num-input) { width: 100%; text-align: right; }
.pair-row { display: flex; align-items: center; gap: var(--dm-space-4); flex-wrap: wrap; margin-bottom: 12px; }
.arrow { font-size: 1.4rem; color: var(--dm-danger); }
.delta-value { font-size: var(--dm-text-xl); font-weight: 500; letter-spacing: -0.01em; }
.assumptions { margin: 12px 0 0; padding-left: 18px; }
</style>
