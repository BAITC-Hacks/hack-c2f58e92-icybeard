<script setup lang="ts">
import Button from 'primevue/button'
import InputNumber from 'primevue/inputnumber'
import Slider from 'primevue/slider'
import { useToast } from 'primevue/usetoast'
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute } from 'vue-router'
import { analytics, journal, simulation } from '@/api/endpoints'
import type { LosItem, RedistributeResponse, SimulateResponse } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import BeforeAfterChart from '@/components/gov/BeforeAfterChart.vue'
import AppCard from '@/components/ui/AppCard.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import PageShell from '@/components/ui/PageShell.vue'
import SearchSelect from '@/components/ui/SearchSelect.vue'
import Skeleton from '@/components/ui/Skeleton.vue'
import { useLocaleFormat } from '@/composables/useLocaleFormat'
import { downloadCsv } from '@/lib/csv'
import { days, shortOrgName, signed } from '@/lib/format'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'

/** Симулятор «что если» (W-Simulator): горизонт пилюлями 4·8·12 недель; слева «Рычаги сценария» (регион, профиль,
 * доля переноса, мощность, +N коек, максимум от одной организации) и «Рассчитать»; справа «До и после» — пара
 * «сейчас → сценарий» по медиане региона, график, четыре карточки (пропускная способность; p90, «ждут дольше 20»,
 * простой коек — их нет в открытых данных, так и подписаны), «Эффект по организациям» из /redistribute с сохранением
 * сценария в журнал решений и экспортом CSV. */
interface Control { key: 'capacity' | 'redirect' | 'maxShare' | 'beds'; min: number; max: number; step: number; suffix: string }
const CONTROLS: Control[] = [
  { key: 'redirect', min: 0, max: 50, step: 1, suffix: '%' },
  { key: 'capacity', min: -30, max: 60, step: 1, suffix: '%' },
  { key: 'beds', min: 0, max: 100, step: 5, suffix: '' },
  { key: 'maxShare', min: 5, max: 50, step: 5, suffix: '%' },
]
const HORIZONS = [4, 8, 12] as const
const SUBJECT_SCENARIO = 'scenario'

const { t } = useI18n()
const { num } = useLocaleFormat()
const refdata = useRefdataStore()
const auth = useAuthStore()
const route = useRoute()
const toast = useToast()
// регион — из ссылки или учётной записи, профиль — только из ссылки; без обоих расчёт не запускается
const region = ref<string | null>(typeof route.query.region === 'string' ? route.query.region : (auth.region ?? null))
const profile = ref<string | null>(typeof route.query.profile === 'string' ? route.query.profile : null)
const weeks = ref<(typeof HORIZONS)[number]>(12)
const scenario = ref({ capacity: 15, redirect: 20, maxShare: 20, beds: 0 })
const result = ref<SimulateResponse | null>(null)
const moves = ref<RedistributeResponse | null>(null)
const los = ref<LosItem | null>(null)
const error = ref<unknown>(null)
const busy = ref(false)
const saving = ref(false)
const savedId = ref<string | null>(null)

const horizonDays = computed(() => weeks.value * 7)
const delta = computed(() => result.value?.deltaDays ?? 0)
const interval = computed<[number, number]>(() => {
  const r = result.value
  return r ? [r.scenario.meanWaitDays + (r.ci[0] ?? 0) - r.deltaDays, r.scenario.meanWaitDays + (r.ci[1] ?? 0) - r.deltaDays] : [0, 0]
})
const deltaText = computed(() => (delta.value < 0 ? t('gov.simulator.lessBy', { days: days(-delta.value, 1) }) : delta.value > 0 ? t('gov.simulator.moreBy', { days: days(delta.value, 1) }) : t('gov.simulator.noChange')))
const controlLabel = (key: Control['key']) => t(`gov.simulator.${key}`)

