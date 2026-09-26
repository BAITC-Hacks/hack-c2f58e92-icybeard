<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRouter } from 'vue-router'
import { ApiError } from '@/api/client'
import { analytics } from '@/api/endpoints'
import type { EquipmentRegion, ForecastResponse, OncoLateItem, StaffingRegion, VacRefusalContraindication, VacRefusalReason } from '@/api/types'
import SeriesChart from '@/components/SeriesChart.vue'
import CollapsibleSection from '@/components/ui/CollapsibleSection.vue'
import { num } from '@/lib/format'

/** Витрины по стране под картой регионов, свёрнутые в строки с итогом: онкология (прогноз и запущенные случаи),
 * кадры, отказы от вакцинации, медтехника. Каждая грузится отдельно — отсутствие витрины не ломает страницу. */
const { t } = useI18n()
const router = useRouter()

/** 3.1: онкология — поток onco_monthly не имеет региона в сущности; 'ALL' — зарезервированная сумма локализаций. */
const onco = ref<ForecastResponse | null>(null)
const oncoHint = ref<string | null>(null)
const staffing = ref<StaffingRegion[]>([])
const staffingHint = ref<string | null>(null)
const vacByReason = ref<VacRefusalReason[]>([])
const vacByContraindication = ref<VacRefusalContraindication[]>([])
const vacHint = ref<string | null>(null)
const oncoLate = ref<OncoLateItem[]>([])
const oncoLateHint = ref<string | null>(null)
const equipment = ref<EquipmentRegion[]>([])
const equipmentHint = ref<string | null>(null)

async function loadOnco() {
  try {
    onco.value = await analytics.forecast('onco_monthly', { localization: 'ALL' }, 3)
  } catch (e) {
    oncoHint.value = e instanceof ApiError && e.status === 404 ? t('gov.map.oncoNoForecast') : t('gov.map.oncoNotPublished')
  }
}

async function loadList<T>(request: () => Promise<{ items: T[] }>, target: { value: T[] }, hint: { value: string | null }, missing: string) {
  try {
    target.value = (await request()).items
    if (target.value.length === 0) hint.value = missing
  } catch {
    hint.value = missing
  }
}

async function loadVaccinationRefusals() {
  try {
    const res = await analytics.vaccinationRefusals()
    vacByReason.value = res.byReason
    vacByContraindication.value = res.byContraindication
    if (res.byReason.length === 0) vacHint.value = t('gov.map.vacRefusalsNotPublished')
  } catch {
    vacHint.value = t('gov.map.vacRefusalsNotPublished')
  }
}

const toRegion = (kato: string) => router.push({ name: 'region', params: { kato } })

onMounted(async () => {
  // Пять независимых источников — грузим параллельно, каждый со своей подсказкой при отсутствии данных.
  await Promise.all([
    loadOnco(),
    loadList(() => analytics.staffing(), staffing, staffingHint, t('gov.map.staffingNotPublished')),
    loadVaccinationRefusals(),
    loadList(() => analytics.oncologyLateStage(), oncoLate, oncoLateHint, t('gov.map.oncoLateNotPublished')),
    loadList(() => analytics.equipment(), equipment, equipmentHint, t('gov.map.equipmentNotPublished')),
  ])
})
</script>

