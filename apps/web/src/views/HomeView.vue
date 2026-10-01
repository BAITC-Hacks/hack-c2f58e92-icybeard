<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute, useRouter } from 'vue-router'
import { medicines, pub, queue } from '@/api/endpoints'
import type { LoginExamples } from '@/api/types'
import LoginPanel from '@/components/app/LoginPanel.vue'
import { days, num } from '@/lib/format'
import { readPref, WAIT_PREFS } from '@/lib/prefs'
import { useRefdataStore } from '@/stores/refdata'

/** Главная без входа (доска home-prop-5, утверждена): градиент на каркасе (.shell--hero), слева H1, подводка,
 * карточка «Вход» с синей полосой сверху и ряд фактов о данных; справа обезличенный путь пациента из 5 этапов
 * (названия — существующие ключи route.stage.*), в этапе «В листе ожидания» — реальный медианный срок из
 * GET /public/login-examples (пока эндпоинта нет — из публичных прогноза и проверки рецепта). Вошедший сюда
 * не попадает: защита маршрутов уводит его на свой экран. */
const DEFAULT_REGION = '75'

const { t } = useI18n()
const route = useRoute()
const router = useRouter()
const refdata = useRefdataStore()

const examples = ref<LoginExamples | null>(null)

const denied = computed(() => (typeof route.query.denied === 'string' ? route.query.denied : ''))
/** Вместо адреса страницы («/me/route») — её название из меню («Мой путь»); без названия — общая фраза. */
const loginHint = computed(() => {
  if (!denied.value) return undefined
  let title: unknown
  try {
    title = router.resolve(denied.value).meta.title
  } catch {
    title = undefined
  }
  return typeof title === 'string' ? t('home.deniedGuest', { page: t(title) }) : t('home.deniedGuestAny')
})

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

