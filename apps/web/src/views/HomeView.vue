<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute } from 'vue-router'
import { medicines, pub, queue } from '@/api/endpoints'
import type { LoginExamples } from '@/api/types'
import LoginPanel from '@/components/app/LoginPanel.vue'
import OriginTag from '@/components/OriginTag.vue'
import StatusTag from '@/components/ui/StatusTag.vue'
import { days, num, pct } from '@/lib/format'
import { readPref, WAIT_PREFS } from '@/lib/prefs'
import { useRefdataStore } from '@/stores/refdata'

/** Страница входа (W-Home) — единственная страница без сессии (кроме регистрации организации, приглашения и памятки по
 * QR). Слева заголовок, подводка, карточка «Вход» и «Зарегистрировать организацию»; справа две плавающие
 * карточки-примера («Сколько ждут», «Проверка рецепта») — статичные примеры из GET /public/login-examples (пока
 * эндпоинта нет — из публичных прогноза и проверки рецепта), не ссылки; внизу ряд фактов о данных. Вошедший сюда не
 * попадает: защита маршрутов уводит его на свой экран. */
const DEFAULT_REGION = '75'

const { t } = useI18n()
const route = useRoute()
const refdata = useRefdataStore()

const examples = ref<LoginExamples | null>(null)

const denied = computed(() => (typeof route.query.denied === 'string' ? route.query.denied : ''))
const loginHint = computed(() => (denied.value ? t('home.deniedGuest', { page: denied.value }) : undefined))

/** Прежний источник примеров: прогноз очереди и проверка самого частого МНН (публичные эндпоинты). */
async function legacyExamples(): Promise<LoginExamples> {
  const region = readPref(WAIT_PREFS.region) ?? DEFAULT_REGION
  const profile = readPref(WAIT_PREFS.profile) ?? refdata.topProfileCode()
  const [wait, rx] = await Promise.all([
    profile ? queue.predict({ regionKato: region, profileCode: profile }).catch(() => null) : Promise.resolve(null),
    medicines.topMnn(1).then(async (r) => {
      const top = r.items[0]
      return top ? { top, check: await medicines.check({ mnnId: top.mnnId }) } : null
    }).catch(() => null),
  ])
  return {
    wait: wait ? { regionName: refdata.regionName(region), profileName: refdata.profileName(profile), p50Days: wait.p50Days, p90Days: wait.p90Days, within30: wait.pWithin30Days } : null,
    rx: rx ? { mnn: rx.top.mnnId, covered: rx.check.covered, fillP50: rx.check.fillDaysP50, fillP90: rx.check.fillDaysP90 } : null,
  }
}

/** МНН из API приходит кодом («286») — подпись «МНН 286», название — как есть. */
const mnnTitle = (mnn: string) => (/^\d+$/.test(mnn) ? t('medicines.mnnShort', { id: mnn }) : mnn)

onMounted(async () => {
  // примеры и факты — витрина: без API страница остаётся страницей входа
  await refdata.load().catch(() => undefined)
  try {
    examples.value = await pub.loginExamples()
  } catch {
    examples.value = await legacyExamples().catch(() => null)
  }
})
</script>

<template>
  <main class="page home">
    <div class="hero-grid">
      <div class="intro">
        <h1>{{ t('home.headline') }}</h1>
        <p class="lead intro-lead">{{ t('home.lead') }}</p>
        <LoginPanel :hint="loginHint" />
        <p class="signup-line small">{{ t('home.signupLead') }} <RouterLink class="link-arrow small" to="/signup" data-testid="signup-link">{{ t('home.signup') }}</RouterLink></p>
      </div>

      <div class="examples">
        <section class="card example example-wait" data-testid="example-wait">
          <div class="example-head"><span class="eyebrow">{{ t('home.exampleWait') }}</span><span class="spacer" /><OriginTag kind="ml" /></div>
          <span class="muted small">{{ examples?.wait ? `${examples.wait.regionName} · ${examples.wait.profileName.toLowerCase()}` : '—' }}</span>
          <div class="hero-value tabular"><span class="hero-number">{{ examples?.wait ? `≈ ${days(examples.wait.p50Days)}` : '—' }}</span><span class="hero-unit">{{ t('common.days') }}</span></div>
          <span class="hero-label">{{ t('hero.half') }}</span>
          <span v-if="examples?.wait" class="muted small tabular">{{ t('hero.nineOfTen', { days: days(examples.wait.p90Days) }) }} · {{ t('hero.within30', { pct: pct(examples.wait.within30) }) }}</span>
          <span class="caption">{{ t('home.exampleTag') }}</span>
        </section>

        <section class="card example example-rx" data-testid="example-rx">
          <div class="example-head">
            <span class="eyebrow">{{ t('home.exampleRx') }}</span><span class="spacer" />
            <StatusTag v-if="examples?.rx" :value="examples.rx.covered ? t('medicines.covered') : t('medicines.notCovered')" :tone="examples.rx.covered ? 'ok' : 'warn'" />
          </div>
          <span class="rx-title">{{ examples?.rx ? mnnTitle(examples.rx.mnn) : '—' }}</span>
          <div class="rx-row"><span class="muted">{{ t('home.rxMedian') }}</span><span class="tabular rx-value">{{ examples?.rx && examples.rx.fillP50 !== null ? `${days(examples.rx.fillP50)} ${t('common.days')}` : '—' }}</span></div>
          <div class="rx-row last"><span class="muted">{{ t('home.rxNineOfTen') }}</span><span class="tabular rx-value">{{ examples?.rx && examples.rx.fillP90 !== null ? t('home.rxUpTo', { days: days(examples.rx.fillP90) }) : '—' }}</span></div>
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
.signup-line { margin: -4px 0 0; color: var(--dm-muted); display: flex; gap: 8px; align-items: center; flex-wrap: wrap; }
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