<template>
  <div class="extras">
    <CollapsibleSection :title="t('gov.map.oncoTitle')" origin="ml" :summary="onco ? `${onco.points.length} ${t('gov.map.monthsAhead')}` : (oncoHint ?? '')">
      <SeriesChart v-if="onco" :history="onco.history" :points="onco.points" :title="t('gov.map.oncoSeriesTitle')" :unit="t('gov.map.oncoUnit')" />
      <p v-else class="muted">{{ oncoHint }}</p>
      <p v-if="onco" class="muted small">
        {{ t('gov.map.backtest') }}: sMAPE {{ (onco.backtest.smape * 100).toFixed(1) }} % {{ t('gov.map.vsNaive') }} {{ (onco.backtest.baselineSmape * 100).toFixed(1) }} %. {{ onco.model.name }} {{ onco.model.version }}. {{ t('gov.map.oncoCaveat') }}
      </p>
    </CollapsibleSection>

    <CollapsibleSection :title="t('gov.map.staffingTitle')" origin="formula" :summary="staffing.length ? `${staffing.length} · ${t('gov.map.staffingSnapshot')} ${staffing[0]!.snapshotDate}` : (staffingHint ?? '')">
      <div v-if="staffing.length" class="table-wrap">
        <table class="dense-table">
          <thead><tr><th>{{ t('common.region') }}</th><th class="num">{{ t('gov.map.staffingPer10k') }}</th><th class="num">{{ t('gov.map.staffingPer1000') }}</th></tr></thead>
          <tbody>
            <tr v-for="s in staffing" :key="s.regionKato" class="clickable" @click="toRegion(s.regionKato)">
              <td>{{ s.regionName }}</td>
              <td class="num">{{ num(s.ratePer10kPopulation, 1) }}</td>
              <td class="num"><span v-if="s.ratePer1000Admissions !== null">{{ num(s.ratePer1000Admissions, 1) }}</span><span v-else class="muted">{{ t('gov.map.staffingNoAdmissions') }}</span></td>
            </tr>
          </tbody>
        </table>
      </div>
      <p v-else class="muted">{{ staffingHint }}</p>
    </CollapsibleSection>

    <CollapsibleSection :title="t('gov.map.vacRefusalsTitle')" origin="formula" :summary="vacByReason.length ? `${vacByReason.length} ${t('gov.map.reasonsShort')}` : (vacHint ?? '')">
      <p class="muted small">{{ t('gov.map.vacRefusalsNationwide') }}</p>
      <div v-if="vacByReason.length" class="grid cols-2">
        <table class="dense-table">
          <thead><tr><th>{{ t('gov.map.vacReason') }}</th><th class="num">{{ t('common.count') }}</th></tr></thead>
          <tbody><tr v-for="r in vacByReason" :key="r.reason"><td>{{ r.reason }}</td><td class="num">{{ num(r.n) }}</td></tr></tbody>
        </table>
        <table v-if="vacByContraindication.length" class="dense-table">
          <thead><tr><th>{{ t('gov.map.vacContraindication') }}</th><th class="num">{{ t('common.count') }}</th></tr></thead>
          <tbody><tr v-for="c in vacByContraindication" :key="c.contraindication"><td>{{ c.contraindication }}</td><td class="num">{{ num(c.n) }}</td></tr></tbody>
        </table>
      </div>
      <p v-else class="muted">{{ vacHint }}</p>
    </CollapsibleSection>

    <CollapsibleSection :title="t('gov.map.oncoLateTitle')" origin="formula" :summary="oncoLate.length ? `${oncoLate.length} · ${t('gov.map.staffingSnapshot')} ${oncoLate[0]!.snapshotDate}` : (oncoLateHint ?? '')">
      <p class="muted small">{{ t('gov.map.oncoLateNationwide') }}</p>
      <div v-if="oncoLate.length" class="table-wrap">
        <table class="dense-table">
          <thead><tr><th>{{ t('gov.map.oncoLateLocalization') }}</th><th class="num">{{ t('gov.map.oncoLateShare') }}</th><th class="num">{{ t('gov.map.oncoLateCount') }}</th></tr></thead>
          <tbody>
            <tr v-for="o in oncoLate" :key="o.localizationId">
              <td>{{ o.localizationName }}</td>
              <td class="num"><span v-if="o.advancedShare !== null">{{ num(o.advancedShare * 100, 1) }} %</span><span v-else class="muted">—</span></td>
              <td class="num">{{ num(o.advancedTotalCount) }}</td>
            </tr>
          </tbody>
        </table>
      </div>
      <p v-else class="muted">{{ oncoLateHint }}</p>
    </CollapsibleSection>

    <CollapsibleSection :title="t('gov.map.equipmentTitle')" origin="formula" :summary="equipment.length ? `${num(equipment.reduce((s, e) => s + e.units, 0))} ${t('gov.map.unitsShort')}` : (equipmentHint ?? '')">
      <div v-if="equipment.length" class="table-wrap">
        <table class="dense-table">
          <thead><tr><th>{{ t('common.region') }}</th><th class="num">{{ t('gov.map.equipmentUnits') }}</th></tr></thead>
          <tbody>
            <tr v-for="e in equipment" :key="e.regionKato" class="clickable" @click="toRegion(e.regionKato)"><td>{{ e.regionName }}</td><td class="num">{{ num(e.units) }}</td></tr>
          </tbody>
        </table>
      </div>
      <p v-else class="muted">{{ equipmentHint }}</p>
    </CollapsibleSection>
  </div>
</template>

<style scoped>
.extras { display: flex; flex-direction: column; gap: var(--dm-space-3); }
</style>
