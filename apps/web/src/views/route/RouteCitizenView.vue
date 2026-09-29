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
import RouteTimeline from '@/components/route/RouteTimeline.vue'
import AppCard from '@/components/ui/AppCard.vue'
import CollapsibleSection from '@/components/ui/CollapsibleSection.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import HeroNumber from '@/components/ui/HeroNumber.vue'
import PageShell from '@/components/ui/PageShell.vue'
import Skeleton from '@/components/ui/Skeleton.vue'
import StatusTag from '@/components/ui/StatusTag.vue'
import { useRouteData } from '@/composables/useRouteData'
import { days, pct, shortOrgName } from '@/lib/format'
import { dateShort, stageTone, type Tone } from '@/lib/route'

/** «Мой путь» (route-new): чип стадии справа от заголовка; во всю ширину карточка «Этапы маршрута» горизонтальным
 * степпером (узлы 40); ниже две колонки — слева «Сколько ждать» (крупный срок 34) и «Что дальше», справа
 * карточка-сигнал (ответ врача / валидация листа ожидания) и «Где быстрее» плитками с зелёными сроками;
 * внизу решения и прошлые направления. Риск отказа не показывается. */
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

/** Ответ на решение redirect, ждущее согласия (задача 2): пока не ответит — «Понятно» не показывается, банер держится. */
async function respondConsent(decisionId: string, accepted: boolean) {
  const ok = await r.consent(decisionId, accepted)
  if (!ok) return
  toast.add({ severity: 'success', summary: t(accepted ? 'route.consentAccepted' : 'route.consentDeclined'), life: 4000 })
}

onMounted(r.load)
</script>

