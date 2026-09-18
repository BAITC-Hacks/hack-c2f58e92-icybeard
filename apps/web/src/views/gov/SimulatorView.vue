<script setup lang="ts">
import Button from 'primevue/button'
import Column from 'primevue/column'
import DataTable from 'primevue/datatable'
import Select from 'primevue/select'
import Slider from 'primevue/slider'
import { onMounted, ref } from 'vue'
import { useRoute } from 'vue-router'
import { analytics, simulation } from '@/api/endpoints'
import type { LosItem, RedistributeResponse, SimulateResponse } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import OriginTag from '@/components/OriginTag.vue'
import { days, num, signed } from '@/lib/format'
import { useRefdataStore } from '@/stores/refdata'

const refdata = useRefdataStore()
const route = useRoute()
// 3.2: список перегруженных организаций (RegionView, GovMapView) ведёт сюда с конкретным регионом/профилем
const region = ref(typeof route.query.region === 'string' ? route.query.region : '75')
const profile = ref(typeof route.query.profile === 'string' ? route.query.profile : '381')
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
  busy.value = true
  error.value = null
  try {
    ;[result.value, moves.value] = await Promise.all([
      simulation.simulate(region.value, profile.value, { capacityDeltaPct: capacity.value, redistributeSharePct: redirect.value, horizonDays: horizon.value, bedsDelta: beds.value }),
      simulation.redistribute(region.value, profile.value, { maxShareMovedPct: maxShare.value, horizonDays: horizon.value }),
    ])
    // длительность лечения — отдельная витрина; её отсутствие не должно ломать расчёт
    los.value = (await analytics.los(region.value, profile.value)).items[0] ?? null
  } catch (e) {
    if (result.value === null) error.value = e
  } finally {
    busy.value = false
  }
}

onMounted(async () => {
  await refdata.load()
  await run()
})
</script>

<template>
  <main class="page">
    <h1>Симулятор</h1>
    <p class="lead">Что будет с ожиданием, если добавить мощность или перенаправить часть направлений. Жидкостная модель очереди, откалиброванная на фактических ожиданиях.</p>
    <div class="grid cols-2">
      <div class="card">
        <h2>Сценарий</h2>
        <div class="form-grid">
          <div class="field"><label>Регион</label><Select v-model="region" :options="refdata.regions" option-label="name" option-value="regionKato" filter /></div>
          <div class="field"><label>Профиль</label><Select v-model="profile" :options="refdata.profiles" option-label="name" option-value="profileCode" filter /></div>
        </div>
        <div class="field" style="margin-top: 12px"><label>Мощность: {{ signed(capacity, 0) }} %</label><Slider v-model="capacity" :min="-30" :max="60" /></div>
        <div class="field" style="margin-top: 12px"><label>Перенаправить из группы: {{ redirect }} %</label><Slider v-model="redirect" :min="0" :max="50" /></div>
        <div class="field" style="margin-top: 12px"><label>Горизонт: {{ horizon }} дней</label><Slider v-model="horizon" :min="30" :max="180" :step="30" /></div>
        <div class="field" style="margin-top: 12px"><label>Максимум переноса от одной организации: {{ maxShare }} %</label><Slider v-model="maxShare" :min="5" :max="50" :step="5" /></div>
        <div class="field" style="margin-top: 12px"><label>+N коек: {{ beds }}</label><Slider v-model="beds" :min="0" :max="100" :step="5" /></div>
        <div class="actions"><Button label="Рассчитать" icon="pi pi-play" :loading="busy" @click="run" /></div>
        <ErrorBox :error="error" />
      </div>
      <div class="card" v-if="result">
        <h2>Результат для {{ result.organisations }} организаций <OriginTag kind="formula" /></h2>
        <div class="kpi">
          <div class="item"><div class="value">{{ days(result.baseline.meanWaitDays, 1) }}</div><div class="label">ожидание сейчас, дн.</div></div>
          <div class="item"><div class="value">{{ days(result.scenario.meanWaitDays, 1) }}</div><div class="label">ожидание в сценарии, дн.</div></div>
          <div class="item"><div class="value">{{ signed(result.deltaDays) }}</div><div class="label">изменение, дн. (чувствительность к потоку ±20 %: {{ signed(result.ci[0] ?? 0) }} … {{ signed(result.ci[1] ?? 0) }})</div></div>
          <div class="item" v-if="result.admissionsPerDay !== null"><div class="value">{{ num(result.admissionsPerDay, 1) }}</div><div class="label">пропускная способность в сценарии, госпитализаций/день</div></div>
        </div>
        <ul class="muted"><li v-for="a in result.assumptions" :key="a">{{ a }}</li></ul>
        <p class="muted" v-if="los && los.losMedianFact > 0">
          Средняя длительность лечения в этой ячейке: {{ los.losMedianFact.toFixed(1) }} дн. (медиана факта за 12 мес,
          {{ los.n.toLocaleString('ru-RU') }} случаев<template v-if="los.losP50Model !== null">; p50 LOS-модели {{ los.losP50Model.toFixed(1) }} дн.</template>) —
          одна койка ≈ {{ (1 / los.losMedianFact).toFixed(2) }} госпитализации в день<template v-if="beds > 0">, поэтому +{{ beds }} коек ≈ +{{ (beds / los.losMedianFact).toFixed(2) }} госпитализации в день</template>.
        </p>
        <p class="muted" v-else-if="beds > 0">
          Длительность лечения для этой ячейки не опубликована — «+{{ beds }} коек» не учтено в расчёте пропускной способности.
        </p>
        <p class="muted">{{ result.model.name }} {{ result.model.version }}</p>
        <!-- значения и источники: refdata/external_benchmarks.yaml (beds) -->
        <p class="muted">
          Ориентир коечного фонда: ЕС ≈ 5,3 койки на 1 000 жителей (Eurostat, 2021), Казахстан ≈ 6,0 (ВОЗ HFA, 2021) —
          внешний ориентир для сценариев «добавить мощность», не норматив потребности.
        </p>
      </div>
    </div>
    <div v-if="moves" class="card" style="margin-top: 16px">
      <h2>Перераспределение: {{ moves.moves.length }} переносов, {{ num(-moves.totalDeltaDays) }} дней ожидания меньше за {{ moves.horizonDays }} дней</h2>
      <DataTable :value="moves.moves" size="small">
        <Column header="Откуда"><template #body="{ data }">{{ data.fromMo.name }} <span class="muted">({{ data.fromMo.moCode }})</span></template></Column>
        <Column header="Куда"><template #body="{ data }">{{ data.toMo.name }} <span class="muted">({{ data.toMo.moCode }})</span></template></Column>
        <Column header="Доля"><template #body="{ data }">{{ data.sharePct.toFixed(0) }} %</template></Column>
        <Column header="Ожидание у источника"><template #body="{ data }">{{ days(data.waitFromBefore) }} → {{ days(data.waitFromAfter) }}</template></Column>
        <Column header="Ожидание у получателя"><template #body="{ data }">{{ days(data.waitToBefore) }} → {{ days(data.waitToAfter) }}</template></Column>
      </DataTable>
      <p v-if="moves.moves.length === 0" class="muted">Модель не нашла переносов, которые сокращают суммарное ожидание.</p>
    </div>
  </main>
</template>
