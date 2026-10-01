<script setup lang="ts">
import Button from 'primevue/button'
import Textarea from 'primevue/textarea'
import { useToast } from 'primevue/usetoast'
import { computed, nextTick, onMounted, ref } from 'vue'
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
import { dateShort } from '@/lib/route'

/** «Мой путь» (route-new): чип стадии справа от заголовка; во всю ширину карточка «Этапы маршрута» горизонтальным
 * степпером (узлы 40); ниже две колонки — слева «Сколько ждать» (крупный срок 34) и «Что дальше», справа
 * карточка-сигнал (ответ врача / валидация листа ожидания) и «Где быстрее» плитками с зелёными сроками;
 * внизу решения и прошлые направления. Риск отказа не показывается. */
const { t } = useI18n()
const toast = useToast()
const r = useRouteData(() => undefined)
const requestComment = ref('')
const commentOpen = ref(false)
/** «Посмотреть» у строки про анализы: раскрыть свёрнутый раздел «Анализы» и прокрутить к нему. */
const testsOpen = ref(false)
const testsKey = ref(0)
async function openTests() {
  testsOpen.value = true
  testsKey.value++
  await nextTick()
  document.getElementById('route-tests')?.scrollIntoView({ behavior: 'smooth', block: 'start' })
}
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
  const parts = [t('route.citizen.forecastNine', { days: days(f.p90Days) })]
  if (f.pWithin30Days !== null) parts.push(t('route.citizen.forecastWithin30', { pct: pct(f.pWithin30Days) }))
  return parts.join('\n')
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
    <ErrorBox :error="r.error.value" />
    <EmptyState v-if="r.notFound.value" :title="t('route.notFound')" icon="pi pi-map">
      <RouterLink class="link-arrow" to="/wait">{{ t('nav.wait') }}</RouterLink>
    </EmptyState>
    <div v-else-if="r.busy.value && !r.data.value" class="cols">
      <AppCard><Skeleton :lines="5" /></AppCard>
      <AppCard><Skeleton :lines="4" /></AppCard>
    </div>

    <template v-if="r.data.value">
      <!-- одна карточка: больница и сроки сверху, под чертой — этапы маршрута (текущий этап виден на степпере) -->
      <section class="card route-card">
      <div class="who" data-testid="route-who">
          <div class="who-main">
            <span class="who-label">{{ t('route.citizen.yourHospital') }}</span>
            <span class="who-name" :title="r.data.value.organization.moName">{{ shortOrgName(r.data.value.organization.moName) }}</span>
            <span class="who-profile">{{ r.data.value.organization.profileName }}</span>
          </div>
          <dl class="who-facts">
            <div class="fact"><dt>{{ t('route.citizen.factSince') }}</dt><dd class="tabular">{{ dateShort(r.data.value.dates.registeredAt) }}</dd></div>
            <div class="fact"><dt>{{ t('route.citizen.factWaiting') }}</dt><dd class="tabular">{{ t('route.citizen.factDays', { days: r.data.value.daysWaiting }) }}</dd></div>
            <div class="fact"><dt>{{ t('route.citizen.factAsOf') }}</dt><dd class="tabular">{{ dateShort(r.data.value.asOf) }}</dd></div>
          </dl>
        </div>
        <div class="stages-block">
          <div class="stages-title">
            <span class="eyebrow">{{ t('route.stagesTitle') }}</span>
            <span class="caption" data-testid="route-stage" :data-stage="r.data.value.stage">{{ t('route.stagesCount', { total: r.data.value.timeline.length, done: doneCount }) }}</span>
          </div>
          <RouteTimeline :stages="r.data.value.timeline" variant="citizen" norms />
        </div>
      </section>

      <!-- две колонки: слева «Что дальше» и прогноз, справа ответ врача / «вы ещё ждёте?» и «Где быстрее» -->
      <div class="cols">
        <div class="col">
          <AppCard :title="t('route.whatNext')" label class="what-next" data-testid="what-now">
            <div class="rows">
              <div class="row">
                <span class="row-main"><span class="row-title">{{ r.data.value.dates.plannedAt ? t('route.dates.planned') : t('route.dates.expected') }}</span><span class="row-sub">{{ shortOrgName(r.data.value.organization.moName) }} · {{ r.data.value.organization.moCode }}</span></span>
                <span class="row-value strong tabular">{{ dateShort(r.data.value.dates.plannedAt ?? r.data.value.dates.expectedAt) }}</span>
              </div>
              <div v-if="r.expired.value" class="row">
                <span class="row-main"><span class="row-title">{{ t('route.updateTests', { n: r.expired.value }) }}</span><span class="row-sub">{{ expiredTitles }}</span></span>
                <span class="row-value"><button type="button" class="link-btn" @click="openTests">{{ t('route.citizen.seeTests') }}</button></span>
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
          <AppCard :title="t('route.forecast')" label class="grow" :origin="r.data.value.forecast.fromModel ? 'ml' : 'formula'">
            <HeroNumber :value="`≈ ${days(r.data.value.forecast.p50Days)}`" :unit="t('common.days')" :label="t('route.citizen.forecastLead')" :sub="heroSub" label-first />
            <div v-if="r.target.value" class="benchmark">
              <p class="benchmark-text">{{ t('route.citizen.benchmark', { days: days(r.target.value.value) }) }} <OriginTag kind="formula" class="benchmark-tag" /></p>
              <details class="source">
                <summary>{{ t('route.citizen.sourceToggle') }} <i class="pi pi-chevron-down" aria-hidden="true" /></summary>
                <p class="caption benchmark-source">{{ t('route.citizen.benchmarkSource', { source: r.target.value.source }) }}</p>
              </details>
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
            <p class="muted small faster-lead">{{ t('route.citizen.fasterLead') }}</p>
            <RouteAlternatives :items="r.data.value.alternatives" audience="citizen" :acting="r.acting.value" :pending-code="r.pendingRequest.value?.toMoCode" :action-label="t('route.requestConsider')" :baseline-days="r.data.value.forecast.p50Days" @act="signal('request_redirect', $event)" />
            <div v-if="r.data.value.alternatives.length" class="comment-block" :class="{ open: commentOpen || requestComment }">
              <button type="button" class="comment-toggle" :aria-expanded="commentOpen || !!requestComment" aria-controls="request-comment-box" data-testid="comment-toggle" @click="commentOpen = !commentOpen">
                <i class="pi pi-comment" aria-hidden="true" />{{ t('route.citizen.commentToggle') }}
                <i class="pi chevron" :class="commentOpen || requestComment ? 'pi-chevron-up' : 'pi-chevron-down'" aria-hidden="true" />
              </button>
              <div v-show="commentOpen || requestComment" id="request-comment-box" class="comment-box">
                <p class="comment-note">{{ t('route.citizen.commentHint') }}</p>
                <Textarea id="request-comment" v-model="requestComment" rows="3" auto-resize :aria-label="t('route.citizen.commentLabel')" data-testid="request-comment" />
              </div>
            </div>
          </AppCard>
        </div>
      </div>

      <CollapsibleSection id="route-tests" :key="testsKey" :open="testsOpen" :title="t('route.checklist')" :summary="t('route.checklistSummary', { expired: r.expired.value, valid: r.valid.value })" origin="formula" data-testid="route-tests">
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
.route-card { padding: 0; overflow: hidden; }
.route-card .who { margin: 0; border: 0; border-radius: 0; box-shadow: none; padding: 22px 28px; }
.stages-block { border-top: 1px solid var(--border-soft); padding: 20px 28px 24px; }
.stages-title { display: flex; align-items: baseline; justify-content: space-between; gap: 12px; margin-bottom: 14px; }
.eyebrow { font-size: var(--fs-xs); font-weight: var(--fw-bold); letter-spacing: 0.06em; text-transform: uppercase; color: var(--text-muted); }
.source summary { display: inline-flex; align-items: center; gap: 6px; font-size: var(--fs-sm); color: var(--text-muted); cursor: pointer; list-style: none; }
.source summary::-webkit-details-marker { display: none; }
.source summary i { font-size: 0.6rem; transition: transform .15s; }
.source[open] summary i { transform: rotate(180deg); }
.source .benchmark-source { margin-top: 4px; }
.cols { display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); gap: var(--gap-citizen); align-items: stretch; }
.col { display: flex; flex-direction: column; gap: var(--gap-citizen); min-width: 0; }
.grow { flex: 1; }
#route-tests { scroll-margin-top: 16px; }
.link-btn { border: 0; background: none; padding: 0; font: inherit; font-size: var(--fs-base-sm); font-weight: var(--fw-bold); color: var(--link); cursor: pointer; white-space: nowrap; }
.link-btn:hover { color: var(--accent-strong); }
.benchmark { border-top: 1px solid var(--surface-muted); margin: 16px 0 0; padding-top: 14px; display: flex; flex-direction: column; align-items: flex-start; gap: 6px; }
.benchmark-text { margin: 0; font-size: var(--fs-base); font-weight: var(--fw-semibold); }
.benchmark-source { margin: 0; color: var(--text-muted); line-height: 1.45; }
.benchmark-tag { margin-left: 8px; }
.stages-head { display: inline-flex; align-items: center; gap: 8px; flex-wrap: wrap; }
/* шапка: карточка «Ваша больница» — название крупно, профиль ниже; справа три факта «подпись над значением» */
.who { display: flex; align-items: center; justify-content: space-between; gap: 24px; flex-wrap: wrap; margin-top: 10px; padding: 20px 24px; background: var(--surface); border: 1px solid var(--border-soft); border-radius: var(--radius-card); box-shadow: var(--shadow-card-citizen); }
.who-main { display: flex; flex-direction: column; gap: 4px; min-width: 0; flex: 1 1 380px; }
.who-label { font-size: var(--fs-xs); font-weight: var(--fw-bold); letter-spacing: 0.06em; text-transform: uppercase; color: var(--text-muted); }
.who-name { font-size: 22px; font-weight: var(--fw-extrabold); color: var(--text); line-height: 1.25; letter-spacing: -0.01em; }
.who-profile { font-size: var(--fs-base); color: var(--text-secondary); line-height: 1.45; }
.who-facts { display: flex; gap: 0; margin: 0; flex: none; }
.fact { padding: 2px 22px; border-left: 1px solid var(--border-soft); display: flex; flex-direction: column; gap: 4px; }
.fact:first-child { border-left: 0; padding-left: 0; }
.fact dt { font-size: var(--fs-sm); color: var(--text-muted); }
.fact dd { margin: 0; font-size: 17px; font-weight: var(--fw-extrabold); color: var(--text); white-space: nowrap; }
@media (max-width: 640px) { .who-facts { flex-wrap: wrap; row-gap: 12px; } .fact { padding: 0 14px; } }
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
.comment-block { margin-top: 14px; border-top: 1px solid var(--border-soft); padding-top: 12px; }
.comment-toggle { display: inline-flex; align-items: center; gap: 8px; border: 0; background: none; padding: 4px 0; font: inherit; font-size: var(--fs-base); font-weight: var(--fw-bold); color: var(--link); cursor: pointer; }
.comment-toggle:hover { color: var(--accent-strong); }
.comment-toggle .chevron { font-size: 0.7rem; }
.comment-box { display: flex; flex-direction: column; gap: 8px; margin-top: 8px; }
.comment-note { margin: 0; font-size: var(--fs-sm); color: var(--text-muted); line-height: 1.45; }
.footnote { color: var(--text-faint); }
.grid.cols-2 .card { display: flex; flex-direction: column; }
@media (max-width: 900px) { .cols { grid-template-columns: 1fr; } }
</style>