<template>
  <PageShell :title="t('route.myTitle')">
    <template v-if="r.data.value" #subtitle>
      <span :title="r.data.value.organization.moName">{{ shortOrgName(r.data.value.organization.moName) }}</span> · {{ r.data.value.organization.profileName }} ·
      {{ t('route.since', { date: dateShort(r.data.value.dates.registeredAt), days: r.data.value.daysWaiting }) }} · {{ t('shell.asOf', { date: dateShort(r.data.value.asOf) }) }}
    </template>
    <template v-if="r.data.value" #actions>
      <StatusTag :value="t('route.stage.' + r.data.value.stage)" :tone="tone(stageTone(r.data.value.stage))" data-testid="route-stage" />
    </template>
    <ErrorBox :error="r.error.value" />
    <EmptyState v-if="r.notFound.value" :title="t('route.notFound')" icon="pi pi-map">
      <RouterLink class="link-arrow" to="/wait">{{ t('nav.wait') }}</RouterLink>
    </EmptyState>
    <div v-else-if="r.busy.value && !r.data.value" class="cols">
      <AppCard><Skeleton :lines="5" /></AppCard>
      <AppCard><Skeleton :lines="4" /></AppCard>
    </div>

    <template v-if="r.data.value">
      <AppCard :title="t('route.stagesTitle')" label class="stages-card">
        <template #header><span class="caption">{{ t('route.stagesCount', { total: r.data.value.timeline.length, done: doneCount }) }}</span></template>
        <RouteTimeline :stages="r.data.value.timeline" variant="citizen" norms />
      </AppCard>

      <div class="cols">
        <div class="col">
          <AppCard :title="t('route.forecast')" label :origin="r.data.value.forecast.fromModel ? 'ml' : 'formula'">
            <HeroNumber :value="`≈ ${days(r.data.value.forecast.p50Days)}`" :unit="t('common.days')" :label="t('hero.half')" :sub="heroSub" />
            <p v-if="r.target.value" class="caption benchmark">{{ t('route.benchmark', { days: days(r.target.value.value), source: r.target.value.source }) }} <OriginTag kind="formula" /></p>
          </AppCard>

          <AppCard :title="t('route.whatNext')" label class="grow" data-testid="what-now">
            <div class="rows">
              <div class="row">
                <span class="row-main"><span class="row-title">{{ r.data.value.dates.plannedAt ? t('route.dates.planned') : t('route.dates.expected') }}</span><span class="row-sub">{{ shortOrgName(r.data.value.organization.moName) }} · {{ r.data.value.organization.moCode }}</span></span>
                <span class="row-value strong tabular">{{ dateShort(r.data.value.dates.plannedAt ?? r.data.value.dates.expectedAt) }}</span>
              </div>
              <div v-if="r.expired.value" class="row">
                <span class="row-main"><span class="row-title">{{ t('route.updateTests', { n: r.expired.value }) }}</span><span class="row-sub">{{ expiredTitles }}</span></span>
                <span class="row-value"><StatusTag :value="t('route.status.expired')" tone="danger" /></span>
              </div>
              <div v-if="validItems.length" class="row">
                <span class="row-main"><span class="row-title">{{ t('route.validTests', { n: validItems.length }) }}</span><span class="row-sub">{{ validItems[0]!.title }} · {{ t('route.validUntil', { date: dateShort(validItems[0]!.validUntil) }) }}</span></span>
                <span class="row-value"><StatusTag :value="t('route.status.valid')" tone="ok" /></span>
              </div>
              <div v-if="nextStage" class="row">
                <span class="row-main"><span class="row-title">{{ nextStage.title }}</span><span v-if="nextStage.norm" class="row-sub">{{ t('route.normLabel') }}: {{ nextStage.norm }}</span></span>
              </div>
              <div v-else-if="currentStage" class="row"><span class="row-main row-title">{{ currentStage.title }}</span></div>
              <div v-if="r.pendingRequest.value" class="row">
                <span class="row-main row-title" :title="r.pendingRequest.value.toMoName ?? ''">{{ t('route.signal.request_redirect', { name: shortOrgName(r.pendingRequest.value.toMoName) }) }}</span>
                <span class="row-value"><StatusTag :value="t('route.awaitingDoctor')" tone="accent" /></span>
              </div>
            </div>
          </AppCard>
        </div>

        <div class="col">
          <!-- ответ врача: карточка-сигнал на accent-soft -->
          <section v-if="doctorAnswer" class="card signal-card" data-testid="doctor-answer">
            <div class="signal-head"><i class="pi pi-shield" aria-hidden="true" /><span class="signal-title">{{ doctorAnswer.kind === 'redirect' ? t('route.doctorSuggested') : t('route.keep') }}</span></div>
            <span v-if="doctorAnswer.kind === 'redirect'" class="signal-body" :title="doctorAnswer.toMoName">
              {{ shortOrgName(doctorAnswer.toMoName) }}<template v-if="answerAlternative"> · ≈ {{ days(answerAlternative.p50Days) }} {{ t('common.days') }} — {{ t('hero.half') }}</template>
            </span>
            <span v-if="doctorAnswer.reason" class="muted">{{ t('route.doctorReason', { reason: doctorAnswer.reason }) }}</span>
            <StatusTag v-if="doctorAnswer.patientConsent === 'accepted'" :value="t('route.consentAccepted')" tone="ok" />
            <StatusTag v-else-if="doctorAnswer.patientConsent === 'declined'" :value="t('route.consentDeclined')" tone="neutral" />
            <div class="signal-actions">
              <template v-if="doctorAnswer.patientConsent === 'pending'">
                <Button :label="t('route.consentAccept')" :loading="r.acting.value === doctorAnswer.decisionId" :disabled="r.acting.value !== null" data-testid="consent-accept" @click="respondConsent(doctorAnswer.decisionId, true)" />
                <Button :label="t('route.consentDecline')" severity="secondary" :loading="r.acting.value === doctorAnswer.decisionId" :disabled="r.acting.value !== null" data-testid="consent-decline" @click="respondConsent(doctorAnswer.decisionId, false)" />
              </template>
              <Button v-else :label="t('route.gotIt')" @click="dismissAnswer(doctorAnswer.decisionId)" />
              <RouterLink class="link-arrow" to="/wait">{{ t('route.compareWait') }}</RouterLink>
            </div>
          </section>
          <!-- валидация листа ожидания -->
          <AppCard v-else-if="r.data.value.validationDue" :title="t('route.validationTitle')" class="validation" data-testid="validation-card">
            <p class="muted small validation-body">{{ t('route.validationBody') }}</p>
            <div class="options">
              <button type="button" class="option" :disabled="r.acting.value !== null" data-testid="still-waiting" @click="signal('still_waiting')">{{ t('route.validationStill') }}</button>
              <button type="button" class="option" :disabled="r.acting.value !== null" @click="signal('treated_elsewhere')">{{ t('route.validationTreated') }}</button>
              <button type="button" class="option" :disabled="r.acting.value !== null" @click="signal('withdraw')">{{ t('route.validationWithdraw') }}</button>
            </div>
          </AppCard>

          <AppCard :title="t('route.whereFaster')" label :origin="r.data.value.alternativesModel ? 'ml' : undefined" class="grow">
            <p class="muted small faster-lead">{{ t('route.sameRegionProfile') }}. {{ t('route.doctorOnly') }}.</p>
            <RouteAlternatives :items="r.data.value.alternatives" audience="citizen" :acting="r.acting.value" :pending-code="r.pendingRequest.value?.toMoCode" :action-label="t('route.requestConsider')" :baseline-days="r.data.value.forecast.p50Days" @act="signal('request_redirect', $event)" />
            <div v-if="r.data.value.alternatives.length" class="comment-block">
              <div class="field">
                <label>{{ t('route.requestComment') }}</label>
                <Textarea v-model="requestComment" rows="2" auto-resize data-testid="request-comment" />
              </div>
              <p class="caption comment-note">{{ t('route.doctorOnly') }}</p>
            </div>
          </AppCard>
        </div>
      </div>

      <CollapsibleSection :title="t('route.checklist')" :summary="t('route.checklistSummary', { expired: r.expired.value, valid: r.valid.value })" :tone="r.expired.value ? 'danger' : undefined" origin="formula">
        <RouteChecklist :items="r.data.value.checklist" :standard="r.data.value.standard" />
      </CollapsibleSection>
      <div class="grid cols-2">
        <AppCard :title="t('route.signalsTitle')" label><RouteFeed :entries="r.entries.value" audience="citizen" /></AppCard>
        <AppCard :title="t('route.pastReferrals')" label><RouteHistory :items="r.data.value.history" /></AppCard>
      </div>
      <p class="caption footnote">{{ r.data.value.basis }} · {{ t('route.synthetic', { asOf: dateShort(r.data.value.asOf) }) }} · {{ t('route.stagesSource') }}</p>
    </template>
  </PageShell>
