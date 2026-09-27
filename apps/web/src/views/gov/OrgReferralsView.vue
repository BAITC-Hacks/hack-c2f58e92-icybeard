<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute } from 'vue-router'
import { ApiError } from '@/api/client'
import { journal, queue } from '@/api/endpoints'
import type { OrganizationSeries, WorklistItem } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import AppCard from '@/components/ui/AppCard.vue'
import BarList, { type BarItem } from '@/components/ui/BarList.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import KpiRow from '@/components/ui/KpiRow.vue'
import KpiTile from '@/components/ui/KpiTile.vue'
import PageShell from '@/components/ui/PageShell.vue'
import SearchSelect from '@/components/ui/SearchSelect.vue'
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
const REASON_KEYS = [0, 1, 2, 3] as const
/** Порог «выше среднего по стране»: 11 % направлений заканчиваются отказом (тот же, что в refusalWords). */
const REFUSAL_ABOVE = 0.165

const props = defineProps<{ moCode: string }>()
const { t } = useI18n()
const route = useRoute()
const auth = useAuthStore()
const refdata = useRefdataStore()

const kato = computed(() => String(route.query.kato ?? auth.region ?? ''))
const weeks = ref<(typeof PERIODS)[number]>(4)
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
const refusals = computed(() => {
  const refused = selectedSeries.value.reduce((acc, s) => acc + sumLast(s, 'refused', weeks.value * 7), 0)
  const outcomes = refused + selectedSeries.value.reduce((acc, s) => acc + sumLast(s, 'hospitalized', weeks.value * 7), 0)
  return outcomes > 0 ? refused / outcomes : null
})
/** Профиль с долей отказов выше остальных — коралловая строка; сравнение только при двух и более профилях. */
const profileBars = computed<BarItem[]>(() => {
  const entries = Object.entries(seriesByProfile.value)
  const rates = entries.map(([, s]) => s.throughput?.refusalRate4w ?? null)
  const known = rates.filter((r): r is number => r !== null)
  const worst = known.length > 1 ? Math.max(...known) : null
  return entries
    .map(([code, s], i) => {
      const value = sumLast(s, 'registered', weeks.value * 7)
      return { key: code, label: refdata.profileName(code), value, display: num(value), highlight: worst !== null && rates[i] === worst }
    })
    .sort((a, b) => b.value - a.value)
})

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
    </template>
    <template #actions>
      <div class="chips">
        <button v-for="w in PERIODS" :key="w" type="button" class="chip-filter" :class="{ active: weeks === w }" @click="weeks = w">{{ t('gov.orgReferrals.period', { weeks: w }) }}</button>
      </div>
      <SearchSelect v-model="profile" :options="profileOptions" option-label="name" option-value="profileCode" size="small" class="profile-select" />
    </template>
    <ErrorBox :error="error" />

    <KpiRow data-testid="org-referrals-kpis">
      <KpiTile :value="num(incoming)" :label="t('gov.orgReferrals.kpiIncoming', { weeks })" origin="formula" :loading="loading" />
      <KpiTile :value="refusals === null ? '—' : pct(refusals)" :label="t('gov.orgReferrals.kpiRefusals', { weeks })" origin="formula" :loading="loading" :tone="refusals !== null && refusals > REFUSAL_ABOVE ? 'danger' : undefined" :chip="refusals !== null && refusals > REFUSAL_ABOVE ? t('gov.orgReferrals.aboveAverage') : undefined" />
      <KpiTile value="—" :label="t('gov.orgReferrals.kpiDecisionTime')" :hint="t('gov.orgReferrals.notInOpenData')" />
    </KpiRow>

    <div class="two-col">
      <div class="col">
        <AppCard :title="t('gov.orgReferrals.originTitle')" origin="formula">
          <p class="muted">{{ t('gov.orgReferrals.notInOpenData') }}</p>
          <p class="caption">{{ t('gov.orgReferrals.originNote') }} · {{ t('gov.orgReferrals.request6') }}</p>
        </AppCard>
        <AppCard :title="t('gov.orgReferrals.profilesTitle')">
          <template #header><span class="caption">{{ t('home.factPeriodValue') }}</span></template>
          <Skeleton v-if="loading" :lines="4" />
          <p v-else-if="profileBars.length === 0" class="muted">{{ t('gov.orgReferrals.profilesEmpty') }}</p>
          <BarList v-else :items="profileBars" />
          <p class="caption note">{{ t('gov.orgReferrals.profilesNote') }}</p>
        </AppCard>
      </div>
      <div class="col">
        <AppCard :title="t('gov.orgReferrals.reasonsTitle')" origin="formula">
          <template #header><span class="caption">{{ t('gov.orgReferrals.weeks', { weeks }) }}</span></template>
          <table class="dense-table">
            <thead><tr><th>{{ t('gov.orgReferrals.reasonCol') }}</th><th class="num">{{ t('gov.orgReferrals.shareCol') }}</th><th class="num">{{ t('gov.orgReferrals.trendCol') }}</th></tr></thead>
            <tbody>
              <tr v-for="k in REASON_KEYS" :key="k" class="reason-row">
                <td>{{ t(`gov.orgReferrals.reasons.${k}`) }}</td>
                <td class="num muted">{{ t('gov.orgReferrals.notInOpenData') }}</td>
                <td class="num muted">—</td>
              </tr>
            </tbody>
          </table>
          <p class="caption note">{{ t('gov.orgReferrals.request6') }}</p>
        </AppCard>
        <AppCard :title="t('gov.orgReferrals.pendingTitle')" origin="ml" data-testid="org-pending">
          <template #header><RouterLink class="link-arrow small" :to="{ name: 'decisions' }">{{ t('gov.orgReferrals.allInJournal') }}</RouterLink></template>
          <EmptyState v-if="pendingForbidden" :title="t('gov.orgReferrals.noAccessTitle')" :text="t('gov.orgReferrals.noAccessText')" icon="pi pi-lock" />
          <Skeleton v-else-if="pending === null" :lines="3" />
          <p v-else-if="pending.length === 0" class="muted">{{ t('gov.orgReferrals.noPending') }}</p>
          <div v-else class="rows">
            <div v-for="item in pending" :key="item.patientRef" class="row">
              <div class="row-main">
                <div class="mono">{{ item.patientRef }}</div>
                <div class="row-sub">{{ refdata.profileName(item.profileCode) }}</div>
              </div>
              <div class="row-value">
                <span>{{ item.daysWaiting }} {{ t('common.days') }}</span>
                <StatusTag v-if="item.riskFlags.includes('refusal_risk')" :value="t('route.flags.refusal_risk')" tone="danger" />
              </div>
            </div>
          </div>
        </AppCard>
      </div>
    </div>
    <p class="caption">{{ t('gov.orgReferrals.footnote') }}</p>
  </PageShell>
</template>

<style scoped>
.profile-select { min-width: 220px; }
.two-col { display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1.4fr); gap: var(--dm-space-4); align-items: start; }
.col { display: flex; flex-direction: column; gap: var(--dm-space-4); min-width: 0; }
.note { margin: 12px 0 0; }
.reason-row td { height: 40px; }
@media (max-width: 1000px) { .two-col { grid-template-columns: 1fr; } }
</style>
