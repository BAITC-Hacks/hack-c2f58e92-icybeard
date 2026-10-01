<script setup lang="ts">
import Button from 'primevue/button'
import Checkbox from 'primevue/checkbox'
import Textarea from 'primevue/textarea'
import { useToast } from 'primevue/usetoast'
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import ErrorBox from '@/components/ErrorBox.vue'
import OriginTag from '@/components/OriginTag.vue'
import RouteChecklist from '@/components/route/RouteChecklist.vue'
import RouteFeed from '@/components/route/RouteFeed.vue'
import RouteHistory from '@/components/route/RouteHistory.vue'
import AppCard from '@/components/ui/AppCard.vue'
import CollapsibleSection from '@/components/ui/CollapsibleSection.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import RouteTimeline from '@/components/route/RouteTimeline.vue'
import PageShell from '@/components/ui/PageShell.vue'
import Skeleton from '@/components/ui/Skeleton.vue'
import StatusTag from '@/components/ui/StatusTag.vue'
import { useForecastFactors } from '@/composables/useForecastFactors'
import { useRouteData } from '@/composables/useRouteData'
import { scribe } from '@/api/endpoints'
import type { ScribeConsent } from '@/api/types'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'
import { days, pct, refusalWords, shortOrgName } from '@/lib/format'
import { dateShort, nextActionKey } from '@/lib/route'

/** Маршрут пациента для врача (W-Patient). Сверху одна карточка маршрута: пациент (номер, флаги, факты), больница
 * текстом, этапы и строка «Что сделать». Ниже карточка «Текущая больница» (сроки, риск, «что сделать»
 * списком и обоснование) и карточка «Оставить или перевести»: больницы, где быстрее, списком с выбором, общий комментарий (причина, попадает в
 * журнал), отметка тяжести для перенаправления и одна кнопка «Сохранить решение». Затем свёрнутые «Анализы» и
 * «Почему такой срок» (там же ориентир Минздрава), история решений и запросов. */
const props = defineProps<{ patientRef: string }>()
const { t } = useI18n()
const toast = useToast()
const r = useRouteData(() => props.patientRef)
const refdata = useRefdataStore()
const auth = useAuthStore()
const reason = ref('')
/** Причина для отмены перевода или снятия с листа ожидания — обязательна, попадает в журнал. */
const actionReason = ref('')
const progress = computed(() => r.progress.value)
/** Решение «оставить или перевести» нужно только пока пациент ждёт в своей больнице (по progress.allowed). */
const canDecide = computed(() => r.can('keep') || r.can('redirect'))
const transfer = computed(() => progress.value?.transfer ?? null)
const attempt = computed(() => progress.value?.lastAttempt ?? null)
/** Клинический флаг тяжести (задача 3): применяется только к «Направить» — принимающая организация видит его в /journal/referrals/incoming. */
const severe = ref(false)

const FLAG_TONES: Record<string, 'neutral' | 'danger' | 'accent' | 'warn'> = {
  stuck_over_30: 'neutral', refusal_risk: 'danger', faster_alternative: 'accent', patient_signal: 'warn',
  transfer_pending: 'accent', transferred_in: 'accent', prefers_current: 'neutral', date_overdue: 'danger',
}
const doctor = computed(() => r.data.value?.doctor ?? null)
const nextAction = computed(() => {
  const key = nextActionKey(doctor.value?.nextActionCode)
  return key ? t(key) : (doctor.value?.nextAction ?? '')
})

/** «Что сделать»: сейчас система даёт один шаг, но блок — список, чтобы вместить несколько. */
const todoItems = computed(() => (nextAction.value ? [nextAction.value] : []))

/** Записи приёма этого пациента (AI-скрайб): утверждённые — с памяткой, которую видит пациент; плюс текущая запись. */
const visits = ref<ScribeConsent[]>([])
const VISIT_STATUSES = ['completed', 'recording', 'granted', 'pending']
const shownVisits = computed(() => visits.value.filter((v) => VISIT_STATUSES.includes(v.status)))
async function loadVisits() {
  if (!auth.can('scribe.use')) return
  try {
    visits.value = await scribe.consents(props.patientRef)
  } catch {
    visits.value = [] // скрайб — дополнительная функция, маршрут без него работает
  }
}
watch(() => props.patientRef, loadVisits, { immediate: true })
const refusalHigh = computed(() => (doctor.value?.pRefusal ?? 0) > 0.2)
const refusalText = computed(() => (doctor.value ? (doctor.value.refusalOrgInTraining ? pct(doctor.value.pRefusal) : refusalWords(doctor.value.pRefusal)) : ''))

