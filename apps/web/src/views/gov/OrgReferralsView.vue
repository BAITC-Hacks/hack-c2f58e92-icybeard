<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute } from 'vue-router'
import { ApiError } from '@/api/client'
import { journal, queue } from '@/api/endpoints'
import type { OrganizationSeries, WorklistItem } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import OriginLegend from '@/components/OriginLegend.vue'
import AppCard from '@/components/ui/AppCard.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import KpiRow from '@/components/ui/KpiRow.vue'
import KpiTile from '@/components/ui/KpiTile.vue'
import PageShell from '@/components/ui/PageShell.vue'
import SearchSelect from '@/components/ui/SearchSelect.vue'
import Select from 'primevue/select'
import SelectButton from 'primevue/selectbutton'
import ArrowPager from '@/components/ui/ArrowPager.vue'
import Skeleton from '@/components/ui/Skeleton.vue'
import StatusTag from '@/components/ui/StatusTag.vue'
import { num, pct, shortOrgName } from '@/lib/format'
import { dateShort } from '@/lib/route'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'

/** «Больница · направления и отказы» (W-Org-Referrals): KPI входящих направлений и отказов из ряда очереди
 * организации (queue_daily по профилям), бары по профилям коек; регион прикрепления, причины отказов и время до
 * решения в открытых данных отсутствуют — строки «нет в открытых данных» со сноской «запрос № 6». Список
 * направлений, требующих решения, открыт только врачу (политика doctor): главврачу — пустое состояние. */
const PERIODS = [4, 12] as const
/** Сколько профилей (по числу направлений в справочнике) опрашивается для баров «По профилям коек». */
const PROFILE_LIMIT = 8
/** Порог «выше среднего по стране»: 11 % направлений заканчиваются отказом (тот же, что в refusalWords). */
const REFUSAL_ABOVE = 0.165

const props = defineProps<{ moCode: string }>()
const { t } = useI18n()
const route = useRoute()
const auth = useAuthStore()
const refdata = useRefdataStore()

const kato = computed(() => String(route.query.kato ?? auth.region ?? ''))
const weeks = ref<(typeof PERIODS)[number]>(4)
const profileSort = ref<'count' | 'refusal' | 'name'>('count')
const profile = ref<string>('all')
const seriesByProfile = ref<Record<string, OrganizationSeries>>({})
const pending = ref<WorklistItem[] | null>(null)
const pendingForbidden = ref(false)
const error = ref<unknown>(null)
const loading = ref(true)

const orgName = computed(() => refdata.organizationName(props.moCode))
const profileOptions = computed(() => [{ profileCode: 'all', name: t('common.all') }, ...refdata.profiles])
const asOf = computed(() => Object.values(seriesByProfile.value)[0]?.days.at(-1)?.day ?? '')
const selectedSeries = computed(() => (profile.value === 'all' ? Object.values(seriesByProfile.value) : [seriesByProfile.value[profile.value]].filter((s): s is OrganizationSeries => !!s)))

/** Сумма поля ряда за последние N дней (ряд — по дням, свежие в конце). */
function sumLast(series: OrganizationSeries, field: 'registered' | 'hospitalized' | 'refused', days: number): number {
  return series.days.slice(-days).reduce((acc, d) => acc + d[field], 0)
}
const incoming = computed(() => selectedSeries.value.reduce((acc, s) => acc + sumLast(s, 'registered', weeks.value * 7), 0))
const hospitalized = computed(() => selectedSeries.value.reduce((acc, s) => acc + sumLast(s, 'hospitalized', weeks.value * 7), 0))
const refusals = computed(() => {
  const refused = selectedSeries.value.reduce((acc, s) => acc + sumLast(s, 'refused', weeks.value * 7), 0)
  const outcomes = refused + selectedSeries.value.reduce((acc, s) => acc + sumLast(s, 'hospitalized', weeks.value * 7), 0)
  return outcomes > 0 ? refused / outcomes : null
})
/** По профилям: сколько направлений пришло и чем закончились — госпитализация (зелёный) или отказ (красный). */
interface ProfileRow { code: string; name: string; incoming: number; hospitalized: number; refused: number; waiting: number; refusalShare: number | null }
const profileRows = computed<ProfileRow[]>(() =>
  Object.entries(seriesByProfile.value)
    .map(([code, s]) => {
      const n = weeks.value * 7
      const hosp = sumLast(s, 'hospitalized', n)
      const ref = sumLast(s, 'refused', n)
      const incoming = sumLast(s, 'registered', n)
      // «ждут» — пришедшие за период без решения: разница пришедших и решённых, не меньше нуля
      return { code, name: refdata.profileName(code), incoming, hospitalized: hosp, refused: ref, waiting: Math.max(0, incoming - hosp - ref), refusalShare: hosp + ref > 0 ? ref / (hosp + ref) : null }
    })
    .sort((a, b) => (profileSort.value === 'name' ? a.name.localeCompare(b.name, 'ru') : profileSort.value === 'refusal' ? (b.refusalShare ?? 0) - (a.refusalShare ?? 0) : b.incoming - a.incoming)))
