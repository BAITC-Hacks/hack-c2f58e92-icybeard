<script setup lang="ts">
import Button from 'primevue/button'
import InputNumber from 'primevue/inputnumber'
import Select from 'primevue/select'
import Slider from 'primevue/slider'
import { useToast } from 'primevue/usetoast'
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute } from 'vue-router'
import { analytics, journal, simulation } from '@/api/endpoints'
import type { LosItem, RedistributeResponse, SimulateResponse } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import AppCard from '@/components/ui/AppCard.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import PageShell from '@/components/ui/PageShell.vue'
import SearchSelect from '@/components/ui/SearchSelect.vue'
import Skeleton from '@/components/ui/Skeleton.vue'
import { useLocaleFormat } from '@/composables/useLocaleFormat'
import { downloadCsv } from '@/lib/csv'
import { shortOrgName } from '@/lib/format'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'

/** Симулятор «что если» (W-Simulator) для обычного пользователя: слева «Условия сценария» — регион, профиль, срок
 * (выпадающий список 4·8·12 недель) и четыре рычага с подсказками; справа «Что изменится» — среднее ожидание
 * сейчас → после, итог словами с диапазоном неопределённости, график, сколько пациентов больницы смогут принимать;
 * допущения модели и ориентиры — в свёрнутом «Как считали». Ниже «Куда перенаправить пациентов» (/redistribute)
 * с сохранением сценария в журнал решений и экспортом CSV. */