const factors = useForecastFactors(computed(() => doctor.value?.shap?.factors), computed(() => r.data.value?.organization.profileName))

/** Решение врача: «Оставить в текущей» или «Перевести в выбранную» (choice — код организации из списка «где
 * быстрее»); комментарий обязателен и попадает в журнал. */
const choice = ref<string | null>(null)
const choiceIsRedirect = computed(() => choice.value !== null)
/** Выбор снимается повторным кликом по выбранной больнице или кликом за пределами карточки решения
 * (внутри карточки — поле причины и кнопки — выбор сохраняется). */
const decisionCard = ref<{ $el: HTMLElement } | null>(null)
function onOutside(e: MouseEvent) {
  const el = decisionCard.value?.$el
  if (choice.value && el && e.target instanceof Node && !el.contains(e.target)) {
    choice.value = null
    severe.value = false
  }
}
onMounted(() => document.addEventListener('mousedown', onOutside))
onBeforeUnmount(() => document.removeEventListener('mousedown', onOutside))
function toggleChoice(code: string) {
  choice.value = choice.value === code ? null : code
  if (!choice.value) severe.value = false
}
async function saveDecision(kind: 'keep' | 'redirect') {
  if (kind === 'redirect' && !choice.value) return
  if (!reason.value.trim()) {
    toast.add({ severity: 'warn', summary: t('route.reasonRequired'), life: 3000 })
    return
  }
  const ok = kind === 'redirect' ? await r.redirect(choice.value!, reason.value.trim(), severe.value) : await r.keep(reason.value.trim())
  if (ok) {
    toast.add({ severity: 'success', summary: kind === 'redirect' ? t('route.redirected') : t('route.keepDone'), life: 4000 })
    choice.value = null
    reason.value = ''
    severe.value = false
  }
}

async function routeAction(kind: 'cancel_transfer' | 'close') {
  if (!actionReason.value.trim()) {
    toast.add({ severity: 'warn', summary: t('route.progress.reasonRequired'), life: 3000 })
    return
  }
  const ok = kind === 'close' ? await r.close(actionReason.value.trim()) : await r.cancelTransfer(actionReason.value.trim())
  if (ok) {
    toast.add({ severity: 'success', summary: t(kind === 'close' ? 'route.progress.closeDone' : 'route.progress.cancelDone'), life: 4000 })
    actionReason.value = ''
  }
}

onMounted(r.load)
watch(() => props.patientRef, r.load)
</script>