const PROFILE_PAGE = 5
/** Доля отказов цветом относительно средней по больнице: заметно выше — красным, немного выше — жёлтым. */
const avgRefusal = computed(() => {
  const decided = profileRows.value.reduce((a, r) => a + r.hospitalized + r.refused, 0)
  return decided ? profileRows.value.reduce((a, r) => a + r.refused, 0) / decided : 0
})
const refusalTone = (share: number | null) => (share === null || !avgRefusal.value ? 'neutral' : share >= avgRefusal.value * 1.4 ? 'danger' : share >= avgRefusal.value * 1.1 ? 'warn' : 'ok')
const profilePage = ref(0)
const profilePageRows = computed(() => profileRows.value.slice(profilePage.value * PROFILE_PAGE, (profilePage.value + 1) * PROFILE_PAGE))
const profileSortOptions = computed(() => (['count', 'refusal', 'name'] as const).map((v) => ({ value: v, label: t('gov.orgReferrals.profileSort.' + v) })))
/** Итог одной строкой: средняя доля отказов и профиль, где отказывают чаще всего. */
const profileSummary = computed(() => {
  const decided = profileRows.value.reduce((a, r) => a + r.hospitalized + r.refused, 0)
  if (!decided) return ''
  const avg = profileRows.value.reduce((a, r) => a + r.refused, 0) / decided
  const top = [...profileRows.value].filter((r) => r.refusalShare !== null).sort((a, b) => (b.refusalShare ?? 0) - (a.refusalShare ?? 0))[0]
  const base = t('gov.orgReferrals.profileSummary', { pct: pct(avg) })
  return top && profileRows.value.length > 1 ? `${base} ${t('gov.orgReferrals.profileTop', { name: top.name.toLowerCase(), pct: pct(top.refusalShare) })}` : base
})
watch(() => profileSort.value, () => (profilePage.value = 0))
const periodOptions = computed(() => PERIODS.map((w) => ({ value: w, label: t('gov.orgReferrals.periodOption', { weeks: w }) })))

async function loadSeries() {
  loading.value = true
  error.value = null
  const profiles = [...refdata.profiles].sort((a, b) => b.referrals - a.referrals).slice(0, PROFILE_LIMIT).map((p) => p.profileCode)
  if (profile.value !== 'all' && !profiles.includes(profile.value)) profiles.push(profile.value)
  try {
    const found = await Promise.all(
      profiles.map((code) =>
        queue.organization(props.moCode, code, 90).then((s) => [code, s] as const).catch((e: unknown) => {
          if (e instanceof ApiError && e.status === 404) return null
          throw e
        }),
      ),
    )
    seriesByProfile.value = Object.fromEntries(found.filter((x): x is readonly [string, OrganizationSeries] => x !== null))
  } catch (e) {
    error.value = e
  } finally {
    loading.value = false
  }
}

async function loadPending() {
  try {
    const list = await journal.worklist({ regionKato: kato.value || undefined })
    pending.value = list.items.filter((i) => i.moCode === props.moCode).slice(0, 5)
  } catch (e) {
    if (e instanceof ApiError && (e.status === 403 || e.status === 401)) pendingForbidden.value = true
    else pending.value = []
  }
}

onMounted(async () => {
  await refdata.load()
  await refdata.resolveOrganizations([props.moCode]).catch(() => undefined)
  await Promise.all([loadSeries(), loadPending()])
})
watch(() => props.moCode, () => Promise.all([loadSeries(), loadPending()]))
watch(profile, () => {
  if (profile.value !== 'all' && !seriesByProfile.value[profile.value]) loadSeries()
})
</script>

