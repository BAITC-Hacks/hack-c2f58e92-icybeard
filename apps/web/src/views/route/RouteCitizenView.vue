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
import CollapsibleSection from '@/components/ui/CollapsibleSection.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import HeroNumber from '@/components/ui/HeroNumber.vue'
import PageShell from '@/components/ui/PageShell.vue'
import Skeleton from '@/components/ui/Skeleton.vue'
import StageStepper from '@/components/ui/StageStepper.vue'
import StatusTag from '@/components/ui/StatusTag.vue'
import { useRouteData } from '@/composables/useRouteData'
import { days, pct, shortOrgName } from '@/lib/format'
import { dateShort, stageTone, type Tone } from '@/lib/route'

/** «Мой путь» (W-Route): заголовок с чипом стадии и подписью «организация · профиль · с даты · ждёт N дн.»;
 * слева карточка «Этапы маршрута» вертикальной лентой, справа карточка-сигнал (ответ врача / валидация листа ожидания)
 * и «Что дальше» строками; ниже прогноз, «где быстрее», решения и прошлые направления. Риск отказа не показывается. */
const { t } = useI18n()
const toast = useToast()
const r = useRouteData(() => undefined)
const requestComment = ref('')
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
const answerAlternative = computed(() => r.data.value?.alternatives.find((a) => a.mo.moCode === doctorAnswer.value?.toMoCode) ?? null)
const currentStage = computed(() => r.data.value?.timeline.find((s) => s.status === 'current') ?? null)
const nextStage = computed(() => r.data.value?.timeline.find((s) => s.status === 'upcoming') ?? null)
const doneCount = computed(() => r.data.value?.timeline.filter((s) => s.status === 'done').length ?? 0)
const expiredTitles = computed(() => r.data.value?.checklist.filter((c) => c.status === 'expired').map((c) => c.title).join(' · ') ?? '')
const validItems = computed(() => r.data.value?.checklist.filter((c) => c.status !== 'expired') ?? [])
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
  <PageShell :title="t('route.myTitle')">
    <template v-if="r.data.value" #title-extra>
      <StatusTag :value="t('route.stage.' + r.data.value.stage)" :tone="tone(stageTone(r.data.value.stage))" data-testid="route-stage" />
    </template>
    <template v-if="r.data.value" #subtitle>
      <span :title="r.data.value.organization.moName">{{ shortOrgName(r.data.value.organization.moName) }}</span> · {{ r.data.value.organization.profileName }} ·
      {{ t('route.since', { date: dateShort(r.data.value.dates.registeredAt), days: r.data.value.daysWaiting }) }} · {{ t('shell.asOf', { date: dateShort(r.data.value.asOf) }) }}
    </template>
    <ErrorBox :error="r.error.value" />
    <EmptyState v-if="r.notFound.value" :title="t('route.notFound')" icon="pi pi-map">
      <RouterLink class="link-arrow" to="/wait">{{ t('nav.wait') }}</RouterLink>
    </EmptyState>
    <div v-else-if="r.busy.value && !r.data.value" class="top-grid">
      <AppCard><Skeleton :lines="5" /></AppCard>
      <AppCard><Skeleton :lines="4" /></AppCard>
    </div>

    <template v-if="r.data.value">
      <div class="top-grid">
        <AppCard :title="t('route.stagesTitle')">
          <template #header><span class="caption">{{ t('route.stagesCount', { total: r.data.value.timeline.length, done: doneCount }) }}</span></template>
          <StageStepper :stages="r.data.value.timeline" vertical norms />
        </AppCard>

        <div class="col">
          <!-- ответ врача: карточка-сигнал на coral-wash -->
          <section v-if="doctorAnswer" class="card signal-card" data-testid="doctor-answer">
            <div class="signal-head"><i class="pi pi-shield" aria-hidden="true" /><span class="signal-title">{{ doctorAnswer.kind === 'redirect' ? t('route.doctorSuggested') : t('route.keep') }}</span></div>
            <span v-if="doctorAnswer.kind === 'redirect'" class="signal-body" :title="doctorAnswer.toMoName">
              {{ shortOrgName(doctorAnswer.toMoName) }}<template v-if="answerAlternative"> · ≈ {{ days(answerAlternative.p50Days) }} {{ t('common.days') }} — {{ t('hero.half') }}</template>
            </span>
            <span v-if="doctorAnswer.reason" class="muted">{{ t('route.doctorReason', { reason: doctorAnswer.reason }) }}</span>
            <div class="signal-actions">
              <Button :label="t('route.gotIt')" @click="dismissAnswer(doctorAnswer.decisionId)" />
              <RouterLink class="link-arrow" to="/wait">{{ t('route.compareWait') }}</RouterLink>
            </div>
          </section>
          <!-- валидация листа ожидания -->
          <AppCard v-else-if="r.data.value.validationDue" :title="t('route.validationTitle')" data-testid="validation-card">
            <p class="muted small" style="margin: 0 0 12px">{{ t('route.validationBody') }}</p>
            <div class="options">
              <button type="button" class="option" :disabled="r.acting.value !== null" data-testid="still-waiting" @click="signal('still_waiting')"><i class="pi pi-check-circle" aria-hidden="true" /><span>{{ t('route.validationStill') }}</span></button>
              <button type="button" class="option" :disabled="r.acting.value !== null" @click="signal('treated_elsewhere')"><i class="pi pi-building" aria-hidden="true" /><span>{{ t('route.validationTreated') }}</span></button>
              <button type="button" class="option" :disabled="r.acting.value !== null" @click="signal('withdraw')"><i class="pi pi-times-circle" aria-hidden="true" /><span>{{ t('route.validationWithdraw') }}</span></button>
            </div>
          </AppCard>

          <AppCard :title="t('route.whatNext')" data-testid="what-now">
            <div class="rows">
              <div class="row">
                <span class="row-main"><span>{{ r.data.value.dates.plannedAt ? t('route.dates.planned') : t('route.dates.expected') }}</span><span class="row-sub">{{ shortOrgName(r.data.value.organization.moName) }} · {{ r.data.value.organization.moCode }}</span></span>
                <span class="row-value strong">{{ dateShort(r.data.value.dates.plannedAt ?? r.data.value.dates.expectedAt) }}</span>
              </div>
              <div v-if="r.expired.value" class="row">
                <span class="row-main"><span>{{ t('route.updateTests', { n: r.expired.value }) }}</span><span class="row-sub">{{ expiredTitles }}</span></span>
                <span class="row-value"><StatusTag :value="t('route.status.expired')" tone="danger" /></span>
              </div>
              <div v-if="validItems.length" class="row">
                <span class="row-main"><span>{{ t('route.validTests', { n: validItems.length }) }}</span><span class="row-sub">{{ validItems[0]!.title }} · {{ t('route.validUntil', { date: dateShort(validItems[0]!.validUntil) }) }}</span></span>
                <span class="row-value"><StatusTag :value="t('route.status.valid')" tone="ok" /></span>
              </div>
              <div v-if="nextStage" class="row">
                <span class="row-main"><span>{{ nextStage.title }}</span><span v-if="nextStage.norm" class="row-sub">{{ t('route.normLabel') }}: {{ nextStage.norm }}</span></span>
              </div>
              <div v-else-if="currentStage" class="row"><span class="row-main">{{ currentStage.title }}</span></div>
              <div v-if="r.pendingRequest.value" class="row">
                <span class="row-main" :title="r.pendingRequest.value.toMoName ?? ''">{{ t('route.signal.request_redirect', { name: shortOrgName(r.pendingRequest.value.toMoName) }) }}</span>
                <span class="row-value"><StatusTag :value="t('route.awaitingDoctor')" tone="accent" /></span>
              </div>
            </div>
          </AppCard>
        </div>
      </div>

      <div class="grid cols-2">
        <AppCard>
          <HeroNumber :value="`≈ ${days(r.data.value.forecast.p50Days)}`" :unit="t('common.days')" :caption="t('route.forecast')" :label="t('hero.half')" :sub="heroSub" :origin="r.data.value.forecast.fromModel ? 'ml' : 'formula'" compact />
          <p v-if="r.target.value" class="caption benchmark">{{ t('route.benchmark', { days: days(r.target.value.value), source: r.target.value.source }) }} <OriginTag kind="formula" /></p>
        </AppCard>
        <AppCard :title="t('route.whereFaster')" :origin="r.data.value.alternativesModel ? 'ml' : undefined">
          <RouteAlternatives :items="r.data.value.alternatives" audience="citizen" :acting="r.acting.value" :pending-code="r.pendingRequest.value?.toMoCode" :action-label="t('route.requestConsider')" @act="signal('request_redirect', $event)" />
          <div v-if="r.data.value.alternatives.length" class="field" style="margin-top: 12px">
            <label>{{ t('route.requestComment') }}</label>
            <Textarea v-model="requestComment" rows="2" auto-resize data-testid="request-comment" />
          </div>
          <p class="caption" style="margin: 8px 0 0">{{ t('route.doctorOnly') }}</p>
        </AppCard>
      </div>

      <CollapsibleSection :title="t('route.checklist')" :summary="t('route.checklistSummary', { expired: r.expired.value, valid: r.valid.value })" :tone="r.expired.value ? 'danger' : undefined" origin="formula">
        <RouteChecklist :items="r.data.value.checklist" :standard="r.data.value.standard" />
      </CollapsibleSection>
      <div class="grid cols-2">
        <AppCard :title="t('route.signalsTitle')"><RouteFeed :entries="r.entries.value" audience="citizen" /></AppCard>
        <AppCard :title="t('route.pastReferrals')"><RouteHistory :items="r.data.value.history" /></AppCard>
      </div>
      <p class="caption">{{ r.data.value.basis }} · {{ t('route.synthetic', { asOf: dateShort(r.data.value.asOf) }) }} · {{ t('route.stagesSource') }}</p>
    </template>
  </PageShell>