onMounted(async () => {
  // срок в этапе «В листе ожидания» и факты — витрина: без API страница остаётся страницей входа
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
        <LoginPanel :hint="loginHint">
          <template #footer>
            <span class="signup-lead">{{ t('home.signupLead') }}</span>
            <RouterLink class="link-arrow small signup-link" to="/signup" data-testid="signup-link">{{ t('home.signup') }}</RouterLink>
          </template>
        </LoginPanel>
        <div class="facts-row" data-testid="data-facts">
          <div class="fact"><span class="fact-value tabular">{{ refdata.referralsTotal ? `${num(Math.round(refdata.referralsTotal / 1000))} ${t('home.thousand')}` : '—' }}</span><span class="fact-label">{{ t('home.factReferrals') }}</span></div>
          <div class="fact"><span class="fact-value tabular">{{ refdata.regionsCount || '—' }}</span><span class="fact-label">{{ t('home.factRegions') }}</span></div>
          <div class="fact"><span class="fact-value">{{ t('home.factPeriodValue') }}</span><span class="fact-label">{{ t('home.factPeriod') }}</span></div>
        </div>
        <span class="caption provenance">{{ t('home.factsNote') }}</span>
      </div>

      <ol class="path" data-testid="patient-path">
        <li class="step">
          <span class="node done" aria-hidden="true"><i class="pi pi-check" /></span>
          <div class="step-title">{{ t('route.stage.referral_issued') }}</div>
          <div class="step-note">{{ t('home.path.issuedNote') }}</div>
        </li>
        <li class="step">
          <span class="node done" aria-hidden="true"><i class="pi pi-check" /></span>
          <div class="step-title">{{ t('route.stage.examination') }}</div>
          <div class="step-note">{{ t('home.path.examNote') }}</div>
        </li>
        <li class="step">
          <span class="node done" aria-hidden="true"><i class="pi pi-check" /></span>
          <div class="step-card card" data-testid="example-wait">
            <span class="step-kicker">{{ t('route.stage.waitlisted') }}</span>
            <div class="wait-value tabular">
              <span class="wait-number">{{ examples?.wait ? `≈${days(examples.wait.p50Days)}` : '—' }}</span>
              <span class="wait-unit">{{ t('common.days') }} · {{ t('hero.half') }}</span>
            </div>
            <span class="wait-note">{{ t('home.path.waitNote') }}</span>
          </div>
        </li>
        <li class="step">
          <span class="node current" aria-hidden="true"><span class="node-dot" /></span>
          <div class="step-card assigned">
            <span class="step-kicker accent">{{ t('route.stage.date_assigned') }}</span>
            <span class="assigned-text">{{ t('home.path.assignedNote') }}</span>
          </div>
        </li>
        <li class="step">
          <span class="node future" aria-hidden="true" />
          <div class="step-title future">{{ t('route.stage.hospitalized') }}</div>
        </li>
      </ol>
    </div>
  </main>
</template>

<style scoped>
/* home-prop-5: две колонки 1fr/1fr gap 64 в контейнере 1240, градиент даёт .shell--hero */
.home { gap: 24px; }
.hero-grid { display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); gap: 64px; align-items: center; flex: 1; }
.intro { display: flex; flex-direction: column; gap: 24px; }
.intro h1 { font-size: 38px; line-height: 1.22; letter-spacing: -0.02em; max-width: 14ch; }
.intro-lead { font-size: 15.5px; max-width: 40ch; line-height: 1.6; }
.facts-row { display: flex; align-items: flex-end; gap: 40px; flex-wrap: wrap; }
.fact { display: flex; flex-direction: column; gap: 2px; }
.fact-value { font-size: var(--fs-xl); font-weight: var(--fw-extrabold); letter-spacing: -0.01em; line-height: 1.2; }
.fact-label { font-size: var(--fs-sm); color: var(--text-muted); }
.provenance { margin-top: -12px; }

/* путь пациента: узлы 36, линия 2px --border-strong */
.path { list-style: none; margin: 0; padding: 0 0 0 56px; display: flex; flex-direction: column; }
.step { position: relative; margin-bottom: 32px; }
.step:last-child { margin-bottom: 0; }
.node { position: absolute; left: -56px; top: 0; width: 36px; height: 36px; border-radius: 50%; display: flex; align-items: center; justify-content: center; box-sizing: border-box; z-index: 1; }
.node.done { background: var(--accent); color: var(--text-on-accent); }
.node.done .pi { font-size: 14px; font-weight: 700; }
.node.current { background: var(--accent-soft); border: 2.5px solid var(--accent); }
.node-dot { width: 9px; height: 9px; border-radius: 50%; background: var(--accent); }
.node.future { background: var(--surface); border: 2px solid var(--border-strong); }
.step:not(:last-child)::before { content: ''; position: absolute; left: -39px; top: 36px; bottom: -30px; width: 2px; background: var(--border-strong); }
.step-title { font-size: var(--fs-lg); font-weight: var(--fw-extrabold); padding-top: 7px; }
.step-title.future { color: var(--text-faint); font-weight: var(--fw-bold); }
.step-note { font-size: 14px; color: var(--text-muted); margin-top: 3px; }
.step-card { max-width: 400px; display: flex; flex-direction: column; gap: 6px; }
.step-kicker { font-size: var(--fs-base-sm); font-weight: var(--fw-extrabold); color: var(--text-muted); text-transform: uppercase; letter-spacing: 0.04em; margin-bottom: 4px; }
.step-kicker.accent { color: var(--accent-strong); }
.wait-value { display: flex; align-items: baseline; gap: 9px; flex-wrap: wrap; }
.wait-number { font-size: 38px; font-weight: var(--fw-extrabold); letter-spacing: -0.02em; line-height: 1; }
.wait-unit { font-size: var(--fs-md); font-weight: var(--fw-bold); color: var(--text-muted); }
.wait-note { font-size: var(--fs-base); color: var(--text-secondary); }
.step-card.assigned { background: var(--accent-soft); border: 0; border-radius: var(--radius-card); padding: 22px 24px; box-shadow: none; }
.assigned-text { font-size: 16.5px; font-weight: var(--fw-bold); color: var(--text); line-height: 1.5; }
.signup-lead { font-size: var(--fs-base-sm); color: var(--text-muted); }
.signup-link { color: var(--link); }

@media (max-width: 900px) {
  .hero-grid { grid-template-columns: 1fr; gap: 32px; }
  .intro h1 { font-size: 30px; }
  .facts-row { gap: 24px; }
}
</style>
