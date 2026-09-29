<script setup lang="ts">
import { useToast } from 'primevue/usetoast'
import { computed, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute } from 'vue-router'
import { ApiError } from '@/api/client'
import { analytics, queue } from '@/api/endpoints'
import type { Anomaly, EquipmentOrganization, OrganizationItem, OrganizationSeries, PredictResponse } from '@/api/types'
import AnomalyFeed from '@/components/AnomalyFeed.vue'
import ErrorBox from '@/components/ErrorBox.vue'
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

/** Больница · обзор (W-Organization): H1 короткое имя · код, подпись «регион · профиль · данные на», четыре KPI
 * (в листе ожидания, p50 с подписью региона, отказы за 4 недели, госпитализаций в день), слева очередь за 90 дней
 * и ссылки «Направления и отказы» / «Симулятор», справа сигналы и «Сравнение с регионом» (факт организации за 4 недели
 * против прогноза модели по региону). */
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

const fullName = computed(() => organizations.value.find((o) => o.moCode === moCode.value)?.name ?? refdata.organizationName(moCode.value))
const asOf = computed(() => series.value?.days.at(-1)?.day ?? '')
const queueNow = computed(() => series.value?.days.at(-1)?.queueLen ?? null)
/** Очередь две недели назад — для подписи «выше/ниже, чем две недели назад». */
const queueDelta = computed(() => {
  const d = series.value?.days
  if (!d || d.length < 15) return null
  const before = d[d.length - 15]!.queueLen
  return before ? ((d.at(-1)!.queueLen - before) / before) * 100 : null
})

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
    organizations.value = kato.value ? await refdata.organizationsOf(kato.value, undefined) : []
    if (!organizations.value.some((o) => o.moCode === moCode.value)) await refdata.resolveOrganizations([moCode.value]).catch(() => undefined)
    try {
      series.value = await queue.organization(moCode.value, profile.value, 90)
    } catch (e) {
      if (!(e instanceof ApiError && e.status === 404)) throw e
    }
    if (kato.value) regionPrediction.value = await queue.predict({ regionKato: kato.value, profileCode: profile.value })
    anomalies.value = (await analytics.anomalies({ regionKato: kato.value || undefined, moCode: moCode.value, status: 'open', size: 50 })).items
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

/** Профиль по умолчанию: первый по числу направлений в стране, по которому организация есть в очередях своего
 * региона (главврач без ?profile= сразу видит данные, а не прочерки); если ни один из первых восьми не подошёл —
 * самый частый профиль, как раньше. */
async function profileWithData(): Promise<string> {
  if (!kato.value) return refdata.topProfileCode()
  const candidates = [...refdata.profiles].sort((a, b) => b.referrals - a.referrals).slice(0, 8)
  for (const candidate of candidates) {
    const orgs = await refdata.organizationsOf(kato.value, candidate.profileCode).catch(() => [] as OrganizationItem[])
    if (orgs.some((o) => o.moCode === moCode.value)) return candidate.profileCode
  }
  return refdata.topProfileCode()
}

