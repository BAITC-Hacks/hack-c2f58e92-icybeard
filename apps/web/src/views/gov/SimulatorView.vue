<script setup lang="ts">
import Button from 'primevue/button'
import Column from 'primevue/column'
import DataTable from 'primevue/datatable'
import Select from 'primevue/select'
import Slider from 'primevue/slider'
import { onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute } from 'vue-router'
import { analytics, simulation } from '@/api/endpoints'
import type { LosItem, RedistributeResponse, SimulateResponse } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import OriginTag from '@/components/OriginTag.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import { days, signed } from '@/lib/format'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'
import { useLocaleFormat } from '@/composables/useLocaleFormat'
import PageShell from '@/components/ui/PageShell.vue'

const { t } = useI18n()
const { num } = useLocaleFormat()
const refdata = useRefdataStore()
const auth = useAuthStore()
const route = useRoute()
// 3.2: список перегруженных организаций (RegionView, GovMapView) ведёт сюда с конкретным регионом/профилем
// регион — из ссылки или учётной записи, профиль — только из ссылки; без обоих расчёт не запускается
const region = ref<string | null>(typeof route.query.region === 'string' ? route.query.region : (auth.region ?? null))
const profile = ref<string | null>(typeof route.query.profile === 'string' ? route.query.profile : null)
const capacity = ref(15)
const redirect = ref(0)
const horizon = ref(90)
const maxShare = ref(20)
// 3.4: «+N коек» — переводится в госпитализации в день через LOS на стороне ML-сервиса (см. подсказку под результатом)
const beds = ref(0)
const result = ref<SimulateResponse | null>(null)
const moves = ref<RedistributeResponse | null>(null)
const los = ref<LosItem | null>(null)
const error = ref<unknown>(null)
const busy = ref(false)