interface Control { key: 'capacity' | 'redirect' | 'maxShare' | 'beds'; min: number; max: number; step: number; suffix: string }
const CONTROLS: Control[] = [
  { key: 'beds', min: 0, max: 100, step: 5, suffix: '' },
  { key: 'capacity', min: -30, max: 60, step: 1, suffix: '%' },
  { key: 'redirect', min: 0, max: 50, step: 1, suffix: '%' },
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
const deltaText = computed(() => (delta.value < 0 ? t('gov.simulator.lessBy', { days: num(-delta.value, 1) }) : delta.value > 0 ? t('gov.simulator.moreBy', { days: num(delta.value, 1) }) : t('gov.simulator.noChange')))
const controlLabel = (key: Control['key']) => t(`gov.simulator.lever.${key}`)
const controlHint = (key: Control['key']) => t(`gov.simulator.lever.${key}Hint`)
const horizonOptions = computed(() => HORIZONS.map((w) => ({ value: w, label: t('gov.simulator.horizonOption', { weeks: w }) })))
/** Диапазон изменения ожидания (ci — границы дельты) словами: «от 0,4 до 0,8 дн.». */
const rangeText = computed(() => {
  const ci = result.value?.ci ?? []
  if (ci.length < 2) return ''
  const [a, b] = [Math.abs(ci[0]!), Math.abs(ci[1]!)].sort((x, y) => x - y)
  return t('gov.simulator.rangeText', { lo: num(a!, 1), hi: num(b!, 1) })
})

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

/** CSV для Excel: русские заголовки, полные названия больниц, сценарий в первых строках имени файла. */
function exportCsv() {
  if (!moves.value || !region.value || !profile.value) return
  const c = (key: string) => t(`gov.simulator.csv.${key}`)
  const cols = ['from', 'fromCode', 'to', 'toCode', 'share', 'arrivals', 'fromBefore', 'fromAfter', 'toBefore', 'toAfter'].map(c)
  const rows = moves.value.moves.map((m) => Object.fromEntries([
    [c('from'), m.fromMo.name], [c('fromCode'), m.fromMo.moCode], [c('to'), m.toMo.name], [c('toCode'), m.toMo.moCode],
    [c('share'), Math.round(m.sharePct)], [c('arrivals'), Math.round(m.arrivalsPerDay * 7 * 10) / 10],
    [c('fromBefore'), Math.round(m.waitFromBefore * 10) / 10], [c('fromAfter'), Math.round(m.waitFromAfter * 10) / 10],
    [c('toBefore'), Math.round(m.waitToBefore * 10) / 10], [c('toAfter'), Math.round(m.waitToAfter * 10) / 10],
  ]))
  const name = `${t('gov.simulator.csv.file')} ${refdata.regionName(region.value)} ${refdata.profileName(profile.value)} ${new Date().toISOString().slice(0, 10)}`
  downloadCsv(`${name.replace(/[\\/:*?"<>|]+/g, ' ').replace(/\s+/g, ' ').trim()}.csv`, rows, cols)
}

/** «Как считали» простыми словами — из тех же величин, что и расчёт; технические допущения API не показываем. */
const howItems = computed(() => {
  const r = result.value
  if (!r) return []
  const items = [t('gov.simulator.how.flow'), t('gov.simulator.how.queue', { n: r.organisations }), t('gov.simulator.how.range')]
  if (los.value && los.value.losMedianFact > 0) {
    items.push(t('gov.simulator.how.beds', { days: num(los.value.losMedianFact, 1) }))
    if (scenario.value.beds > 0) items.push(t('gov.simulator.how.bedsAdded', { beds: scenario.value.beds, n: num((scenario.value.beds / los.value.losMedianFact) * 7, 0) }))
  } else if (scenario.value.beds > 0) {
    items.push(t('gov.simulator.how.bedsMissing', { beds: scenario.value.beds }))
  }
  items.push(t('gov.simulator.how.estimate'))
  return items
})
/** Ширина полос сравнения «сейчас / после» — от большего из значений и верхней границы диапазона. */
const barScale = computed(() => Math.max(result.value?.baseline.meanWaitDays ?? 0, interval.value[1], result.value?.scenario.meanWaitDays ?? 0, 0.1))
const barWidth = (v: number) => `${Math.max(2, (v / barScale.value) * 100)}%`

onMounted(async () => {
  await refdata.load()
  // автозапуск только по ссылке с региона/организации; иначе регулятор выбирает сам
  if (typeof route.query.region === 'string' && typeof route.query.profile === 'string') await run()
})
</script>

<template>
  <PageShell :title="t('gov.simulator.titleWhatIf')">
    <template #subtitle>{{ t('gov.simulator.subtitlePlain') }}</template>
    <ErrorBox :error="error" />

    <div class="split">
      <AppCard :title="t('gov.simulator.leversTitle')" class="sticky levers">
        <p class="caption card-lead">{{ t('gov.simulator.leversLead') }}</p>
        <div class="form-col">
          <div class="field"><label>{{ t('common.region') }}</label><SearchSelect v-model="region" :options="refdata.regions" option-label="name" option-value="regionKato" :placeholder="t('gov.simulator.pickRegion')" /></div>
          <div class="field"><label>{{ t('common.profile') }}</label><SearchSelect v-model="profile" :options="refdata.profiles" option-label="name" option-value="profileCode" :placeholder="t('gov.simulator.pickProfile')" /></div>
          <div class="field"><label>{{ t('gov.simulator.horizonLabel') }}</label><Select v-model="weeks" :options="horizonOptions" option-label="label" option-value="value" /></div>
          <div v-for="c in CONTROLS" :key="c.key" class="field control">
            <label>{{ controlLabel(c.key) }}</label>
            <span class="hint">{{ controlHint(c.key) }}</span>
            <div class="control-row">
              <Slider v-model="scenario[c.key]" :min="c.min" :max="c.max" :step="c.step" class="slider" />
              <InputNumber v-model="scenario[c.key]" :min="c.min" :max="c.max" :step="c.step" :suffix="c.suffix ? ` ${c.suffix}` : undefined" size="small" show-buttons button-layout="stacked" input-class="num-input" />
            </div>
          </div>
        </div>
        <div class="actions"><Button :label="t('common.apply')" icon="pi pi-calculator" class="run-btn" :loading="busy" :disabled="!region || !profile" data-testid="simulate-run" @click="run" /></div>
        <p class="caption">{{ t('gov.simulator.leversNotePlain') }}</p>
      </AppCard>

      <div class="col">
        <AppCard v-if="busy && !result"><Skeleton kind="kpi" /><Skeleton kind="chart" style="margin-top: 12px" /></AppCard>
        <AppCard v-else-if="!result"><EmptyState :title="t('gov.simulator.pickTitle')" :text="t('gov.simulator.pickText')" icon="pi pi-sliders-h" /></AppCard>
        <template v-else>
          <AppCard :title="t('gov.simulator.resultTitle', { weeks })" origin="formula" data-testid="simulate-result">
            <p class="caption card-lead">{{ t('gov.simulator.resultLead', { region: refdata.regionName(region ?? ''), profile: refdata.profileName(profile ?? '').toLowerCase() }) }}</p>
            <div class="stats tabular">
              <div class="stat">
                <span class="stat-label">{{ t('gov.simulator.nowLabel') }}</span>
                <span class="stat-value">{{ num(result.baseline.meanWaitDays, 1) }} <small>{{ t('common.days') }}</small></span>
              </div>
              <div class="stat stat-after" :class="delta < 0 ? 'good' : delta > 0 ? 'bad' : ''">
                <span class="stat-label">{{ t('gov.simulator.afterLabel') }}</span>
                <span class="stat-value">{{ num(result.scenario.meanWaitDays, 1) }} <small>{{ t('common.days') }}</small></span>
              </div>
              <div class="stat">
                <span class="stat-label">{{ t('gov.simulator.deltaLabel') }}</span>
                <span class="stat-value" :class="delta < 0 ? 'delta-down' : delta > 0 ? 'delta-up' : ''">{{ delta > 0 ? '+' : delta < 0 ? '−' : '' }}{{ num(Math.abs(delta), 1) }} <small>{{ t('common.days') }}</small></span>
                <span v-if="rangeText" class="stat-sub">{{ rangeText }}</span>
              </div>
            </div>
            <p class="delta-text" :class="delta < 0 ? 'delta-down' : delta > 0 ? 'delta-up' : ''">{{ deltaText }}</p>
            <div class="bars" role="img" :aria-label="deltaText">
              <div class="bar-row">
                <span class="bar-name">{{ t('gov.simulator.before') }}</span>
                <div class="bar-track"><div class="bar before" :style="{ width: barWidth(result.baseline.meanWaitDays) }" /></div>
                <span class="bar-value tabular">{{ num(result.baseline.meanWaitDays, 1) }} {{ t('common.days') }}</span>
              </div>
              <div class="bar-row">
                <span class="bar-name">{{ t('gov.simulator.after') }}</span>
                <div class="bar-track">
                  <div class="bar-range" :style="{ left: barWidth(Math.min(...interval)), width: `calc(${barWidth(Math.max(...interval))} - ${barWidth(Math.min(...interval))})` }" />
                  <div class="bar after" :style="{ width: barWidth(result.scenario.meanWaitDays) }" />
                </div>
                <span class="bar-value tabular">{{ num(result.scenario.meanWaitDays, 1) }} {{ t('common.days') }}</span>
              </div>
            </div>
            <p class="caption chart-note">{{ t('gov.simulator.chartNotePlain') }}</p>
            <div v-if="result.admissionsPerDay !== null" class="fact-line">
              <span>{{ t('gov.simulator.throughputPlain') }}</span>
              <b class="tabular">{{ t('gov.simulator.throughputValue', { n: num(result.admissionsPerDay * 7, 0) }) }}</b>
            </div>
            <details class="how">
              <summary>{{ t('gov.simulator.howTitle') }}</summary>
              <ul class="how-list">
                <li v-for="item in howItems" :key="item">{{ item }}</li>
              </ul>
              <!-- значения и источники: refdata/external_benchmarks.yaml (beds) -->
              <p class="caption">{{ t('gov.simulator.how.benchmark') }}</p>
            </details>
          </AppCard>

          <AppCard v-if="moves" :title="t('gov.simulator.movesTitle')" origin="formula">
            <p class="caption card-lead">{{ moves.moves.length ? t('gov.simulator.movesLead', { moves: moves.moves.length, days: num(-moves.totalDeltaDays), horizon: moves.horizonDays }) : t('gov.simulator.noMoves') }}</p>
            <p v-if="moves.moves[0]" class="example">{{ t('gov.simulator.movesExample', { share: moves.moves[0].sharePct.toFixed(0), from: shortOrgName(moves.moves[0].fromMo.name), to: shortOrgName(moves.moves[0].toMo.name), fromBefore: num(moves.moves[0].waitFromBefore, 1), fromAfter: num(moves.moves[0].waitFromAfter, 1), toBefore: num(moves.moves[0].waitToBefore, 1), toAfter: num(moves.moves[0].waitToAfter, 1) }) }}</p>
            <div v-if="moves.moves.length" class="table-wrap">
              <table class="dense-table moves">
                <thead>
                  <tr><th>{{ t('gov.simulator.colFromPlain') }}</th><th>{{ t('gov.simulator.colToPlain') }}</th><th class="num">{{ t('gov.simulator.colSharePlain') }}</th><th class="num">{{ t('gov.simulator.colSourceWait') }}</th><th class="num">{{ t('gov.simulator.colTargetWait') }}</th></tr>
                </thead>
                <tbody>
                  <tr v-for="m in moves.moves" :key="m.fromMo.moCode + m.toMo.moCode">
                    <td class="org" :title="m.fromMo.name">{{ shortOrgName(m.fromMo.name) }}</td>
                    <td class="org" :title="m.toMo.name">{{ shortOrgName(m.toMo.name) }}</td>
                    <td class="num">{{ m.sharePct.toFixed(0) }} %</td>
                    <td class="num">{{ t('gov.simulator.waitChange', { before: num(m.waitFromBefore, 1), after: num(m.waitFromAfter, 1) }) }}</td>
                    <td class="num">{{ t('gov.simulator.waitChange', { before: num(m.waitToBefore, 1), after: num(m.waitToAfter, 1) }) }}</td>
                  </tr>
                </tbody>
              </table>
            </div>
            <div class="save-row">
              <Button :label="savedId ? t('gov.simulator.saved') : t('gov.simulator.saveScenario')" :icon="savedId ? 'pi pi-check' : 'pi pi-bookmark'" :disabled="!!savedId" :loading="saving" data-testid="scenario-save" @click="saveScenario" />
              <button type="button" class="link-arrow small" :disabled="!moves.moves.length" @click="exportCsv">{{ t('shell.exportCsv') }}</button>
            </div>
            <p class="caption">{{ t('gov.simulator.saveNote') }}</p>
          </AppCard>
        </template>
      </div>
    </div>
  </PageShell>
</template>

<style scoped>
.split { grid-template-columns: minmax(320px, 1fr) 1.4fr; }
@media (max-width: 900px) { .split { grid-template-columns: 1fr; } }
.levers { display: flex; flex-direction: column; gap: 12px; }
.levers :deep(.run-btn) { width: 100%; }
.card-lead { margin: -4px 0 8px; line-height: 1.5; }
.form-col { display: flex; flex-direction: column; gap: 18px; }
.field { display: flex; flex-direction: column; gap: 6px; }
.field > label { font-weight: var(--fw-bold); font-size: var(--dm-text-base); text-transform: none; letter-spacing: 0; color: var(--text); }
.hint { font-size: var(--dm-text-sm); color: var(--text-secondary); line-height: 1.4; margin-top: -2px; }
.col { display: flex; flex-direction: column; gap: var(--dm-space-4); min-width: 0; }
.control-row { display: grid; grid-template-columns: 1fr 120px; gap: 12px; align-items: center; }
.slider { margin: 0 8px; }
.control :deep(.num-input) { width: 100%; text-align: right; }
.delta-text { margin: 14px 0 4px; font-size: var(--dm-text-md); font-weight: var(--fw-bold); }
.chart-note { margin: 0 0 8px; }
.fact-line { display: flex; justify-content: space-between; gap: 16px; padding: 12px 0; border-top: 1px solid var(--dm-hairline); border-bottom: 1px solid var(--dm-hairline); }
.how { margin-top: 12px; }
.how summary { cursor: pointer; font-weight: var(--fw-bold); padding: 6px 0; }
.how p { margin: 6px 0 0; line-height: 1.5; }
.stats { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 12px; margin-top: 4px; }
.stat { border: 1px solid var(--dm-hairline); border-radius: 14px; padding: 14px 16px; display: flex; flex-direction: column; gap: 6px; }
.stat-after.good { border-color: color-mix(in srgb, var(--dm-ok) 45%, transparent); background: color-mix(in srgb, var(--dm-ok) 6%, transparent); }
.stat-after.bad { border-color: color-mix(in srgb, var(--dm-danger) 45%, transparent); }
.stat-label { font-size: var(--dm-text-sm); color: var(--text-secondary); }
.stat-value { font-size: 30px; font-weight: var(--fw-extrabold); letter-spacing: -0.02em; line-height: 1.05; }
.stat-value small { font-size: var(--dm-text-base); font-weight: 500; color: var(--text-secondary); }
.stat-sub { font-size: var(--dm-text-sm); color: var(--text-secondary); }
.bars { display: flex; flex-direction: column; gap: 12px; margin: 8px 0 6px; }
.bar-row { display: grid; grid-template-columns: 70px minmax(0, 1fr) 80px; gap: 12px; align-items: center; }
.bar-name { color: var(--text-secondary); }
.bar-track { position: relative; height: 22px; background: var(--surface-muted); border-radius: 6px; }
.bar { position: absolute; left: 0; top: 0; bottom: 0; border-radius: 6px; }
.bar.before { background: var(--bar-neutral, #B4C0D8); }
.bar.after { background: var(--dm-accent); }
.bar-range { position: absolute; top: -4px; bottom: -4px; border-radius: 6px; background: color-mix(in srgb, var(--dm-accent) 22%, transparent); border: 1px dashed var(--dm-accent); box-sizing: border-box; z-index: 1; }
.bar-value { text-align: right; font-weight: var(--fw-bold); }
.how-list { margin: 8px 0; padding-left: 20px; display: flex; flex-direction: column; gap: 6px; line-height: 1.5; }
.example { margin: 0 0 12px; padding: 10px 14px; border-left: 3px solid var(--dm-accent); background: var(--surface-muted); border-radius: 0 10px 10px 0; line-height: 1.5; }
.moves .org { min-width: 180px; white-space: normal; line-height: 1.35; }
@media (max-width: 700px) { .stats { grid-template-columns: 1fr; } }
.save-row { display: flex; align-items: center; gap: 16px; flex-wrap: wrap; margin-top: 16px; }
.link-arrow:disabled { opacity: 0.5; cursor: default; }
</style>
