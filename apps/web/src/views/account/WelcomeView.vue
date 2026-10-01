<script setup lang="ts">
import Button from 'primevue/button'
import { computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import OriginTag from '@/components/OriginTag.vue'
import AppCard from '@/components/ui/AppCard.vue'
import PageShell from '@/components/ui/PageShell.vue'
import { capabilitiesFor } from '@/lib/capabilities'
import { shortOrgName } from '@/lib/format'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'

/** «Первый вход» (W-Onboarding): чек-лист из `/me.onboarding` (почта, второй фактор → Keycloak CONFIGURE_TOTP,
 * профиль, приглашение коллег — если есть admin.users), «Что умеет кабинет» по разрешениям и «Как читать прогнозы».
 * Показывается после первого входа (флаг в localStorage ставится здесь), дальше — из меню «Аккаунт». */
type StepKey = 'emailVerified' | 'otpConfigured' | 'profileChecked' | 'colleaguesInvited'
interface Step { key: StepKey; done: boolean | null; action?: { label: string; primary?: boolean; run: () => void } | { label: string; to: string } }

const { t } = useI18n()
const auth = useAuthStore()
const refdata = useRefdataStore()
const onboarding = computed(() => auth.me?.onboarding ?? null)

const steps = computed<Step[]>(() => {
  const state = onboarding.value
  const list: Step[] = [
    { key: 'emailVerified', done: state?.emailVerified ?? null },
    { key: 'otpConfigured', done: state?.otpConfigured ?? null, action: { label: t('welcome.configure'), primary: true, run: () => void auth.accountAction('CONFIGURE_TOTP') } },
    { key: 'profileChecked', done: state?.profileChecked ?? null, action: { label: t('welcome.open'), to: '/account/profile' } },
  ]
  if (auth.can('admin.users')) list.push({ key: 'colleaguesInvited', done: state?.colleaguesInvited ?? null, action: { label: t('welcome.open'), to: '/admin/users' } })
  return list
})
const doneCount = computed(() => steps.value.filter((s) => s.done).length)
const left = computed(() => steps.value.length - doneCount.value)
/** Имя из клейма given_name; без него — первое слово отображаемого имени, иначе логин. */
const firstName = computed(() => auth.givenName || (auth.displayName ?? auth.me?.displayName ?? '').trim().split(/\s+/)[0] || auth.actor || '')
const place = computed(() => {
  const full = auth.me?.moName ?? (auth.moCode ? refdata.organizationName(auth.moCode) : null)
  const org = full ? shortOrgName(full) : null
  return [org && auth.moCode ? `${org} · ${auth.moCode}` : org, auth.region ? refdata.regionName(auth.region) : null].filter(Boolean).join(' · ')
})
const lead = computed(() => [place.value, onboarding.value ? (left.value > 0 ? t('welcome.stepsLeft', { n: left.value }) : t('welcome.allDone')) : t('welcome.statusUnknown')].filter(Boolean).join(' · '))
const capabilities = computed(() => capabilitiesFor(auth.can, 4).map((c) => ({ ...c, to: c.key === 'cabinet' && auth.moCode ? `/gov/organizations/${auth.moCode}` : c.to })))
const detail = (step: Step) => (step.key === 'emailVerified' ? auth.email ?? t(`welcome.step.${step.key}.text`) : t(`welcome.step.${step.key}.text`))

onMounted(async () => {
  auth.markWelcomeSeen()
  await refdata.load().catch(() => undefined)
  if (auth.moCode) await refdata.resolveOrganizations([auth.moCode]).catch(() => undefined)
})
</script>

<template>
  <PageShell :title="t('welcome.title', { name: firstName })" :lead="lead">
    <div class="welcome-col">
      <section class="card checklist" data-testid="welcome-checklist">
        <div v-for="(step, i) in steps" :key="step.key" class="step" :class="{ done: step.done }">
          <span class="num" aria-hidden="true"><i v-if="step.done" class="pi pi-check" /><template v-else>{{ i + 1 }}</template></span>
          <div class="step-main">
            <div class="step-title">{{ t(`welcome.step.${step.key}.${step.done ? 'done' : 'title'}`) }}</div>
            <div class="muted small">{{ detail(step) }}</div>
          </div>
          <span v-if="step.done" class="caption">{{ t('welcome.done') }}</span>
          <template v-else-if="step.action">
            <Button v-if="'run' in step.action" :label="step.action.label" size="small" :severity="step.action.primary ? undefined : 'secondary'" @click="step.action.run" />
            <RouterLink v-else class="link-arrow small" :to="step.action.to">{{ step.action.label }}</RouterLink>
          </template>
        </div>
        <div class="progress">
          <span class="caption">{{ onboarding ? t('welcome.progress', { done: doneCount, total: steps.length }) : t('welcome.statusUnknownShort') }}</span>
          <span class="track" aria-hidden="true"><span class="fill" :style="{ width: `${(doneCount / steps.length) * 100}%` }" /></span>
        </div>
      </section>

      <div class="grid cols-2">
        <AppCard :title="t('welcome.canTitle')" label>
          <div class="caps">
            <RouterLink v-for="c in capabilities" :key="c.key" class="cap" :to="c.to || '/'">
              <i :class="c.icon" aria-hidden="true" />
              <span><span class="cap-title">{{ t(`welcome.can.${c.key}.title`) }}</span><span class="muted cap-text">{{ t(`welcome.can.${c.key}.text`) }}</span></span>
            </RouterLink>
          </div>
        </AppCard>
        <AppCard :title="t('welcome.forecastTitle')" label>
          <p class="text">{{ t('welcome.howIntro') }}</p>
          <ul class="guide">
            <li><OriginTag kind="ml" /><span>{{ t('welcome.guideMl') }}</span></li>
            <li><OriginTag kind="formula" /><span>{{ t('welcome.guideFormula') }}</span></li>
          </ul>
          <p class="text faint">{{ t('welcome.howNote') }}</p>
        </AppCard>
      </div>
      <RouterLink class="skip" :to="auth.roleHome()" data-testid="welcome-skip">{{ t('welcome.skip') }} <span aria-hidden="true">→</span></RouterLink>
    </div>
  </PageShell>
</template>

<style scoped>
/* аккаунт (account-welcome-new): колонка 880 по центру, карточки padding 24 */
.page { max-width: 1120px; }
.card { padding: 24px; }
.welcome-col { display: flex; flex-direction: column; gap: 16px; }
.checklist { display: flex; flex-direction: column; }
.step { display: flex; align-items: center; gap: 16px; padding: 15px 0; border-bottom: 1px solid var(--border); }
.num { width: 30px; height: 30px; border-radius: 50%; background: var(--surface-sunken); color: var(--text); display: grid; place-items: center; font-size: 14px; font-weight: var(--fw-extrabold); flex: none; }
.step:not(.done) .num { background: var(--accent); color: var(--text-on-accent); }
.step:not(.done) ~ .step:not(.done) .num { background: var(--surface-sunken); color: var(--text); }
.step.done .num { background: var(--success-bg); color: var(--success-text); }
.step.done .num i { font-size: 13px; }
.step-main { flex: 1; min-width: 0; }
.step-title { font-size: var(--fs-md); font-weight: var(--fw-bold); }
.step-main .small { font-size: 13px; }
.progress { display: flex; align-items: center; gap: 16px; padding-top: 16px; }
.track { flex: 1; height: 4px; border-radius: 2px; background: var(--surface-muted); overflow: hidden; }
.fill { display: block; height: 100%; background: var(--accent); }
.caps { display: flex; flex-direction: column; gap: 4px; }
.cap { display: flex; gap: 12px; text-decoration: none; color: var(--text); padding: 10px 0; }
.cap i { margin-top: 3px; color: var(--text-muted); font-size: 15px; }
.cap span { display: flex; flex-direction: column; }
.cap-title { font-weight: var(--fw-bold); font-size: var(--fs-base); }
.cap-text { font-size: 13px; }
.cap:hover .cap-title { color: var(--accent-strong); }
.text { margin: 0 0 10px; font-size: 14px; line-height: 1.5; }
.text.faint { font-size: 13px; }
.guide { list-style: none; margin: 0 0 12px; padding: 0; display: flex; flex-direction: column; gap: 10px; }
.guide li { display: flex; align-items: flex-start; gap: 10px; font-size: 14px; line-height: 1.5; }
.guide li :deep(.origin) { flex: none; margin-top: 1px; }
.skip { align-self: center; margin-top: 8px; font-size: 14px; font-weight: var(--fw-bold); color: var(--link); text-decoration: none; }
.skip:hover { color: var(--accent-strong); }
</style>
