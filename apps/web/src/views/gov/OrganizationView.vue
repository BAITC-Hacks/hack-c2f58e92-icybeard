<script setup lang="ts">
import Tab from 'primevue/tab'
import TabList from 'primevue/tablist'
import TabPanel from 'primevue/tabpanel'
import TabPanels from 'primevue/tabpanels'
import Tabs from 'primevue/tabs'
import { useToast } from 'primevue/usetoast'
import { computed, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute } from 'vue-router'
import { ApiError } from '@/api/client'
import { analytics, queue } from '@/api/endpoints'
import type { Anomaly, EquipmentOrganization, OrganizationItem, OrganizationSeries, PredictResponse } from '@/api/types'
import AnomalyFeed from '@/components/AnomalyFeed.vue'
import ErrorBox from '@/components/ErrorBox.vue'
import OriginTag from '@/components/OriginTag.vue'
import QueueChart from '@/components/QueueChart.vue'
import AppCard from '@/components/ui/AppCard.vue'
import KpiRow from '@/components/ui/KpiRow.vue'
import KpiTile from '@/components/ui/KpiTile.vue'
import PageShell from '@/components/ui/PageShell.vue'
import SearchSelect from '@/components/ui/SearchSelect.vue'
import { days, pct, shortOrgName, signed } from '@/lib/format'
import { dateShort } from '@/lib/route'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'

/** Кабинет организации: короткое имя заголовком, полное подстрокой; «организация против региона» парными плитками
 * с дельтой (факт организации за 4 недели против прогноза модели по региону); очередь и сигналы вкладками. */
const { t } = useI18n()
const route = useRoute()
const refdata = useRefdataStore()
const auth = useAuthStore()
const toast = useToast()

const moCode = computed(() => String(route.params.moCode))
const kato = computed(() => String(route.query.kato ?? auth.region ?? ''))
const profile = ref<string>(String(route.query.profile ?? ''))
const organizations = ref<OrganizationItem[]>([])
const series = ref<OrganizationSeries | null>(null)
const regionPrediction = ref<PredictResponse | null>(null)
const anomalies = ref<Anomaly[]>([])
const equipment = ref<EquipmentOrganization | null>(null)
const error = ref<unknown>(null)
const tab = ref('queue')

const fullName = computed(() => organizations.value.find((o) => o.moCode === moCode.value)?.name ?? moCode.value)
const period = computed(() => (series.value?.days.length ? `${dateShort(series.value.days[0]!.day)} — ${dateShort(series.value.days.at(-1)!.day)}` : ''))

interface Pair { key: string; org: number | null | undefined; region: number | null | undefined; format: (v: number | null | undefined) => string; delta: (o: number, r: number) => string }
/** Парные показатели: факт организации против прогноза региона; дельта в днях или процентных пунктах. */
const pairs = computed<Pair[]>(() => {
  const th = series.value?.throughput
  const rp = regionPrediction.value
  const dDays = (o: number, r: number) => `${signed(o - r, 0)} ${t('common.days')}`
  const dPoints = (o: number, r: number) => `${signed((o - r) * 100, 0)} ${t('gov.org.points')}`
  return [
    { key: 'p50', org: th?.waitP50Days, region: rp?.p50Days, format: (v) => days(v), delta: dDays },
    { key: 'p90', org: th?.waitP90Days, region: rp?.p90Days, format: (v) => days(v), delta: dDays },
    { key: 'refusal', org: th?.refusalRate4w, region: rp?.pRefusal, format: (v) => pct(v), delta: dPoints },
  ]
})
const worse = computed(() => (series.value?.throughput?.waitP50Days ?? 0) > (regionPrediction.value?.p50Days ?? Infinity))

async function load() {
  error.value = null
  series.value = null
  regionPrediction.value = null
  try {
    organizations.value = await refdata.organizationsOf(kato.value, undefined)
    try {
      series.value = await queue.organization(moCode.value, profile.value, 90)
    } catch (e) {
      if (!(e instanceof ApiError && e.status === 404)) throw e
    }
    regionPrediction.value = await queue.predict({ regionKato: kato.value, profileCode: profile.value })
    anomalies.value = (await analytics.anomalies({ regionKato: kato.value, moCode: moCode.value, status: 'open', size: 50 })).items
  } catch (e) {
    error.value = e
  }
  try {
    equipment.value = await analytics.equipmentForOrganization(moCode.value)
  } catch {
    equipment.value = null
  }
}

async function resolve(id: string, comment: string, status: 'acknowledged' | 'dismissed') {
  try {
    await analytics.ack(id, comment, status)
    anomalies.value = anomalies.value.filter((a) => a.id !== id)
    toast.add({ severity: status === 'acknowledged' ? 'success' : 'info', summary: t(status === 'acknowledged' ? 'gov.map.ackToast' : 'gov.map.dismissToast'), life: 2500 })
  } catch (e) {
    error.value = e
  }
}