</template>

<style scoped>
.top-grid { display: grid; grid-template-columns: minmax(0, 1.1fr) minmax(0, 1fr); gap: var(--dm-space-4); align-items: start; }
.col { display: flex; flex-direction: column; gap: var(--dm-space-4); min-width: 0; }
.signal-card { background: var(--dm-accent-soft); display: flex; flex-direction: column; gap: 10px; color: var(--dm-ink); }
.signal-head { display: flex; align-items: center; gap: 12px; }
.signal-head i { font-size: 1.3rem; }
.signal-title { font-size: var(--dm-text-lg); font-weight: 500; letter-spacing: -0.01em; }
.signal-body { font-size: var(--dm-text-base); }
.signal-actions { display: flex; align-items: center; gap: 16px; margin-top: 6px; flex-wrap: wrap; }
.row-main { display: flex; flex-direction: column; gap: 2px; }
.strong { font-weight: 500; font-size: var(--dm-text-base); }
.options { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 8px; }
.option { display: flex; flex-direction: column; align-items: flex-start; gap: 8px; padding: 14px 16px; border: 0; border-radius: var(--dm-radius-md); background: var(--dm-surface-2); color: var(--dm-ink); font: inherit; font-size: var(--dm-text-md); text-align: left; cursor: pointer; }
.option:hover:not(:disabled) { box-shadow: inset 0 0 0 2px var(--dm-ink); }
.option:disabled { opacity: 0.6; cursor: default; }
.option i { color: var(--dm-accent); }
.benchmark { margin: 12px 0 0; }
@media (max-width: 900px) { .top-grid { grid-template-columns: 1fr; } }
</style>