async function run() {
  const regionKato = region.value
  const profileCode = profile.value
  if (!regionKato || !profileCode) return
  busy.value = true
  error.value = null
  try {
    ;[result.value, moves.value] = await Promise.all([
      simulation.simulate(regionKato, profileCode, { capacityDeltaPct: capacity.value, redistributeSharePct: redirect.value, horizonDays: horizon.value, bedsDelta: beds.value }),
      simulation.redistribute(regionKato, profileCode, { maxShareMovedPct: maxShare.value, horizonDays: horizon.value }),
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
  // автозапуск только по ссылке с региона/организации (регион и профиль в query); иначе регулятор выбирает сам
  if (typeof route.query.region === 'string' && typeof route.query.profile === 'string') await run()
})
</script>

<template>
  <PageShell :title="t('gov.simulator.title')" :lead="t('gov.simulator.lead')">
    <div class="grid cols-2">
      <div class="card">
        <h2>{{ t('gov.simulator.scenario') }}</h2>
        <div class="form-grid">
          <div class="field"><label>{{ t('common.region') }}</label><Select v-model="region" :options="refdata.regions" option-label="name" option-value="regionKato" filter :placeholder="t('common.region')" /></div>
          <div class="field"><label>{{ t('common.profile') }}</label><Select v-model="profile" :options="refdata.profiles" option-label="name" option-value="profileCode" filter :placeholder="t('common.profile')" /></div>
        </div>
        <div class="field" style="margin-top: 12px"><label>{{ t('gov.simulator.capacity') }}: {{ signed(capacity, 0) }} %</label><Slider v-model="capacity" :min="-30" :max="60" /></div>
        <div class="field" style="margin-top: 12px"><label>{{ t('gov.simulator.redirect') }}: {{ redirect }} %</label><Slider v-model="redirect" :min="0" :max="50" /></div>
        <div class="field" style="margin-top: 12px"><label>{{ t('gov.simulator.horizon') }}: {{ horizon }} {{ t('common.days') }}</label><Slider v-model="horizon" :min="30" :max="180" :step="30" /></div>
        <div class="field" style="margin-top: 12px"><label>{{ t('gov.simulator.maxShare') }}: {{ maxShare }} %</label><Slider v-model="maxShare" :min="5" :max="50" :step="5" /></div>
        <div class="field" style="margin-top: 12px"><label>{{ t('gov.simulator.beds') }}: {{ beds }}</label><Slider v-model="beds" :min="0" :max="100" :step="5" /></div>
        <div class="actions"><Button :label="t('common.apply')" icon="pi pi-play" :loading="busy" :disabled="!region || !profile" @click="run" /></div>
        <ErrorBox :error="error" />
      </div>
      <div v-if="!result" class="card"><EmptyState :title="t('gov.simulator.pickTitle')" icon="pi pi-sliders-h" /></div>
      <div class="card" v-else>
        <h2>{{ t('gov.simulator.resultFor') }} {{ result.organisations }} <OriginTag kind="formula" /></h2>
        <div class="kpi">
          <div class="item"><div class="value">{{ days(result.baseline.meanWaitDays, 1) }}</div><div class="label">{{ t('gov.simulator.waitNow') }}</div></div>
          <div class="item"><div class="value">{{ days(result.scenario.meanWaitDays, 1) }}</div><div class="label">{{ t('gov.simulator.waitScenario') }}</div></div>
          <div class="item"><div class="value">{{ signed(result.deltaDays) }}</div><div class="label">{{ t('gov.simulator.delta') }} ({{ t('gov.simulator.sensitivity') }}: {{ signed(result.ci[0] ?? 0) }} … {{ signed(result.ci[1] ?? 0) }})</div></div>
          <div class="item" v-if="result.admissionsPerDay !== null"><div class="value">{{ num(result.admissionsPerDay, 1) }}</div><div class="label">{{ t('gov.simulator.admissionsPerDay') }}</div></div>
        </div>
        <ul class="muted"><li v-for="a in result.assumptions" :key="a">{{ a }}</li></ul>
        <p class="muted" v-if="los && los.losMedianFact > 0">
          {{ t('gov.simulator.losIntro') }}: {{ los.losMedianFact.toFixed(1) }} {{ t('common.days') }} ({{ t('gov.simulator.losMedianCaveat') }},
          {{ num(los.n) }} {{ t('gov.simulator.cases') }}<template v-if="los.losP50Model !== null">; p50 LOS: {{ los.losP50Model.toFixed(1) }} {{ t('common.days') }}</template>) —
          {{ t('gov.simulator.oneBed') }} ≈ {{ (1 / los.losMedianFact).toFixed(2) }} {{ t('gov.simulator.admissionsPerDayShort') }}<template v-if="beds > 0">, {{ t('gov.simulator.soBedsDelta') }} +{{ beds }} {{ t('gov.simulator.bedsUnit') }} ≈ +{{ (beds / los.losMedianFact).toFixed(2) }} {{ t('gov.simulator.admissionsPerDayShort') }}</template>.
        </p>
        <p class="muted" v-else-if="beds > 0">
          {{ t('gov.simulator.losMissing', { beds: beds }) }}
        </p>
        <p class="muted">{{ result.model.name }} {{ result.model.version }}</p>
        <!-- значения и источники: refdata/external_benchmarks.yaml (beds) -->
        <p class="muted">{{ t('gov.simulator.bedsBenchmark') }}</p>
      </div>
    </div>
    <div v-if="moves" class="card" style="margin-top: 16px">
      <h2>{{ t('gov.simulator.redistributeTitle', { moves: moves.moves.length, days: num(-moves.totalDeltaDays), horizon: moves.horizonDays }) }}</h2>
      <DataTable :value="moves.moves" size="small">
        <Column :header="t('gov.simulator.from')"><template #body="{ data }">{{ data.fromMo.name }} <span class="muted">({{ data.fromMo.moCode }})</span></template></Column>
        <Column :header="t('gov.simulator.to')"><template #body="{ data }">{{ data.toMo.name }} <span class="muted">({{ data.toMo.moCode }})</span></template></Column>
        <Column :header="t('gov.simulator.share')"><template #body="{ data }">{{ data.sharePct.toFixed(0) }} %</template></Column>
        <Column :header="t('gov.simulator.waitAtSource')"><template #body="{ data }">{{ days(data.waitFromBefore) }} → {{ days(data.waitFromAfter) }}</template></Column>
        <Column :header="t('gov.simulator.waitAtDestination')"><template #body="{ data }">{{ days(data.waitToBefore) }} → {{ days(data.waitToAfter) }}</template></Column>
      </DataTable>
      <p v-if="moves.moves.length === 0" class="muted">{{ t('gov.simulator.noMoves') }}</p>
    </div>
  </PageShell>
</template>