async function run() {
  const regionKato = region.value
  const profileCode = profile.value
  if (!regionKato || !profileCode) return
  busy.value = true
  error.value = null
  savedId.value = null
  const s = scenario.value
  try {
    ;[result.value, moves.value] = await Promise.all([
      simulation.simulate(regionKato, profileCode, { capacityDeltaPct: s.capacity, redistributeSharePct: s.redirect, horizonDays: horizonDays.value, bedsDelta: s.beds }),
      simulation.redistribute(regionKato, profileCode, { maxShareMovedPct: s.maxShare, horizonDays: horizonDays.value }),
    ])
    // длительность лечения — отдельная витрина; её отсутствие не должно ломать расчёт
    los.value = (await analytics.los(regionKato, profileCode)).items[0] ?? null
  } catch (e) {
    if (result.value === null) error.value = e
  } finally {
    busy.value = false
  }
}

/** Сценарий в журнал решений: рычаги и результат без персональных данных; рекомендация = сценарий, выбор = сценарий. */
async function saveScenario() {
  if (!result.value || !region.value || !profile.value || savedId.value) return
  saving.value = true
  try {
    const payload = { region: region.value, profile: profile.value, horizonDays: horizonDays.value, ...scenario.value, meanWaitBefore: result.value.baseline.meanWaitDays, meanWaitAfter: result.value.scenario.meanWaitDays }
    const created = await journal.record(
      { subject: SUBJECT_SCENARIO, subjectId: `${region.value}:${profile.value}:${new Date().toISOString().slice(0, 10)}`, recommended: payload, chosen: payload, reason: t('gov.simulator.subjectScenario') },
      crypto.randomUUID(),
    )
    savedId.value = created.decisionId
    toast.add({ severity: 'success', summary: t('gov.simulator.saved'), life: 3000 })
  } catch (e) {
    error.value = e
  } finally {
    saving.value = false
  }
}

function exportCsv() {
  if (!moves.value) return
  downloadCsv(
    'scenario-moves.csv',
    moves.value.moves.map((m) => ({ from: m.fromMo.moCode, fromName: m.fromMo.name, to: m.toMo.moCode, toName: m.toMo.name, sharePct: m.sharePct, arrivalsPerDay: m.arrivalsPerDay, waitFromBefore: m.waitFromBefore, waitFromAfter: m.waitFromAfter, waitToBefore: m.waitToBefore, waitToAfter: m.waitToAfter })),
  )
}

onMounted(async () => {
  await refdata.load()
  // автозапуск только по ссылке с региона/организации; иначе регулятор выбирает сам
  if (typeof route.query.region === 'string' && typeof route.query.profile === 'string') await run()
})
</script>

