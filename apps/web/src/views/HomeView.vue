<script setup lang="ts">
import Message from 'primevue/message'
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute, useRouter } from 'vue-router'
import { medicines, queue } from '@/api/endpoints'
import type { CheckResponse, PredictResponse } from '@/api/types'
import LoginPanel from '@/components/app/LoginPanel.vue'
import AppCard from '@/components/ui/AppCard.vue'
import PageShell from '@/components/ui/PageShell.vue'
import Skeleton from '@/components/ui/Skeleton.vue'
import { days, num } from '@/lib/format'
import { readPref, WAIT_PREFS } from '@/lib/prefs'
import { roleHome } from '@/router/roles'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'

/** Ячейка тизера «Сколько ждут» на главной: та же демонстрационная пара регион/профиль, что в прогонах стенда
 * (г. Алматы · офтальмология); если гость уже выбирал на /wait — берётся его выбор. */
const TEASER_REGION = '75'
const TEASER_PROFILE = '381'

const { t } = useI18n()
const auth = useAuthStore()
const route = useRoute()
const router = useRouter()
const refdata = useRefdataStore()

const teaserRegion = readPref(WAIT_PREFS.region) ?? TEASER_REGION
const teaserProfile = readPref(WAIT_PREFS.profile) ?? TEASER_PROFILE
const wait = ref<PredictResponse | null>(null)
const rx = ref<{ nosologyId: string; check: CheckResponse } | null>(null)
const teasersBusy = ref(true)

const denied = computed(() => (typeof route.query.denied === 'string' ? route.query.denied : ''))
/** Роли, которым открыта страница из ?denied — подсказка над кнопкой входа. */
const deniedRoles = computed(() => {
  if (!denied.value) return ''
  const roles = router.resolve(denied.value).meta.roles ?? []
  return roles.map((r) => t('decision.role.' + r)).join(' / ')
})
const guestHint = computed(() => {
  if (!denied.value || auth.isAuthenticated) return undefined
  return deniedRoles.value ? t('home.deniedGuestRole', { page: denied.value, roles: deniedRoles.value }) : t('home.deniedGuest', { page: denied.value })
})

onMounted(async () => {
  try {
    await refdata.load()
    const [p, nos] = await Promise.all([queue.predict({ regionKato: teaserRegion, profileCode: teaserProfile }), medicines.nosologies(1)])
    wait.value = p
    const nosologyId = nos.items[0]?.nosologyId
    if (nosologyId) rx.value = { nosologyId, check: await medicines.check({ nosologyId }) }
  } catch {
    // тизеры — необязательная витрина: без API главная остаётся страницей входа
  } finally {
    teasersBusy.value = false
  }
})
</script>

<template>
  <PageShell :title="t('home.title')" :lead="t('home.lead')">
    <Message v-if="denied && auth.isAuthenticated" severity="warn" :closable="false" data-testid="denied">
      {{ deniedRoles ? t('home.deniedRoleNamed', { page: denied, roles: deniedRoles }) : t('home.deniedRole', { page: denied }) }}
      <RouterLink :to="roleHome(auth.role, auth.region)">{{ t('home.goHome') }}</RouterLink>
    </Message>
    <div class="home-grid">
      <LoginPanel v-if="!auth.isAuthenticated" :hint="guestHint" />
      <AppCard v-else :title="t('home.continueTitle')" :to="roleHome(auth.role, auth.region)" data-testid="continue">
        <p class="muted">{{ auth.actor }}<template v-if="auth.role"> · {{ t('decision.role.' + auth.role) }}</template></p>
      </AppCard>

      <div class="teasers">
        <AppCard :title="t('nav.short.wait')" :to="{ path: '/wait', query: { region: teaserRegion, profile: teaserProfile } }" data-testid="teaser-wait">
          <Skeleton v-if="teasersBusy && !wait" kind="kpi" />
          <template v-else-if="wait">
            <div class="teaser-number tabular">≈ {{ days(wait.p50Days) }} <span class="unit">{{ t('common.days') }}</span></div>
            <p class="muted">{{ t('home.teaserWait', { region: refdata.regionName(teaserRegion), profile: refdata.profileName(teaserProfile).toLowerCase() }) }}</p>
          </template>
          <p v-else class="muted">{{ t('home.citizen') }}</p>
        </AppCard>
        <AppCard :title="t('nav.medicines')" to="/medicines" data-testid="teaser-medicines">
          <Skeleton v-if="teasersBusy && !rx" kind="kpi" />
          <template v-else-if="rx">
            <div class="teaser-number">{{ rx.check.covered ? t('home.teaserCovered') : t('home.teaserNotCovered') }}</div>
            <p class="muted">{{ t('home.teaserRx', { nosology: rx.nosologyId, program: rx.check.program ?? '—', days: days(rx.check.fillDaysP50) }) }}</p>
          </template>
          <p v-else class="muted">{{ t('home.medicines') }}</p>
        </AppCard>
      </div>
    </div>

    <div class="facts-row" data-testid="data-facts">
      <div class="fact"><div class="fact-value tabular">{{ refdata.referralsTotal ? num(Math.round(refdata.referralsTotal / 1000)) : '—' }} {{ t('home.thousand') }}</div><div class="muted small">{{ t('home.factReferrals') }}</div></div>
      <div class="fact"><div class="fact-value tabular">{{ refdata.regionsCount || '—' }}</div><div class="muted small">{{ t('home.factRegions') }}</div></div>
      <div class="fact"><div class="fact-value">{{ t('home.factPeriodValue') }}</div><div class="muted small">{{ t('home.factPeriod') }}</div></div>
      <p class="muted small provenance">{{ t('home.factsNote') }}</p>
    </div>
  </PageShell>
</template>

<style scoped>
.home-grid { display: grid; grid-template-columns: minmax(280px, 380px) 1fr; gap: var(--dm-space-4); align-items: start; }
.teasers { display: grid; gap: var(--dm-space-4); }
.teaser-number { font-size: 1.8rem; font-weight: 600; letter-spacing: -0.01em; }
.teaser-number .unit { font-size: 1rem; color: var(--dm-muted); font-weight: 400; }
.facts-row { display: flex; flex-wrap: wrap; gap: var(--dm-space-5); margin-top: var(--dm-space-5); padding-top: var(--dm-space-4); border-top: 1px solid var(--dm-hairline); align-items: flex-start; }
.fact-value { font-size: 1.4rem; font-weight: 600; }
.provenance { flex-basis: 100%; margin: 0; }
@media (max-width: 760px) { .home-grid { grid-template-columns: 1fr; } }
</style>