<template>
  <PageShell :title="t('gov.orgReferrals.title')" :back="{ to: `/gov/organizations/${moCode}`, label: t('nav.short.orgOverview') }">
    <template #subtitle>
      <span :title="orgName">{{ shortOrgName(orgName) }}</span> · <span class="mono">{{ moCode }}</span> · {{ t('gov.orgReferrals.weeks', { weeks }) }}<template v-if="asOf"> · {{ t('shell.asOf', { date: dateShort(asOf) }) }}</template> · {{ profile === 'all' ? t('common.all').toLowerCase() : refdata.profileName(profile) }}
      <div class="page-legend"><OriginLegend /></div>
    </template>
    <template #actions>
      <Select v-model="weeks" :options="periodOptions" option-label="label" option-value="value" size="small" class="period-select" :aria-label="t('gov.orgReferrals.periodLabel')" />
      <SearchSelect v-model="profile" :options="profileOptions" option-label="name" option-value="profileCode" size="small" class="profile-select" />
    </template>
    <ErrorBox :error="error" />

    <KpiRow data-testid="org-referrals-kpis">
      <KpiTile label-first :value="num(incoming)" :label="t('gov.orgReferrals.kpiIncomingLabel', { weeks })" :hint="t('gov.orgReferrals.kpiIncomingHint')" :loading="loading" />
      <KpiTile label-first :value="refusals === null ? '—' : pct(refusals)" :label="t('gov.orgReferrals.kpiRefusalsLabel', { weeks })" :hint="t('gov.org.kpiRefusalHint')" :loading="loading" :tone="refusals !== null && refusals > REFUSAL_ABOVE ? 'danger' : undefined" :chip="refusals !== null && refusals > REFUSAL_ABOVE ? t('gov.orgReferrals.aboveAverage') : undefined" />
      <KpiTile label-first :value="num(hospitalized)" :label="t('gov.orgReferrals.kpiHospitalizedLabel', { weeks })" :hint="t('gov.orgReferrals.kpiHospitalizedHint')" :loading="loading" />
    </KpiRow>

    <div class="two-col">
      <AppCard :title="t('gov.orgReferrals.profilesTitle')">
        <template #header><SelectButton v-model="profileSort" :options="profileSortOptions" option-label="label" option-value="value" size="small" :allow-empty="false" /></template>
        <Skeleton v-if="loading" :lines="4" />
        <p v-else-if="profileRows.length === 0" class="muted">{{ t('gov.orgReferrals.profilesEmpty') }}</p>
        <template v-else>
          <p v-if="profileSummary" class="profile-summary">{{ profileSummary }}</p>
          <div :class="{ 'paged-box': profileRows.length > PROFILE_PAGE }"><table class="dense-table profiles-table">
            <thead>
              <tr><th>{{ t('gov.orgReferrals.colProfile') }}</th><th class="num">{{ t('gov.orgReferrals.statIncoming') }}</th><th class="num">{{ t('gov.orgReferrals.statHospitalized') }}</th><th class="num">{{ t('gov.orgReferrals.statRefused') }}</th><th class="num">{{ t('gov.orgReferrals.statRefusalShare') }}</th><th class="num">{{ t('gov.orgReferrals.statWaiting') }}</th></tr>
            </thead>
            <tbody>
              <tr v-for="row in profilePageRows" :key="row.code">
                <td class="profile-name" :title="row.name">{{ row.name }}</td>
                <td class="num tabular">{{ num(row.incoming) }}</td>
                <td class="num tabular">{{ num(row.hospitalized) }}</td>
                <td class="num tabular">{{ num(row.refused) }}</td>
                <td class="num"><StatusTag v-if="row.refusalShare !== null" :value="pct(row.refusalShare)" :tone="refusalTone(row.refusalShare)" /><span v-else class="muted">—</span></td>
                <td class="num tabular">{{ num(row.waiting) }}</td>
              </tr>
            </tbody>
          </table></div>
          <ArrowPager v-model:page="profilePage" :total="profileRows.length" :size="PROFILE_PAGE" />
        </template>
      </AppCard>
      <AppCard :title="t('gov.orgReferrals.pendingTitle')" origin="ml" data-testid="org-pending">
        <template #header><RouterLink class="link-arrow small" :to="{ name: 'decisions' }">{{ t('gov.orgReferrals.allInJournal') }}</RouterLink></template>
        <p class="caption lead">{{ t('gov.orgReferrals.pendingNote') }}</p>
        <EmptyState v-if="pendingForbidden" :title="t('gov.orgReferrals.noAccessTitle')" :text="t('gov.orgReferrals.noAccessText')" icon="pi pi-lock" />
        <Skeleton v-else-if="pending === null" :lines="3" />
        <p v-else-if="pending.length === 0" class="muted">{{ t('gov.orgReferrals.noPending') }}</p>
        <div v-else class="rows pending-list">
          <div v-for="item in pending" :key="item.patientRef" class="row">
            <div class="row-main">
              <div class="mono">{{ item.patientRef }}</div>
              <div class="row-sub">{{ refdata.profileName(item.profileCode) }}</div>
            </div>
            <div class="row-value">
              <span class="tabular">{{ item.daysWaiting }} {{ t('common.days') }}</span>
              <StatusTag v-if="item.riskFlags.includes('refusal_risk')" :value="t('route.flags.refusal_risk')" tone="danger" />
            </div>
          </div>
        </div>
      </AppCard>
    </div>

  </PageShell>
</template>

<style scoped>
.page-legend { display: flex; margin-top: 8px; }
.profile-select { min-width: 220px; }
.two-col { display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); gap: var(--dm-space-4); align-items: stretch; }
.lead { margin: -4px 0 14px; line-height: 1.45; }
.pending-list { max-height: 420px; overflow-y: auto; }
.period-select { min-width: 150px; }
.footnote { margin-top: var(--dm-space-4); }
.profiles-table td { height: 44px; }
.profile-summary { margin: 0 0 6px; line-height: 1.5; }
.nowrap { white-space: nowrap; }
.paged-box { min-height: 268px; }
.profile-name { max-width: 280px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.strong { font-weight: var(--fw-bold); }
@media (max-width: 1000px) { .two-col { grid-template-columns: 1fr; } }
</style>