<template>
  <PageShell :title="t('gov.simulator.titleWhatIf')">
    <template #subtitle>
      <template v-if="region">{{ refdata.regionName(region) }} · </template><template v-if="profile">{{ refdata.profileName(profile).toLowerCase() }} · </template>{{ t('gov.simulator.humanDecides') }}
    </template>
    <template #actions>
      <div class="chips"><button v-for="w in HORIZONS" :key="w" type="button" class="chip-filter" :class="{ active: weeks === w }" @click="weeks = w">{{ t('gov.simulator.horizonWeeks', { weeks: w }) }}</button></div>
    </template>
    <ErrorBox :error="error" />

    <div class="split">
      <AppCard :title="t('gov.simulator.levers')" label class="sticky levers">
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
        <div class="actions"><Button :label="t('common.apply')" :loading="busy" :disabled="!region || !profile" data-testid="simulate-run" @click="run" /></div>
        <p class="caption">{{ t('gov.simulator.leversNote') }}</p>
      </AppCard>

      <div class="col">
        <AppCard v-if="busy && !result"><Skeleton kind="kpi" /><Skeleton kind="chart" style="margin-top: 12px" /></AppCard>
        <AppCard v-else-if="!result"><EmptyState :title="t('gov.simulator.pickTitle')" icon="pi pi-sliders-h" /></AppCard>
        <template v-else>
          <AppCard :title="t('gov.simulator.beforeAfter', { weeks })" origin="formula" data-testid="simulate-result">
            <template #header><span class="caption">{{ t('gov.simulator.regionMedianDays') }}</span></template>
            <div class="pair-block tabular">
              <div class="pair"><span class="big">{{ days(result.baseline.meanWaitDays, 1) }}</span><span class="caption">{{ t('gov.simulator.now') }}</span></div>
              <span class="arrow" aria-hidden="true">→</span>
              <div class="pair"><span class="big" :class="delta < 0 ? 'delta-down' : delta > 0 ? 'delta-up' : ''">{{ days(result.scenario.meanWaitDays, 1) }}</span><span class="caption">{{ t('gov.simulator.scenarioShare', { share: scenario.redirect }) }}</span></div>
            </div>
            <p class="delta-text" :class="delta < 0 ? 'delta-down' : delta > 0 ? 'delta-up' : ''">{{ deltaText }}</p>
            <p class="muted small">{{ t('gov.simulator.sensitivity') }}: {{ signed(result.ci[0] ?? 0) }} … {{ signed(result.ci[1] ?? 0) }} {{ t('common.days') }} · {{ result.organisations }} {{ t('gov.simulator.organisations') }}</p>
            <BeforeAfterChart :before="result.baseline.meanWaitDays" :after="result.scenario.meanWaitDays" :interval="interval" />
            <div class="mini-grid tabular">
              <div class="mini"><span class="mini-value">{{ result.admissionsPerDay !== null ? `${num(result.admissionsPerDay, 1)} ${t('gov.simulator.perDayShort')}` : '—' }}</span><span class="caption">{{ t('gov.simulator.throughputScenario') }}</span></div>
              <div class="mini"><span class="mini-value muted">{{ t('gov.simulator.notInOpenData') }}</span><span class="caption">{{ t('gov.simulator.p90Region') }}</span></div>
              <div class="mini"><span class="mini-value muted">{{ t('gov.simulator.notInOpenData') }}</span><span class="caption">{{ t('gov.simulator.over20') }}</span></div>
              <div class="mini"><span class="mini-value muted">{{ t('gov.simulator.notInOpenData') }}</span><span class="caption">{{ t('gov.simulator.bedIdle') }}</span></div>
            </div>
            <ul class="caption assumptions"><li v-for="a in result.assumptions" :key="a">{{ a }}</li></ul>
            <p v-if="los && los.losMedianFact > 0" class="caption">
              {{ t('gov.simulator.losIntro') }}: {{ los.losMedianFact.toFixed(1) }} {{ t('common.days') }} ({{ t('gov.simulator.losMedianCaveat') }}, {{ num(los.n) }} {{ t('gov.simulator.cases') }}<template v-if="los.losP50Model !== null">; p50 LOS: {{ los.losP50Model.toFixed(1) }} {{ t('common.days') }}</template>) —
              {{ t('gov.simulator.oneBed') }} ≈ {{ (1 / los.losMedianFact).toFixed(2) }} {{ t('gov.simulator.admissionsPerDayShort') }}<template v-if="scenario.beds > 0">, {{ t('gov.simulator.soBedsDelta') }} +{{ scenario.beds }} {{ t('gov.simulator.bedsUnit') }} ≈ +{{ (scenario.beds / los.losMedianFact).toFixed(2) }} {{ t('gov.simulator.admissionsPerDayShort') }}</template>.
            </p>
            <p v-else-if="scenario.beds > 0" class="caption">{{ t('gov.simulator.losMissing', { beds: scenario.beds }) }}</p>
            <!-- значения и источники: refdata/external_benchmarks.yaml (beds) -->
            <p class="caption">{{ t('gov.simulator.aggregateNote') }} {{ result.model.name }} {{ result.model.version }} · {{ t('gov.simulator.bedsBenchmark') }}</p>
          </AppCard>

          <AppCard v-if="moves" :title="t('gov.simulator.orgEffect')" origin="formula">
            <template #header><span class="caption">{{ t('gov.simulator.redistributeTitle', { moves: moves.moves.length, days: num(-moves.totalDeltaDays), horizon: moves.horizonDays }) }}</span></template>
            <p v-if="moves.moves.length === 0" class="muted">{{ t('gov.simulator.noMoves') }}</p>
            <div v-else class="table-wrap">
              <table class="dense-table">
                <thead><tr><th>{{ t('gov.simulator.colFrom') }}</th><th>{{ t('gov.simulator.colTo') }}</th><th class="num">{{ t('gov.simulator.colShare') }}</th><th class="num">{{ t('gov.simulator.colSource') }}</th><th class="num">{{ t('gov.simulator.colTarget') }}</th><th class="num">Δ</th></tr></thead>
                <tbody>
                  <tr v-for="m in moves.moves" :key="m.fromMo.moCode + m.toMo.moCode">
                    <td class="clip" :title="m.fromMo.name">{{ shortOrgName(m.fromMo.name) }} <span class="muted">· {{ m.fromMo.moCode }}</span></td>
                    <td class="clip" :title="m.toMo.name">{{ shortOrgName(m.toMo.name) }} <span class="muted">· {{ m.toMo.moCode }}</span></td>
                    <td class="num">{{ m.sharePct.toFixed(0) }} %</td>
                    <td class="num">{{ days(m.waitFromBefore) }} → {{ days(m.waitFromAfter) }}</td>
                    <td class="num">{{ days(m.waitToBefore) }} → {{ days(m.waitToAfter) }}</td>
                    <td class="num" :class="m.waitFromAfter < m.waitFromBefore ? 'delta-down' : 'delta-up'">{{ signed(m.waitFromAfter - m.waitFromBefore, 0) }} {{ t('common.days') }}</td>
                  </tr>
                </tbody>
              </table>
            </div>
            <div class="save-row">
              <Button :label="savedId ? t('gov.simulator.saved') : t('gov.simulator.saveScenario')" :disabled="!!savedId" :loading="saving" data-testid="scenario-save" @click="saveScenario" />
              <button type="button" class="link-arrow small" :disabled="!moves.moves.length" @click="exportCsv">{{ t('shell.exportCsv') }}</button>
              <span class="caption">{{ t('gov.simulator.saveNote') }}</span>
            </div>
          </AppCard>
        </template>
      </div>
    </div>
  </PageShell>