<template>
  <PageShell :title="t('route.patientTitle')" :back="{ to: { name: 'worklist' }, label: t('nav.group.patients') }">
    <ErrorBox :error="r.error.value" />
    <EmptyState v-if="r.forbidden.value" :title="t('route.forbidden')" icon="pi pi-lock"><RouterLink class="link-arrow" :to="{ name: 'worklist' }">{{ t('nav.worklist') }}</RouterLink></EmptyState>
    <EmptyState v-else-if="r.notFound.value" :title="t('route.refNotFound')" :text="patientRef" icon="pi pi-search"><RouterLink class="link-arrow" :to="{ name: 'worklist' }">{{ t('nav.worklist') }}</RouterLink></EmptyState>
    <AppCard v-else-if="r.busy.value && !r.data.value"><Skeleton :lines="8" /></AppCard>

    <template v-if="r.data.value && doctor">
      <!-- карточка маршрута: пациент и больница, этапы, «что сделать» -->
      <section class="card route-card" data-testid="doctor-panel">
        <div class="who">
          <div class="who-main">
            <span class="eyebrow">{{ t('route.doctorView.patient') }}</span>
            <div class="name-row">
              <span class="who-name tabular">{{ patientRef }}</span>
              <RouterLink v-if="auth.can('scribe.use') && progress?.side !== 'none'" class="record-visit" :to="{ name: 'scribe', query: { patientRef } }" data-testid="record-visit">
                <i class="pi pi-microphone" aria-hidden="true" />{{ t('route.doctorView.recordVisit') }}
              </RouterLink>
            </div>
            <span class="chips"><StatusTag v-for="f in doctor.riskFlags" :key="f" :value="t('route.flags.' + f)" :tone="FLAG_TONES[f] ?? 'neutral'" /></span>
            <span v-if="progress" class="status-line" data-testid="route-status" :data-status="progress.status">{{ t('route.progress.status.' + progress.status) }}<template v-if="progress.closedReason"> · {{ t('route.progress.closed.' + progress.closedReason) }}</template></span>
          </div>
          <dl class="who-facts">
            <div class="fact"><dt>{{ t('route.citizen.factSince') }}</dt><dd class="tabular">{{ dateShort(r.data.value.dates.registeredAt) }}</dd></div>
            <div class="fact"><dt>{{ t('route.doctorView.waiting') }}</dt><dd class="tabular">{{ t('route.citizen.factDays', { days: r.data.value.daysWaiting }) }}</dd></div>
            <div class="fact"><dt>{{ t('route.priority') }}</dt><dd class="tabular">{{ t('doctor.worklist.priorityOf', { n: Math.round(doctor.priority), max: 10 }) }}</dd></div>
            <div class="fact"><dt>{{ t('route.citizen.factAsOf') }}</dt><dd class="tabular">{{ dateShort(r.data.value.asOf) }}</dd></div>
          </dl>
        </div>
        <div class="stages-block">
          <RouteTimeline :stages="r.data.value.timeline" variant="citizen" norms />
        </div>
      </section>

      <!-- текущая больница: её сроки и риск, ниже — что сделать (список, готов к нескольким пунктам) и обоснование -->
      <section class="card hospital-card" data-testid="current-hospital">
        <div class="h-head">
          <span class="eyebrow">{{ t('route.doctorView.currentHospital') }}</span>
          <OriginTag :kind="r.data.value.forecast.fromModel ? 'ml' : 'formula'" />
        </div>
        <div class="h-name" :title="r.data.value.organization.moName">{{ shortOrgName(r.data.value.organization.moName) }}</div>
        <div class="h-sub">{{ r.data.value.organization.profileName }} · {{ r.data.value.organization.moCode }}</div>
        <dl class="h-stats">
          <div class="stat"><dt>{{ t('route.doctorView.half') }}</dt><dd class="tabular">≈ {{ days(r.data.value.forecast.p50Days) }} <small>{{ t('common.days') }}</small></dd></div>
          <div class="stat"><dt>{{ t('route.doctorView.ninety') }}</dt><dd class="tabular">≈ {{ days(r.data.value.forecast.p90Days) }} <small>{{ t('common.days') }}</small></dd></div>
          <div class="stat"><dt>{{ t('route.dates.expected') }}</dt><dd class="tabular">{{ dateShort(r.data.value.dates.expectedAt) }}</dd></div>
          <div class="stat"><dt>{{ t('route.doctorView.refusal') }}</dt><dd class="tabular" :class="{ danger: refusalHigh }">{{ refusalText }}</dd></div>
        </dl>
        <div class="h-todo" data-testid="route-todo">
          <span class="eyebrow">{{ t('route.doctorView.todo') }}</span>
          <ul class="todo-list">
            <li v-for="(item, i) in todoItems" :key="i">{{ item }}</li>
          </ul>
          <p v-if="doctor.explanation" class="todo-why"><span class="why-label">{{ t('route.doctorView.basis') }}:</span> {{ doctor.explanation }}</p>
        </div>
        <details v-if="factors.length" class="more" data-testid="why-term">
          <summary>{{ t('route.doctorView.whyTitle') }} <i class="pi pi-chevron-down" aria-hidden="true" /></summary>
          <p class="more-lead">{{ t('route.doctorView.whyLead') }}</p>
          <div class="rows">
            <div v-for="f in factors" :key="f.name" class="row">
              <span class="row-main"><span>{{ f.label }}</span><span v-if="f.hint" class="row-sub">{{ f.hint }}</span></span>
              <span class="row-value factor-effect" :class="f.dir">{{ f.effect }}</span>
            </div>
          </div>
          <p class="more-note">{{ t('route.doctorView.whyNote') }}</p>
        </details>
        <!-- ориентир — тихой строкой, как у гражданина: текст и «Источник» по клику -->
        <div v-if="r.target.value" class="benchmark">
          <p class="benchmark-text">{{ t('route.citizen.benchmark', { days: days(r.target.value.value) }) }}</p>
          <details class="source">
            <summary>{{ t('route.citizen.sourceToggle') }} <i class="pi pi-chevron-down" aria-hidden="true" /></summary>
            <p class="caption benchmark-source">{{ t('route.citizen.benchmarkSource', { source: r.target.value.source }) }}</p>
          </details>
        </div>
      </section>

      <!-- решение: все варианты одним списком, общий комментарий, одна кнопка -->
      <AppCard v-if="canDecide" ref="decisionCard" :title="t('route.doctorView.whereTitle')" label :origin="r.data.value.alternativesModel ? 'ml' : undefined" data-testid="decision-card">
        <div v-if="r.openSig.value" class="signal" data-testid="signal-banner" :title="r.openSig.value.toMoName ?? ''">
          <i class="pi pi-comment" aria-hidden="true" />
          <span>{{ t('route.patientSignal.' + r.openSig.value.kind, { name: shortOrgName(r.openSig.value.toMoName) }) }}<template v-if="r.openSig.value.comment"> — «{{ r.openSig.value.comment }}»</template><span class="muted"> · {{ dateShort(r.openSig.value.recordedAt) }}</span></span>
        </div>
        <p v-if="attempt" class="attempt" data-testid="last-attempt">
          <span class="muted">{{ t('route.progress.lastAttempt') }}:</span> {{ t('route.progress.attempt.' + attempt.outcome, { name: shortOrgName(attempt.toMoName) }) }}<template v-if="attempt.reason"> — «{{ attempt.reason }}»</template><span class="muted"> · {{ dateShort(attempt.at) }}</span>
        </p>
        <p v-if="progress?.prefersCurrent" class="attempt muted">{{ t('route.progress.prefersCurrent') }}</p>
        <div class="options" role="radiogroup" :aria-label="t('route.doctorView.whereTitle')">
          <label v-for="a in r.alternatives.value" :key="a.mo.moCode" class="option" :class="{ on: choice === a.mo.moCode }">
            <input :checked="choice === a.mo.moCode" type="radio" name="where" :value="a.mo.moCode" data-testid="redirect" @click="toggleChoice(a.mo.moCode)" />
            <span class="opt-main">
              <span class="opt-name" :title="a.mo.name">{{ shortOrgName(a.mo.name) }}<StatusTag v-if="r.openSig.value?.toMoCode === a.mo.moCode" :value="t('route.doctorView.requested')" tone="warn" class="opt-tag" /></span>
              <span class="opt-sub">{{ a.mo.moCode }}<template v-if="a.isNeighborRegion"> · {{ t('citizen.wait.neighborRegion', { region: refdata.regionName(a.mo.regionKato) }) }}</template> · {{ t('route.doctorView.altNine', { days: days(a.p90Days) }) }} · <span :class="{ risk: a.pRefusal > 0.2 }">{{ t('route.doctorView.altRefusal', { pct: pct(a.pRefusal) }) }}</span></span>
            </span>
            <span class="opt-wait"><span class="opt-wait-label">{{ t('route.doctorView.halfShort') }}</span><span class="opt-days tabular faster">≈ {{ days(a.p50Days) }} {{ t('common.days') }}</span></span>
          </label>
          <p v-if="!r.alternatives.value.length" class="muted small">{{ t('doctor.referral.noAlternatives') }}</p>
        </div>
        <div class="decide">
          <label class="field-label" for="decision-reason">{{ t('route.doctorView.comment') }} <span class="req">{{ t('route.doctorView.required') }}</span></label>
          <Textarea id="decision-reason" v-model="reason" rows="2" auto-resize :placeholder="t('route.doctorView.reasonExample')" data-testid="redirect-reason" />
          <div class="decide-foot">
            <label class="severe-check" :class="{ off: !choiceIsRedirect }" :title="choiceIsRedirect ? '' : t('route.doctorView.severeOff')"><Checkbox v-model="severe" binary input-id="severe" :disabled="!choiceIsRedirect" data-testid="redirect-severe" /> <span>{{ t('route.severeCheckbox') }}</span></label>
            <span class="spacer" />
             <Button :label="t('route.keepCurrent')" severity="secondary" size="small" :disabled="r.acting.value !== null" :loading="r.acting.value === 'keep'" data-testid="keep" @click="saveDecision('keep')" />
            <Button :label="t('route.doctorView.transfer')" size="small" :disabled="!choice || r.acting.value !== null" :loading="r.acting.value !== null && r.acting.value !== 'keep'" data-testid="decision-confirm" @click="saveDecision('redirect')" />
          </div>
          <div class="assistant-line">
            <span class="muted small">{{ t('route.doctorView.assistantHint') }}</span>
            <RouterLink class="link-arrow small" :to="{ name: 'referral', query: { moCode: r.data.value.organization.moCode, profileCode: r.data.value.organization.profileCode } }">{{ t('route.doctorView.toAssistant') }}</RouterLink>
          </div>
        </div>
      </AppCard>

      <AppCard v-else-if="progress" :title="t('route.progress.title')" label data-testid="transfer-card">
        <div v-if="r.openSig.value" class="signal" :title="r.openSig.value.toMoName ?? ''">
          <i class="pi pi-comment" aria-hidden="true" />
          <span>{{ t('route.patientSignal.' + r.openSig.value.kind, { name: shortOrgName(r.openSig.value.toMoName) }) }}<template v-if="r.openSig.value.comment"> — «{{ r.openSig.value.comment }}»</template><span class="muted"> · {{ dateShort(r.openSig.value.recordedAt) }}</span></span>
        </div>
        <div class="rows">
          <div class="row"><span class="row-main row-title">{{ t('route.progress.status.' + progress.status) }}</span><span v-if="progress.closedReason" class="row-value">{{ t('route.progress.closed.' + progress.closedReason) }}</span></div>
          <div v-if="transfer && progress.status !== 'withdrawal_requested'" class="row">
            <span class="row-main"><span :title="transfer.toMoName">{{ t('route.progress.transferTo', { name: shortOrgName(transfer.toMoName) }) }}</span><span v-if="transfer.reason" class="row-sub">{{ t('route.feed.reason') }}: {{ transfer.reason }}</span></span>
            <span v-if="transfer.severe" class="row-value"><StatusTag :value="t('route.severeFlag')" tone="danger" /></span>
          </div>
          <div v-if="transfer?.plannedAt" class="row"><span class="row-main row-title">{{ t('route.progress.plannedAt', { date: dateShort(transfer.plannedAt) }) }}</span></div>
          <p v-if="progress.overdue" class="overdue">{{ t('route.progress.overdue') }}</p>
          <p v-if="progress.side === 'origin' && progress.responsibleMoCode !== progress.originMoCode" class="muted small">{{ t('route.progress.responsible', { name: shortOrgName(progress.responsibleMoName) }) }}</p>
        </div>
        <div v-if="r.can('cancel_transfer') || r.can('close')" class="decide">
          <label class="field-label" for="action-reason">{{ r.can('close') ? t('route.progress.closeReason') : t('route.progress.cancelReason') }} <span class="req">{{ t('route.doctorView.required') }}</span></label>
          <Textarea id="action-reason" v-model="actionReason" rows="2" auto-resize data-testid="action-reason" />
          <div class="decide-foot">
            <span class="spacer" />
            <Button v-if="r.can('cancel_transfer')" :label="t('route.progress.cancel')" severity="secondary" size="small" :loading="r.acting.value === 'cancel_transfer'" :disabled="r.acting.value !== null" data-testid="cancel-transfer" @click="routeAction('cancel_transfer')" />
            <Button v-if="r.can('close')" :label="t('route.progress.close')" size="small" :loading="r.acting.value === 'close'" :disabled="r.acting.value !== null" data-testid="close-route" @click="routeAction('close')" />
          </div>
        </div>
        <RouterLink v-if="progress.side === 'receiving' && !progress.closedReason" class="link-arrow small" :to="{ name: 'incoming-referrals' }">{{ t('route.progress.toIncoming') }}</RouterLink>
      </AppCard>

      <CollapsibleSection :title="t('route.checklist')" :summary="t('route.checklistSummary', { expired: r.expired.value, valid: r.valid.value })" :tone="r.expired.value ? 'danger' : undefined" origin="formula">
        <RouteChecklist :items="r.data.value.checklist" :standard="r.data.value.standard" />
      </CollapsibleSection>


      <AppCard v-if="auth.can('scribe.use')" :title="t('route.doctorView.visitsTitle')" label data-testid="patient-visits">
        <p v-if="!shownVisits.length" class="muted small">{{ t('route.doctorView.visitsEmpty') }}</p>
        <ul v-else class="visits">
          <li v-for="v in shownVisits" :key="v.requestId" class="visit">
            <i class="pi" :class="v.status === 'completed' ? 'pi-file-check' : 'pi-microphone'" aria-hidden="true" />
            <div class="visit-main">
              <span class="visit-title">{{ v.status === 'completed' ? t('route.doctorView.visitDone') : t('doctor.scribe.consentStatus.' + v.status) }}</span>
              <span class="caption">{{ dateShort(v.approvedAt ?? v.answeredAt ?? v.requestedAt) }}<template v-if="v.moName"> · {{ shortOrgName(v.moName) }}</template></span>
            </div>
            <RouterLink v-if="v.status === 'completed' && v.leafletToken" class="visit-link" :to="{ name: 'leaflet', params: { token: v.leafletToken } }" target="_blank">{{ t('route.doctorView.openLeaflet') }}</RouterLink>
            <RouterLink v-else-if="v.status !== 'completed'" class="visit-link" :to="{ name: 'scribe', query: { patientRef } }">{{ t('route.doctorView.openScribe') }}</RouterLink>
          </li>
        </ul>
      </AppCard>

      <div class="grid cols-2">
        <AppCard :title="t('route.signalsTitle')" label><div class="scroll-list"><RouteFeed :entries="r.journal.value" audience="doctor" /></div></AppCard>
        <AppCard :title="t('route.pastReferrals')" label><div class="scroll-list"><RouteHistory :items="r.data.value.history" /></div></AppCard>
      </div>
      <p class="caption footnote">{{ r.data.value.basis }} · {{ t('route.synthetic', { asOf: dateShort(r.data.value.asOf) }) }}</p>
    </template>
  </PageShell>
