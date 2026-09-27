<script setup lang="ts">
import Message from 'primevue/message'
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute, useRouter } from 'vue-router'
import { medicines, queue } from '@/api/endpoints'
import type { CheckResponse, PredictResponse } from '@/api/types'
import LoginPanel from '@/components/app/LoginPanel.vue'
import OriginTag from '@/components/OriginTag.vue'
import StatusTag from '@/components/ui/StatusTag.vue'
import { days, num, pct } from '@/lib/format'
import { readPref, WAIT_PREFS } from '@/lib/prefs'
import { roleHome } from '@/router/roles'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'

/** Страница входа (W-Home) — единственная страница без сессии (кроме памятки по QR). Слева заголовок, подводка и
 * карточка «Вход»; справа две плавающие карточки-примера («Сколько ждут», «Проверка рецепта») — статичные примеры
 * с публичных эндпоинтов, не ссылки; внизу ряд фактов о данных. Вошедший попадает сюда только с ?denied. */
const DEFAULT_REGION = '75'

const { t } = useI18n()
const auth = useAuthStore()
const route = useRoute()
const router = useRouter()
const refdata = useRefdataStore()

const exampleRegion = readPref(WAIT_PREFS.region) ?? DEFAULT_REGION
const exampleProfile = ref<string>(readPref(WAIT_PREFS.profile) ?? '')
const wait = ref<PredictResponse | null>(null)
const rxId = ref<string | null>(null)
const rx = ref<CheckResponse | null>(null)

const denied = computed(() => (typeof route.query.denied === 'string' ? route.query.denied : ''))
/** Роли, которым открыта страница из ?denied — подсказка над кнопкой входа. */
const deniedRoles = computed(() => {
  if (!denied.value) return ''
  const roles = router.resolve(denied.value).meta.roles ?? []
  return roles.map((r) => t('decision.role.' + r)).join(' / ')
})
const loginHint = computed(() => {
  if (!denied.value || auth.isAuthenticated) return undefined
  return deniedRoles.value ? t('home.deniedGuestRole', { page: denied.value, roles: deniedRoles.value }) : t('home.deniedGuest', { page: denied.value })
})

async function loadWaitExample() {
  if (!exampleProfile.value) exampleProfile.value = refdata.topProfileCode()
  if (!exampleProfile.value) return
  wait.value = await queue.predict({ regionKato: exampleRegion, profileCode: exampleProfile.value })
}

async function loadRxExample() {
  const top = (await medicines.topMnn(1)).items[0]
  if (!top) return
  rxId.value = top.mnnId
  rx.value = await medicines.check({ mnnId: top.mnnId })
}

onMounted(async () => {
  // примеры и факты — витрина: без API страница остаётся страницей входа
  await refdata.load().catch(() => undefined)
  await Promise.all([loadWaitExample().catch(() => (wait.value = null)), loadRxExample().catch(() => (rx.value = null))])
})
</script>