</template>

<style scoped>
/* карточки гражданина: padding 22/24 (route-new) */
.card { padding: 22px 24px; }
.stages-card { padding: 26px 28px; }
.cols { display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); gap: var(--gap-citizen); align-items: stretch; }
.col { display: flex; flex-direction: column; gap: var(--gap-citizen); min-width: 0; }
.grow { flex: 1; }
.benchmark { border-top: 1px solid var(--surface-muted); margin: 14px 0 0; padding-top: 12px; }
.row-main { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
.row-title { font-weight: var(--fw-bold); }
.strong { font-weight: var(--fw-extrabold); font-size: var(--fs-md); }
.signal-card { background: var(--accent-soft); border-color: var(--accent-soft); display: flex; flex-direction: column; gap: 10px; color: var(--text); }
.signal-head { display: flex; align-items: center; gap: 12px; }
.signal-head i { font-size: 1.2rem; color: var(--accent-strong); }
.signal-title { font-size: 15px; font-weight: var(--fw-extrabold); letter-spacing: -0.01em; }
.signal-body { font-size: var(--fs-base); }
.signal-actions { display: flex; align-items: center; gap: 16px; margin-top: 6px; flex-wrap: wrap; }
.validation :deep(h2) { font-size: 15px; font-weight: var(--fw-extrabold); }
.validation-body { margin: 0 0 14px; line-height: 1.5; }
.options { display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); gap: 8px; }
.option { border: 0; border-radius: var(--radius-lg); background: var(--surface-hover); color: var(--text); font: inherit; font-size: var(--fs-base-sm); font-weight: var(--fw-bold); text-align: center; padding: 12px; cursor: pointer; }
.option:hover:not(:disabled) { background: var(--accent-subtle); color: var(--accent-strong); }
.option:disabled { opacity: 0.6; cursor: default; }
.faster-lead { margin: -4px 0 10px; line-height: 1.45; }
.comment-block { margin-top: auto; padding-top: 14px; }
.comment-note { margin: 8px 0 0; color: var(--text-faint); }
.footnote { color: var(--text-faint); }
.grid.cols-2 .card { display: flex; flex-direction: column; }
@media (max-width: 900px) { .cols { grid-template-columns: 1fr; } }
</style>