onMounted(async () => {
  await refdata.load()
  if (!profile.value) {
    silentProfile = true
    profile.value = refdata.topProfileCode() // профиль с наибольшим числом направлений, не зашитый код
  }
  await load()
})
let silentProfile = false
watch([moCode, profile], () => {
  if (silentProfile) {
    silentProfile = false
    return
  }
  load()
})
</script>

<template>
  <PageShell :title="shortOrgName(fullName)" :back="{ to: `/gov/regions/${kato}`, label: refdata.regionName(kato) }">
    <template #title-extra> <span class="mono muted code">{{ moCode }}</span></template>
    <template #subtitle>{{ fullName }}<br />{{ refdata.profileName(profile) }}<template v-if="period"> · {{ period }}</template></template>
    <template #actions>
      <SearchSelect v-model="profile" :options="refdata.profiles" option-label="name" option-value="profileCode" size="small" class="w-profile" />
    </template>
    <ErrorBox :error="error" />

    <AppCard :title="t('gov.org.vsRegion')" origin="ml" :origin-note="t('gov.org.vsRegionNote')" data-testid="org-vs-region">
      <p v-if="!series" class="muted">{{ t('gov.org.noQueueSeries') }}</p>
      <table v-else-if="regionPrediction" class="dense-table pairs">
        <thead><tr><th></th><th class="num">{{ t('gov.org.orgShort') }}</th><th class="num">{{ refdata.regionName(kato) }}</th><th class="num">Δ</th></tr></thead>
        <tbody>
          <tr v-for="p in pairs" :key="p.key">
            <td>{{ t('gov.org.pair.' + p.key) }}</td>
            <td class="num big">{{ p.format(p.org) }}</td>
            <td class="num">{{ p.format(p.region) }}</td>
            <td class="num" :class="p.org != null && p.region != null ? (p.org > p.region ? 'delta-up' : 'delta-down') : ''">{{ p.org != null && p.region != null ? p.delta(p.org, p.region) : '—' }}</td>
          </tr>
        </tbody>
      </table>
      <p v-else class="muted">{{ t('gov.org.regionForecastUnavailable') }}</p>
      <p v-if="series && regionPrediction" class="verdict" :class="worse ? 'delta-up' : 'delta-down'">{{ worse ? t('gov.org.worseThanRegion') : t('gov.org.notWorseThanRegion') }}</p>
    </AppCard>

    <Tabs v-model:value="tab" class="org-tabs">
      <TabList>
        <Tab value="queue">{{ t('gov.region.tabQueue') }}</Tab>
        <Tab value="signals">{{ t('gov.org.signals') }} <span class="muted">· {{ anomalies.length }}</span></Tab>
      </TabList>
      <TabPanels>
        <TabPanel value="queue">
          <template v-if="series">
            <p class="muted small">{{ t('gov.org.factHeader') }} <OriginTag kind="formula" /></p>
            <KpiRow>
              <KpiTile :value="series.days.at(-1)?.queueLen ?? '—'" :label="t('gov.region.queueNow')" />
              <KpiTile :value="days(series.throughput?.throughputPerDay, 1)" :label="t('gov.org.admissionsPerDay')" />
              <KpiTile :value="pct(regionPrediction?.pWithin30Days)" :label="t('gov.org.within30')" />
              <KpiTile :value="equipment ? String(equipment.units) : '—'" :label="t('gov.org.equipmentUnits')" :hint="equipment ? undefined : t('gov.org.equipmentUnavailable')" />
            </KpiRow>
            <div style="margin-top: 16px"><QueueChart :days="series.days" :title="t('gov.org.queueChart90')" /></div>
          </template>
          <p v-else class="muted">{{ t('gov.org.noQueueSeries') }}</p>
        </TabPanel>
        <TabPanel value="signals">
          <AnomalyFeed :items="anomalies" :can-ack="auth.hasRole('chief', 'regulator')" @ack="(id, c) => resolve(id, c, 'acknowledged')" @dismiss="(id, c) => resolve(id, c, 'dismissed')" />
        </TabPanel>
      </TabPanels>
    </Tabs>
  </PageShell>
</template>

<style scoped>
.code { font-weight: 400; font-size: 0.75em; }
.w-profile { min-width: 240px; }
.pairs { max-width: 640px; }
.pairs .big { font-weight: 600; font-size: 1.05rem; }
.verdict { margin: 12px 0 0; font-weight: 600; }
.org-tabs { margin-top: 16px; }
.org-tabs :deep(.p-tabpanels) { padding: var(--dm-space-4) 0 0; background: transparent; }
</style>