<template>
  <main class="page home">
    <Message v-if="denied && auth.isAuthenticated" severity="warn" :closable="false" data-testid="denied">
      {{ deniedRoles ? t('home.deniedRoleNamed', { page: denied, roles: deniedRoles }) : t('home.deniedRole', { page: denied }) }}
      <RouterLink :to="roleHome(auth.role, auth.region, auth.moCode)">{{ t('home.goHome') }}</RouterLink>
    </Message>

    <div class="hero-grid">
      <div class="intro">
        <h1>{{ t('home.headline') }}</h1>
        <p class="lead intro-lead">{{ t('home.lead') }}</p>
        <LoginPanel :hint="loginHint" />
      </div>

      <div class="examples">
        <section class="card example example-wait" data-testid="example-wait">
          <div class="example-head"><span class="eyebrow">{{ t('home.exampleWait') }}</span><span class="spacer" /><OriginTag kind="ml" /></div>
          <span class="muted small">{{ refdata.regionName(exampleRegion) }} · {{ refdata.profileName(exampleProfile).toLowerCase() }}</span>
          <div class="hero-value tabular"><span class="hero-number">{{ wait ? `≈ ${days(wait.p50Days)}` : '—' }}</span><span class="hero-unit">{{ t('common.days') }}</span></div>
          <span class="hero-label">{{ t('hero.half') }}</span>
          <span v-if="wait" class="muted small tabular">{{ t('hero.nineOfTen', { days: days(wait.p90Days) }) }} · {{ t('hero.within30', { pct: pct(wait.pWithin30Days) }) }}</span>
          <span class="caption">{{ t('home.exampleTag') }}</span>
        </section>

        <section class="card example example-rx" data-testid="example-rx">
          <div class="example-head">
            <span class="eyebrow">{{ t('home.exampleRx') }}</span><span class="spacer" />
            <StatusTag v-if="rx" :value="rx.covered ? t('medicines.covered') : t('medicines.notCovered')" :tone="rx.covered ? 'ok' : 'warn'" />
          </div>
          <span class="rx-title">{{ rxId ? t('medicines.mnnShort', { id: rxId }) : '—' }}</span>
          <div class="rx-row"><span class="muted">{{ t('home.rxMedian') }}</span><span class="tabular rx-value">{{ rx && rx.fillDaysP50 !== null ? `${days(rx.fillDaysP50)} ${t('common.days')}` : '—' }}</span></div>
          <div class="rx-row last"><span class="muted">{{ t('home.rxNineOfTen') }}</span><span class="tabular rx-value">{{ rx && rx.fillDaysP90 !== null ? t('home.rxUpTo', { days: days(rx.fillDaysP90) }) : '—' }}</span></div>
          <span class="caption">{{ t('home.exampleTag') }}</span>
        </section>
      </div>
    </div>

    <div class="facts-row" data-testid="data-facts">
      <div class="fact"><span class="fact-value tabular">{{ refdata.referralsTotal ? `${num(Math.round(refdata.referralsTotal / 1000))} ${t('home.thousand')}` : '—' }}</span><span class="muted small">{{ t('home.factReferrals') }}</span></div>
      <div class="fact"><span class="fact-value tabular">{{ refdata.regionsCount || '—' }}</span><span class="muted small">{{ t('home.factRegions') }}</span></div>
      <div class="fact"><span class="fact-value">{{ t('home.factPeriodValue') }}</span><span class="muted small">{{ t('home.factPeriod') }}</span></div>
      <span class="spacer" />
      <span class="caption provenance">{{ t('home.factsNote') }}</span>
    </div>
  </main>
</template>

<style scoped>
.home { gap: 40px; }
.hero-grid { display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); gap: 48px; align-items: start; }
.intro { display: flex; flex-direction: column; gap: 20px; }
.intro-lead { font-size: var(--dm-text-base); max-width: 52ch; }
.examples { position: relative; min-height: 488px; }
.example { position: absolute; display: flex; flex-direction: column; gap: 12px; }
.example-wait { top: 0; left: 0; width: min(400px, 100%); }
.example-rx { top: 300px; right: 0; width: min(340px, 100%); }
.example-head { display: flex; align-items: center; gap: 10px; }
.spacer { flex: 1; }
.hero-value { display: flex; align-items: baseline; gap: 10px; }
.hero-number { font-size: var(--dm-text-hero); font-weight: 600; letter-spacing: -0.02em; line-height: 1; }
.hero-unit { font-size: var(--dm-text-base); color: var(--dm-muted); }
.hero-label { font-size: var(--dm-text-md); }
.rx-title { font-size: var(--dm-text-lg); font-weight: 500; letter-spacing: -0.01em; }
.rx-row { display: flex; justify-content: space-between; gap: 12px; font-size: var(--dm-text-sm); padding: 8px 0; border-bottom: 1px solid var(--dm-hairline); }
.rx-row.last { border-bottom: 0; padding-bottom: 0; }
.rx-value { font-weight: 500; }
.facts-row { border-top: 1px solid var(--dm-hairline); padding-top: 24px; display: flex; align-items: flex-end; gap: 48px; flex-wrap: wrap; }
.fact { display: flex; flex-direction: column; gap: 4px; }
.fact-value { font-size: 29px; font-weight: 500; letter-spacing: -0.02em; line-height: 1.05; }
@media (max-width: 900px) {
  .hero-grid { grid-template-columns: 1fr; gap: 24px; }
  .examples { min-height: 0; display: grid; gap: 16px; }
  .example { position: static; width: auto; }
  .facts-row { gap: 24px; }
}
</style>