</template>

<style scoped>
.route-card { padding: 0; overflow: hidden; }
.who { display: flex; align-items: flex-start; justify-content: space-between; gap: 20px; flex-wrap: wrap; padding: 18px 24px 14px; }
.who-main { display: flex; flex-direction: column; gap: 4px; min-width: 0; flex: 1 1 380px; }
.eyebrow { font-size: var(--fs-xs); font-weight: var(--fw-bold); letter-spacing: 0.06em; text-transform: uppercase; color: var(--text-muted); }
.who-name { font-size: 20px; font-weight: var(--fw-extrabold); color: var(--text); line-height: 1.25; }
.who-sub { font-size: var(--fs-base); color: var(--text-secondary); }
.chips { display: flex; gap: 6px; flex-wrap: wrap; margin-top: 4px; }
.who-facts { display: flex; margin: 0; flex: none; }
.fact { padding: 2px 18px; border-left: 1px solid var(--border-soft); display: flex; flex-direction: column; gap: 4px; }
.fact:first-child { border-left: 0; padding-left: 0; }
.fact dt { font-size: var(--fs-sm); color: var(--text-muted); }
.fact dd { margin: 0; font-size: var(--fs-md); font-weight: var(--fw-bold); color: var(--text); white-space: nowrap; }
.stages-block { border-top: 1px solid var(--border-soft); padding: 16px 24px; }
.hospital-card { padding: 18px 24px; display: flex; flex-direction: column; gap: 4px; }
.h-head { display: flex; align-items: center; gap: 10px; }
.h-name { font-size: var(--fs-lg); font-weight: var(--fw-extrabold); margin-top: 2px; }
.h-sub { font-size: var(--fs-base-sm); color: var(--text-secondary); }
.h-stats { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); margin: 14px 0 0; padding: 14px 0; border-top: 1px solid var(--border-soft); border-bottom: 1px solid var(--border-soft); }
.stat { display: flex; flex-direction: column; gap: 4px; padding: 0 16px; border-left: 1px solid var(--border-soft); min-width: 0; }
.stat:first-child { border-left: 0; padding-left: 0; }
.stat dt { font-size: var(--fs-sm); color: var(--text-muted); line-height: 1.35; }
.stat dd { margin: 0; font-size: var(--fs-xl); font-weight: var(--fw-extrabold); }
.stat dd small { font-size: var(--fs-base-sm); font-weight: var(--fw-bold); color: var(--text-muted); }
.stat dd.danger { color: var(--danger-text); }
.h-todo { display: flex; flex-direction: column; gap: 6px; padding-top: 12px; }
.todo-list { margin: 0; padding-left: 20px; display: flex; flex-direction: column; gap: 4px; font-size: var(--fs-base); font-weight: var(--fw-semibold); line-height: 1.45; }
.todo-why { margin: 2px 0 0; font-size: var(--fs-base-sm); color: var(--text-secondary); line-height: 1.5; }
.why-label { color: var(--text-muted); }
.more { margin-top: 10px; padding-top: 10px; border-top: 1px solid var(--border-soft); }
.more summary { display: inline-flex; align-items: center; gap: 6px; font-size: var(--fs-base-sm); font-weight: var(--fw-bold); color: var(--link); cursor: pointer; list-style: none; }
.more summary::-webkit-details-marker { display: none; }
.more summary i { font-size: 0.6rem; transition: transform .15s; }
.more[open] summary i { transform: rotate(180deg); }
.more-lead { margin: 8px 0 4px; font-size: var(--fs-base-sm); color: var(--text-secondary); line-height: 1.5; }
.more-note { margin: 6px 0 0; font-size: var(--fs-sm); color: var(--text-muted); }
.benchmark { border-top: 1px solid var(--border-soft); margin: 10px 0 0; padding-top: 10px; display: flex; flex-direction: column; align-items: flex-start; gap: 6px; }
.benchmark-text { margin: 0; font-size: var(--fs-base); font-weight: var(--fw-semibold); }
.source summary { display: inline-flex; align-items: center; gap: 6px; font-size: var(--fs-sm); color: var(--text-muted); cursor: pointer; list-style: none; }
.source summary::-webkit-details-marker { display: none; }
.source summary i { font-size: 0.6rem; transition: transform .15s; }
.source[open] summary i { transform: rotate(180deg); }
.benchmark-source { margin: 4px 0 0; color: var(--text-muted); line-height: 1.45; }
.spacer { flex: 1; }
.more .caption { margin: 0; }
.assistant-line { display: flex; align-items: center; justify-content: space-between; gap: 12px; flex-wrap: wrap; margin-top: 6px; padding-top: 10px; border-top: 1px dashed var(--border-soft); }
@media (max-width: 900px) { .h-stats { grid-template-columns: repeat(2, minmax(0, 1fr)); row-gap: 14px; } .stat:nth-child(3) { border-left: 0; padding-left: 0; } }
.signal { display: flex; align-items: flex-start; gap: 10px; padding: 10px 12px; margin-bottom: 10px; border-radius: var(--radius-md); background: var(--surface-muted); font-size: var(--fs-base); }
.signal .pi { color: var(--text-secondary); margin-top: 3px; }
.options { display: flex; flex-direction: column; }
.option { display: flex; align-items: center; gap: 12px; padding: 10px 12px; border: 0; box-shadow: inset 0 -1px 0 var(--border-soft); border-radius: 0; cursor: pointer; }
.option:last-of-type { box-shadow: none; }
.option:hover { background: var(--surface-hover); }
.option.on { background: var(--accent-subtle); }
.option input { appearance: none; -webkit-appearance: none; width: 18px; height: 18px; flex: none; margin: 0; border: 2px solid var(--border); border-radius: 50%; background: var(--surface); box-sizing: border-box; cursor: pointer; transition: border-color .12s, box-shadow .12s; }
.option input:checked { border-color: var(--accent); box-shadow: inset 0 0 0 3px var(--surface), inset 0 0 0 9px var(--accent); }
.option input:focus { outline: none; }
.option input:focus-visible { box-shadow: 0 0 0 3px var(--accent-soft); }
.option input:checked:focus-visible { box-shadow: inset 0 0 0 3px var(--surface), inset 0 0 0 9px var(--accent), 0 0 0 3px var(--accent-soft); }
.opt-main { display: flex; flex-direction: column; gap: 2px; min-width: 0; flex: 1; }
.opt-name { font-size: var(--fs-base); font-weight: var(--fw-semibold); display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
.opt-sub { font-size: var(--fs-sm); color: var(--text-muted); }
.opt-sub .risk { color: var(--danger-text); }
.opt-wait { display: flex; flex-direction: column; align-items: flex-end; gap: 2px; flex: none; }
.opt-wait-label { font-size: var(--fs-sm); color: var(--text-muted); white-space: nowrap; }
.opt-days { font-weight: var(--fw-bold); white-space: nowrap; }
.req { font-weight: var(--fw-regular); color: var(--text-muted); }
.opt-days.faster { color: var(--success-text); }
.decide { display: flex; flex-direction: column; gap: 6px; margin-top: 12px; padding-top: 12px; border-top: 1px solid var(--border-soft); }
.decide :deep(.p-textarea) { width: 100%; }
.field-label { font-size: var(--fs-sm); font-weight: var(--fw-bold); color: var(--text-secondary); }
.decide-foot { display: flex; align-items: center; gap: 14px; flex-wrap: wrap; }
.severe-check.off { color: var(--text-muted); }
.severe-check { display: flex; align-items: center; gap: 8px; font-size: var(--fs-base-sm); }
.lead { margin: 0 0 6px; }
.row-main { min-width: 0; display: flex; flex-direction: column; gap: 2px; }
.scroll-list { max-height: 340px; overflow-y: auto; padding-right: 4px; }
.name-row { display: flex; align-items: center; gap: 12px; flex-wrap: wrap; }
.record-visit { display: inline-flex; align-items: center; gap: 6px; height: 28px; padding: 0 12px; border: 1px solid var(--border); border-radius: var(--radius-pill);
  font-size: var(--fs-sm); font-weight: var(--fw-semibold); color: var(--text-secondary); text-decoration: none; white-space: nowrap; transition: border-color .12s, color .12s; }
.record-visit .pi { font-size: 12px; }
.visits { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; }
.visit { display: flex; align-items: center; gap: 12px; padding: 12px 0; border-top: 1px solid var(--border-soft); }
.visit:first-child { border-top: 0; padding-top: 4px; }
.visit > .pi { width: 32px; height: 32px; flex: none; display: grid; place-items: center; border-radius: 50%; background: var(--accent-soft); color: var(--accent-strong); font-size: 14px; }
.visit-main { display: flex; flex-direction: column; gap: 2px; flex: 1; min-width: 0; }
.visit-title { font-weight: var(--fw-bold); }
.visit-link { font-weight: var(--fw-bold); color: var(--link, var(--accent)); text-decoration: none; white-space: nowrap; }
.visit-link:hover { text-decoration: underline; }
.record-visit:hover { border-color: var(--accent); color: var(--accent-strong); }
.status-line { font-size: var(--fs-base-sm); color: var(--text-secondary); margin-top: 2px; }
.attempt { margin: 0 0 8px; font-size: var(--fs-base-sm); line-height: 1.45; }
.overdue { margin: 4px 0 0; font-size: var(--fs-base-sm); font-weight: var(--fw-semibold); color: var(--danger-text); }
.rows .row { display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 6px 0; }
.row-title { font-weight: var(--fw-semibold); }
.row-sub { font-size: var(--fs-sm); color: var(--text-muted); }

.factor-effect { font-weight: var(--fw-bold); white-space: nowrap; }
.factor-effect.plus { color: var(--danger-text); }
.factor-effect.minus { color: var(--success-text); }
.factor-effect.zero { color: var(--text-muted); }
.grid.cols-2 .card { display: flex; flex-direction: column; }
.footnote { color: var(--text-faint); }
@media (max-width: 640px) {
  .who-facts { flex-wrap: wrap; row-gap: 10px; } .fact { padding: 0 12px; }
  .who, .stages-block, .todo { padding-inline: 16px; }
  .decide-foot :deep(.p-button) { width: 100%; }
}
</style>