onMounted(async () => {
  await refdata.load()
  if (!profile.value) {
    silentProfile = true
    profile.value = await profileWithData()
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
  <PageShell :title="shortOrgName(fullName)" :back="kato && auth.can('gov.map') ? { to: `/gov/regions/${kato}`, label: refdata.regionName(kato) } : undefined">
    <template #title-extra><span class="code muted">· {{ moCode }}</span></template>
    <template #subtitle><span :title="fullName">{{ refdata.regionName(kato) }}</span> · {{ refdata.profileName(profile) }}<template v-if="asOf"> · {{ t('shell.asOf', { date: dateShort(asOf) }) }}</template></template>
    <template #actions>
      <SearchSelect v-model="profile" :options="refdata.profiles" option-label="name" option-value="profileCode" size="small" class="w-profile" />
    </template>
    <ErrorBox :error="error" />

    <KpiRow data-testid="org-kpis">
      <KpiTile :value="queueNow ?? '—'" :label="t('gov.region.kpiQueue')" origin="formula" :hint="queueDelta !== null ? t('gov.org.queueDelta', { delta: signed(queueDelta, 0) }) : undefined" />
      <KpiTile :value="days(series?.throughput?.waitP50Days)" :unit="t('common.days')" :label="t('gov.org.kpiP50')" origin="formula" :hint="regionPrediction ? t('gov.org.regionHint', { p50: days(regionPrediction.p50Days), p90: days(series?.throughput?.waitP90Days) }) : undefined" />
      <KpiTile :value="pct(series?.throughput?.refusalRate4w)" :label="t('gov.region.refusals4w')" origin="formula" :tone="series?.throughput?.refusalRate4w != null && regionPrediction && series.throughput.refusalRate4w > regionPrediction.pRefusal ? 'danger' : undefined" />
      <KpiTile :value="days(series?.throughput?.throughputPerDay, 1)" :label="t('gov.org.admissionsPerDay')" origin="formula" :hint="equipment ? `${equipment.units} ${t('gov.org.equipmentUnits')}` : undefined" />
    </KpiRow>

    <div class="main-grid">
      <div class="col">
        <AppCard :title="t('gov.org.queueChart90')" origin="formula">
          <template #header><span v-if="series" class="caption">{{ dateShort(series.days[0]!.day) }} — {{ dateShort(series.days.at(-1)!.day) }}</span></template>
          <QueueChart v-if="series" :days="series.days" bare />
          <p v-else class="muted">{{ t('gov.org.noQueueSeries') }}</p>
        </AppCard>
        <div class="links">
          <RouterLink class="card link-card" :to="{ name: 'organization-referrals', params: { moCode }, query: { kato } }"><i class="pi pi-arrow-right" aria-hidden="true" /><span>{{ t('nav.short.orgReferrals') }}</span></RouterLink>
          <RouterLink v-if="auth.can('gov.simulator')" class="card link-card" :to="{ name: 'simulator', query: { region: kato, profile } }"><i class="pi pi-chart-line" aria-hidden="true" /><span>{{ t('gov.org.toSimulator') }}</span></RouterLink>
        </div>
      </div>

      <div class="col">
        <AppCard :title="t('gov.org.signals')" origin="ml">
          <template #header><span class="caption">{{ anomalies.length }}</span></template>
          <AnomalyFeed :items="anomalies" :can-ack="auth.canAny(['gov.map', 'org.cabinet'])" @ack="(id, c) => resolve(id, c, 'acknowledged')" @dismiss="(id, c) => resolve(id, c, 'dismissed')" />
        </AppCard>

        <AppCard :title="t('gov.org.vsRegion')" origin="ml" :origin-note="t('gov.org.vsRegionNote')" data-testid="org-vs-region">
          <p v-if="!series" class="muted">{{ t('gov.org.noQueueSeries') }}</p>
          <table v-else-if="regionPrediction" class="dense-table">
            <thead><tr><th></th><th class="num">{{ t('gov.org.colOurs') }}</th><th class="num">{{ t('gov.org.colRegion') }}</th><th class="num">Δ</th></tr></thead>
            <tbody>
              <tr v-for="p in pairs" :key="p.key">
                <td>{{ t('gov.org.pair.' + p.key) }}</td>
                <td class="num strong">{{ p.format(p.org) }} <span v-if="p.org != null && p.region != null" :class="p.org > p.region ? 'delta-up' : 'delta-down'">{{ p.org > p.region ? '↑' : '↓' }}</span></td>
                <td class="num">{{ p.format(p.region) }}</td>
                <td class="num" :class="p.org != null && p.region != null ? (p.org > p.region ? 'delta-up' : 'delta-down') : ''">{{ p.org != null && p.region != null ? p.delta(p.org, p.region) : '—' }}</td>
              </tr>
            </tbody>
          </table>
          <p v-else class="muted">{{ t('gov.org.regionForecastUnavailable') }}</p>
          <p v-if="series && regionPrediction" class="verdict small" :class="worse ? 'delta-up' : 'delta-down'">{{ worse ? t('gov.org.worseThanRegion') : t('gov.org.notWorseThanRegion') }}</p>
          <p class="caption" style="margin: 8px 0 0">{{ t('gov.org.legendCompare') }}</p>
        </AppCard>
      </div>
    </div>
  </PageShell>
</template>

<style scoped>
.code { font-weight: 400; font-size: var(--dm-text-lg); }
.w-profile { min-width: 240px; }
.main-grid { display: grid; grid-template-columns: minmax(0, 1.4fr) minmax(0, 1fr); gap: var(--dm-space-4); align-items: start; }
.col { display: flex; flex-direction: column; gap: var(--dm-space-4); min-width: 0; }
.links { display: grid; grid-template-columns: 1fr 1fr; gap: var(--dm-space-4); }
.link-card { display: flex; align-items: center; gap: 12px; padding: 16px 24px; text-decoration: none; color: var(--accent-strong); font-weight: var(--fw-bold); font-size: var(--dm-text-sm); }
.link-card i { color: var(--accent); }
.link-card:hover { box-shadow: inset 0 0 0 2px var(--accent); color: var(--accent-strong); }
.strong { font-weight: var(--fw-bold); }
.verdict { margin: 12px 0 0; font-weight: var(--fw-bold); }
@media (max-width: 1000px) { .main-grid { grid-template-columns: 1fr; } .links { grid-template-columns: 1fr; } }
</style>