</template>

<style scoped>
.split { grid-template-columns: minmax(280px, 380px) 1fr; }
.levers { display: flex; flex-direction: column; gap: 12px; }
.col { display: flex; flex-direction: column; gap: var(--dm-space-4); min-width: 0; }
.control-row { display: grid; grid-template-columns: 1fr 120px; gap: 10px; align-items: center; }
.slider { margin: 0 6px; }
.control :deep(.num-input) { width: 100%; text-align: right; }
.pair-block { display: flex; align-items: center; gap: 24px; flex-wrap: wrap; }
.pair { display: flex; flex-direction: column; gap: 4px; }
.big { font-size: var(--dm-text-kpi); font-weight: 500; letter-spacing: -0.02em; line-height: 1; }
.arrow { font-size: 1.6rem; color: var(--dm-danger); }
.delta-text { margin: 10px 0 0; font-size: var(--dm-text-lg); font-weight: 500; }
.mini-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 12px; margin-top: 12px; }
.mini { background: var(--dm-surface-2); border-radius: var(--dm-radius-md); padding: 12px 16px; display: flex; flex-direction: column; gap: 4px; }
.mini-value { font-size: var(--dm-text-lg); font-weight: 500; }
.assumptions { margin: 12px 0 0; padding-left: 18px; }
.clip { max-width: 200px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.save-row { display: flex; align-items: center; gap: 16px; flex-wrap: wrap; margin-top: 16px; }
.link-arrow:disabled { opacity: 0.5; cursor: default; }
</style>
