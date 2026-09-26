<script setup lang="ts">
import Button from 'primevue/button'
import Textarea from 'primevue/textarea'
import { useToast } from 'primevue/usetoast'
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import type { SignalKind } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import OriginTag from '@/components/OriginTag.vue'
import RouteAlternatives from '@/components/route/RouteAlternatives.vue'
import RouteChecklist from '@/components/route/RouteChecklist.vue'
import RouteFeed from '@/components/route/RouteFeed.vue'
import RouteHistory from '@/components/route/RouteHistory.vue'
import AppCard from '@/components/ui/AppCard.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import HeroNumber from '@/components/ui/HeroNumber.vue'
import PageShell from '@/components/ui/PageShell.vue'
import Skeleton from '@/components/ui/Skeleton.vue'
import StageStepper from '@/components/ui/StageStepper.vue'
import StatusTag from '@/components/ui/StatusTag.vue'
import { useRouteData } from '@/composables/useRouteData'
import { days, pct, shortOrgName } from '@/lib/format'
import { dateShort, stageTone, type Tone } from '@/lib/route'

/** «Мой путь» гражданина (/route/me): степпер через всю ширину, слева «что сейчас» и анализы, справа прогноз,
 * организация и «где быстрее», ниже лента решений и прошлые направления. Риск отказа гражданину не показывается. */
const { t } = useI18n()
const toast = useToast()
const r = useRouteData(() => undefined)
const requestComment = ref('')
const fullName = ref(false)
const SEEN_KEY = 'darumen.route.seenDecision'
const seenDecision = ref(readSeen())

function readSeen(): string | null {
  try {
    return sessionStorage.getItem(SEEN_KEY)
  } catch {
    return null
  }
}

/** «Понятно» прячет ответ врача до следующего ответа (ключ решения — в sessionStorage). */
function dismissAnswer(id: string) {
  seenDecision.value = id
  try {
    sessionStorage.setItem(SEEN_KEY, id)
  } catch {
    // приватный режим: ответ спрячется до перезагрузки
  }
}

const STATUS_TONES = { success: 'ok', warn: 'warn', danger: 'danger', info: 'accent', secondary: 'neutral' } as const satisfies Record<Tone, string>
const tone = (severity: Tone) => STATUS_TONES[severity]

/** Ответ врача показывается, если он новее последнего сигнала гражданина и его ещё не закрыли «Понятно». */
const doctorAnswer = computed(() => {
  const d = r.latestDecision.value
  if (!d || seenDecision.value === d.decisionId) return null
  const lastSignal = r.data.value?.signals[0]
  return !lastSignal || lastSignal.recordedAt < d.recordedAt ? d : null
})
const currentStage = computed(() => r.data.value?.timeline.find((s) => s.status === 'current') ?? null)
const nextStage = computed(() => r.data.value?.timeline.find((s) => s.status === 'upcoming') ?? null)
const heroSub = computed(() => {
  const f = r.data.value?.forecast
  if (!f) return ''
  const parts = [t('hero.nineOfTen', { days: days(f.p90Days) })]
  if (f.pWithin30Days !== null) parts.push(t('hero.within30', { pct: pct(f.pWithin30Days) }))
  return parts.join(' · ')
})

async function signal(kind: SignalKind, toMoCode?: string) {
  const ok = await r.signal(kind, toMoCode, requestComment.value)
  if (!ok) return
  toast.add({ severity: 'success', summary: t(toMoCode ? 'route.requestSent' : 'route.signalSent'), life: 4000 })
  requestComment.value = ''
}

onMounted(r.load)
</script>

<template>
  <PageShell :title="t('route.myTitle')" :as-of="r.data.value?.asOf" :synthetic="r.data.value ? t('route.syntheticShort') : undefined">
    <template v-if="r.data.value" #subtitle>
      <StatusTag :value="t('route.stage.' + r.data.value.stage)" :tone="tone(stageTone(r.data.value.stage))" data-testid="route-stage" />
      {{ t('route.since', { date: dateShort(r.data.value.dates.registeredAt), days: r.data.value.daysWaiting }) }}
    </template>
    <ErrorBox :error="r.error.value" />
    <EmptyState v-if="r.notFound.value" :title="t('route.notFound')" icon="pi pi-map">
      <RouterLink to="/wait">{{ t('nav.wait') }}</RouterLink>
    </EmptyState>
    <template v-else-if="r.busy.value && !r.data.value">
      <AppCard><Skeleton :lines="2" /></AppCard>
      <div class="grid cols-2" style="margin-top: 16px"><AppCard><Skeleton :lines="4" /></AppCard><AppCard><Skeleton kind="kpi" /></AppCard></div>
    </template>

    <template v-if="r.data.value">
      <AppCard dense><StageStepper :stages="r.data.value.timeline" norms /></AppCard>

      <div class="grid cols-2" style="margin-top: 16px">
        <div class="col">
          <AppCard :title="t('route.whatNow')" data-testid="what-now">
            <!-- ответ врача -->
            <div v-if="doctorAnswer" class="answer" data-testid="doctor-answer">
              <div class="answer-title"><i class="pi pi-user" aria-hidden="true" /> {{ t('route.doctorAnswered') }}</div>
              <p :title="doctorAnswer.toMoName">{{ doctorAnswer.kind === 'redirect' ? t('route.redirect', { name: shortOrgName(doctorAnswer.toMoName) }) : t('route.keep') }}</p>
              <p v-if="doctorAnswer.reason" class="muted">«{{ doctorAnswer.reason }}»</p>
              <Button :label="t('route.gotIt')" size="small" severity="secondary" @click="dismissAnswer(doctorAnswer.decisionId)" />
            </div>
            <!-- валидация листа ожидания -->
            <div v-else-if="r.data.value.validationDue" data-testid="validation-card">
              <p class="question">{{ t('route.validationTitle') }}</p>
              <p class="muted small">{{ t('route.validationBody') }}</p>
              <div class="options">
                <button type="button" class="option" :disabled="r.acting.value !== null" data-testid="still-waiting" @click="signal('still_waiting')">
                  <i class="pi pi-check-circle" aria-hidden="true" /><span>{{ t('route.validationStill') }}</span>
                </button>
                <button type="button" class="option" :disabled="r.acting.value !== null" @click="signal('treated_elsewhere')">
                  <i class="pi pi-building" aria-hidden="true" /><span>{{ t('route.validationTreated') }}</span>
                </button>
                <button type="button" class="option" :disabled="r.acting.value !== null" @click="signal('withdraw')">
                  <i class="pi pi-times-circle" aria-hidden="true" /><span>{{ t('route.validationWithdraw') }}</span>
                </button>
              </div>
            </div>
            <!-- следующий этап -->
            <div v-else>
              <p v-if="r.data.value.dates.plannedAt" class="question">{{ t('route.dateAssignedOn', { date: dateShort(r.data.value.dates.plannedAt) }) }}</p>
              <template v-else-if="nextStage">
                <p class="question">{{ t('route.nextStage', { title: nextStage.title }) }}</p>
                <p v-if="nextStage.norm" class="muted small">{{ t('route.normLabel') }}: {{ nextStage.norm }}</p>
              </template>
              <p v-else-if="currentStage" class="question">{{ currentStage.title }}</p>
              <p class="muted small">{{ t('route.expectedBy', { date: dateShort(r.data.value.dates.expectedAt) }) }}</p>
            </div>
            <p v-if="r.pendingRequest.value" class="pending">
              <StatusTag :value="t('route.awaitingDoctor')" tone="accent" />
              <span class="muted small" :title="r.pendingRequest.value.toMoName ?? ''">{{ t('route.signal.request_redirect', { name: shortOrgName(r.pendingRequest.value.toMoName) }) }}</span>
            </p>
          </AppCard>

          <AppCard :title="t('route.checklist')" origin="formula" style="margin-top: 16px">
            <template #header><span class="muted small">{{ t('route.checklistSummary', { expired: r.expired.value, valid: r.valid.value }) }}</span></template>
            <RouteChecklist :items="r.data.value.checklist" :standard="r.data.value.standard" />
          </AppCard>
        </div>

        <div class="col">
          <AppCard :title="t('route.forecast')">
            <HeroNumber
              :value="`≈ ${days(r.data.value.forecast.p50Days)}`"
              :unit="t('common.days')"
              :label="t('hero.half')"
              :sub="heroSub"
              :origin="r.data.value.forecast.fromModel ? 'ml' : 'formula'"
              compact
            />
            <p v-if="r.target.value" class="muted small benchmark">{{ t('route.benchmark', { days: days(r.target.value.value), source: r.target.value.source }) }} <OriginTag kind="formula" /></p>
          </AppCard>

          <AppCard :title="t('route.organization')" style="margin-top: 16px">
            <div class="org-name" :title="r.data.value.organization.moName">{{ shortOrgName(r.data.value.organization.moName) }}</div>
            <div class="muted">{{ r.data.value.organization.profileName }} · <span class="mono">{{ r.data.value.organization.moCode }}</span></div>
            <button type="button" class="linkish" @click="fullName = !fullName">{{ fullName ? t('shell.less') : t('route.showFullName') }}</button>
            <p v-if="fullName" class="muted small">{{ r.data.value.organization.moName }}</p>
          </AppCard>

          <AppCard :title="t('route.whereFaster')" :origin="r.data.value.alternativesModel ? 'ml' : undefined" style="margin-top: 16px">
            <RouteAlternatives
              :items="r.data.value.alternatives"
              audience="citizen"
              :acting="r.acting.value"
              :pending-code="r.pendingRequest.value?.toMoCode"
              :action-label="t('route.requestConsider')"
              @act="signal('request_redirect', $event)"
            />
            <div v-if="r.data.value.alternatives.length" class="field" style="margin-top: 12px">
              <label>{{ t('route.requestComment') }}</label>
              <Textarea v-model="requestComment" rows="2" auto-resize data-testid="request-comment" />
            </div>
            <p class="muted small" style="margin-top: 8px">{{ t('route.doctorOnly') }}</p>
          </AppCard>
        </div>
      </div>

      <div class="grid cols-2" style="margin-top: 16px">
        <AppCard :title="t('route.signalsTitle')"><RouteFeed :entries="r.entries.value" audience="citizen" /></AppCard>
        <AppCard :title="t('route.pastReferrals')"><RouteHistory :items="r.data.value.history" /></AppCard>
      </div>
      <p class="muted small" style="margin-top: 16px">{{ r.data.value.basis }} · {{ t('route.synthetic', { asOf: dateShort(r.data.value.asOf) }) }} · {{ t('route.stagesSource') }}</p>
    </template>
  </PageShell>
</template>

<style scoped>
.question { font-size: 1.1rem; font-weight: 600; margin: 0 0 4px; }
.options { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 8px; margin-top: 12px; }
.option { display: flex; flex-direction: column; align-items: flex-start; gap: 8px; padding: 12px; border: 1px solid var(--dm-hairline); border-radius: var(--dm-radius-md); background: var(--dm-surface); color: var(--dm-ink); font: inherit; text-align: left; cursor: pointer; }
.option:hover:not(:disabled) { border-color: var(--dm-accent); background: var(--dm-accent-soft); }
.option:disabled { opacity: 0.6; cursor: default; }
.option i { color: var(--dm-accent); }
.answer { border-left: 3px solid var(--dm-accent); padding-left: 12px; }
.answer-title { font-weight: 600; margin-bottom: 4px; }
.answer p { margin: 0 0 8px; }
.pending { display: flex; align-items: center; gap: 8px; margin: 12px 0 0; flex-wrap: wrap; }
.org-name { font-size: 1.1rem; font-weight: 600; }
.linkish { background: none; border: 0; padding: 0; color: var(--dm-accent); font: inherit; font-size: 0.85rem; cursor: pointer; margin-top: 6px; }
.benchmark { margin: 12px 0 0; }
</style>
