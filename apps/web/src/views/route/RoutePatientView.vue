<script setup lang="ts">
import Button from 'primevue/button'
import Textarea from 'primevue/textarea'
import { useToast } from 'primevue/usetoast'
import { computed, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import ErrorBox from '@/components/ErrorBox.vue'
import RouteAlternatives from '@/components/route/RouteAlternatives.vue'
import RouteChecklist from '@/components/route/RouteChecklist.vue'
import RouteFeed from '@/components/route/RouteFeed.vue'
import RouteHistory from '@/components/route/RouteHistory.vue'
import AppCard from '@/components/ui/AppCard.vue'
import CollapsibleSection from '@/components/ui/CollapsibleSection.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import KpiRow from '@/components/ui/KpiRow.vue'
import KpiTile from '@/components/ui/KpiTile.vue'
import PageShell from '@/components/ui/PageShell.vue'
import Skeleton from '@/components/ui/Skeleton.vue'
import StageStepper from '@/components/ui/StageStepper.vue'
import StatusTag from '@/components/ui/StatusTag.vue'
import { useRouteData } from '@/composables/useRouteData'
import { days, pct, refusalWords, shortOrgName, signed } from '@/lib/format'
import { dateShort, nextActionKey } from '@/lib/route'

/** Маршрут пациента для врача (/route/{ref}): шапка с шевронами стадий и флагами, слева панель врача (следующий шаг,
 * сигнал пациента с кнопками и причиной), прогноз с «почему так» и этапы; справа факты, анализы итогом,
 * «где быстрее» с «Направить», решения; липкая панель действий внизу. */
const props = defineProps<{ patientRef: string }>()
const { t } = useI18n()
const toast = useToast()
const r = useRouteData(() => props.patientRef)
const reason = ref('')

const FLAG_TONES: Record<string, 'warn' | 'danger' | 'accent'> = { stuck_over_30: 'warn', refusal_risk: 'danger', faster_alternative: 'accent', patient_signal: 'accent' }
const doctor = computed(() => r.data.value?.doctor ?? null)
const nextAction = computed(() => {
  const key = nextActionKey(doctor.value?.nextActionCode)
  return key ? t(key) : (doctor.value?.nextAction ?? '')
})

function requireReason(): boolean {
  if (reason.value.trim()) return true
  toast.add({ severity: 'warn', summary: t('route.reasonRequired'), life: 3000 })
  return false
}

async function redirect(toMoCode: string) {
  if (!requireReason()) return
  if (await r.redirect(toMoCode, reason.value.trim())) {
    toast.add({ severity: 'success', summary: t('route.redirected'), life: 4000 })
    reason.value = ''
  }
}

async function keep() {
  if (!requireReason()) return
  if (await r.keep(reason.value.trim())) {
    toast.add({ severity: 'success', summary: t('route.keepDone'), life: 4000 })
    reason.value = ''
  }
}

onMounted(r.load)
watch(() => props.patientRef, r.load)
</script>

<template>
  <PageShell :title="t('route.patientTitle')" :as-of="r.data.value?.asOf" :back="{ to: { name: 'worklist' }, label: t('nav.worklist') }">
    <template #title-extra> <span class="mono muted ref">{{ patientRef }}</span></template>
    <template v-if="r.data.value" #subtitle>
      {{ r.data.value.organization.profileName }} · <span :title="r.data.value.organization.moName">{{ shortOrgName(r.data.value.organization.moName) }}</span>
    </template>
    <ErrorBox :error="r.error.value" />
    <EmptyState v-if="r.forbidden.value" :title="t('route.forbidden')" icon="pi pi-lock"><RouterLink :to="{ name: 'worklist' }">{{ t('nav.worklist') }}</RouterLink></EmptyState>
    <EmptyState v-else-if="r.notFound.value" :title="t('route.refNotFound')" :text="patientRef" icon="pi pi-search"><RouterLink :to="{ name: 'worklist' }">{{ t('nav.worklist') }}</RouterLink></EmptyState>
    <template v-else-if="r.busy.value && !r.data.value">
      <AppCard><Skeleton :lines="2" /></AppCard>
      <div class="grid cols-2" style="margin-top: 16px"><AppCard><Skeleton :lines="5" /></AppCard><AppCard><Skeleton :lines="5" /></AppCard></div>
    </template>

    <template v-if="r.data.value && doctor">
      <AppCard dense>
        <StageStepper :stages="r.data.value.timeline" chevrons />
        <div class="chips head-chips">
          <StatusTag v-for="f in doctor.riskFlags" :key="f" :value="t('route.flags.' + f)" :tone="FLAG_TONES[f] ?? 'neutral'" />
          <span class="muted small">{{ t('route.priority') }} <b class="tabular">{{ Math.round(doctor.priority) }}</b> · {{ t('route.daysWaitingShort', { days: r.data.value.daysWaiting }) }}</span>
        </div>
      </AppCard>

      <div class="grid cols-2" style="margin-top: 16px">
        <div class="col">
          <AppCard :title="t('route.doctorPanel')" origin="ml" data-testid="doctor-panel">
            <div class="next-step"><span class="muted small">{{ t('route.nextAction') }}</span><div class="next-text">{{ nextAction }}</div></div>
            <p class="muted small">{{ doctor.explanation }}</p>
            <div v-if="r.openSig.value" class="signal" data-testid="signal-banner">
              <div class="signal-title" :title="r.openSig.value.toMoName ?? ''">
                <i class="pi pi-comment" aria-hidden="true" /> {{ t('route.patientSignal.' + r.openSig.value.kind, { name: shortOrgName(r.openSig.value.toMoName) }) }}
              </div>
              <div class="muted small">{{ dateShort(r.openSig.value.recordedAt) }}<template v-if="r.openSig.value.comment"> · «{{ r.openSig.value.comment }}»</template></div>
              <div class="field" style="margin-top: 8px">
                <label>{{ t('route.reason') }}</label>
                <Textarea v-model="reason" rows="2" auto-resize data-testid="redirect-reason" />
              </div>
              <div class="actions">
                <Button v-if="r.requestedAlternative.value" :label="t('route.referHere')" :loading="r.acting.value === r.requestedAlternative.value.mo.moCode" :disabled="r.acting.value !== null" @click="redirect(r.requestedAlternative.value.mo.moCode)" />
                <Button :label="t('route.keepHere')" severity="secondary" :loading="r.acting.value === 'keep'" :disabled="r.acting.value !== null" data-testid="keep" @click="keep()" />
              </div>
            </div>
          </AppCard>

          <AppCard :title="t('route.forecast')" :origin="r.data.value.forecast.fromModel ? 'ml' : 'formula'" style="margin-top: 16px">
            <KpiRow>
              <KpiTile :value="days(r.data.value.forecast.p50Days)" :label="t('route.p50')" />
              <KpiTile :value="days(r.data.value.forecast.p90Days)" :label="t('route.p90')" />
              <KpiTile :value="doctor.refusalOrgInTraining ? pct(doctor.pRefusal) : refusalWords(doctor.pRefusal)" :label="t('route.refusal')" />
            </KpiRow>
            <p v-if="r.target.value" class="muted small" style="margin: 10px 0 0">{{ t('route.benchmark', { days: days(r.target.value.value), source: r.target.value.source }) }}</p>
            <div v-if="doctor.shap" class="why">
              <CollapsibleSection :title="t('explanationCard.title')" :summary="doctor.shap.factors.length ? `${doctor.shap.factors.length}` : ''">
                <p class="muted small">{{ doctor.shap.summary }}</p>
                <div v-for="f in doctor.shap.factors" :key="f.name" class="factor">
                  <span>{{ f.text }}</span>
                  <span class="contribution" :class="f.contribution >= 0 ? 'plus' : 'minus'">{{ signed(f.contribution) }} {{ t('common.days') }}</span>
                </div>
              </CollapsibleSection>
            </div>
          </AppCard>

          <AppCard :title="t('route.stages')" origin="formula" style="margin-top: 16px">
            <ol class="stages">
              <li v-for="s in r.data.value.timeline" :key="s.code" :class="s.status">
                <span class="stage-title">{{ s.title }}</span>
                <span class="muted small">{{ s.date ? dateShort(s.date) : (s.norm ?? '') }}</span>
              </li>
            </ol>
          </AppCard>
        </div>

        <div class="col">
          <AppCard :title="t('route.facts')">
            <dl class="facts">
              <dt>{{ t('common.organization') }}</dt><dd :title="r.data.value.organization.moName">{{ shortOrgName(r.data.value.organization.moName) }} <span class="mono muted">{{ r.data.value.organization.moCode }}</span></dd>
              <dt>{{ t('common.profile') }}</dt><dd>{{ r.data.value.organization.profileName }}</dd>
              <dt>{{ t('route.dates.issued') }}</dt><dd class="tabular">{{ dateShort(r.data.value.dates.issuedAt) }}</dd>
              <dt>{{ t('route.dates.registered') }}</dt><dd class="tabular">{{ dateShort(r.data.value.dates.registeredAt) }} · {{ t('route.daysWaitingShort', { days: r.data.value.daysWaiting }) }}</dd>
              <dt>{{ t('route.dates.planned') }}</dt><dd class="tabular">{{ dateShort(r.data.value.dates.plannedAt) }}</dd>
              <dt>{{ t('route.dates.expected') }}</dt><dd class="tabular">{{ dateShort(r.data.value.dates.expectedAt) }}</dd>
              <dt>{{ t('route.priority') }}</dt><dd class="tabular">{{ Math.round(doctor.priority) }}</dd>
            </dl>
          </AppCard>

          <div style="margin-top: 16px">
            <CollapsibleSection :title="t('route.checklist')" :summary="t('route.checklistSummary', { expired: r.expired.value, valid: r.valid.value })" :tone="r.expired.value ? 'danger' : undefined" origin="formula">
              <RouteChecklist :items="r.data.value.checklist" :standard="r.data.value.standard" />
            </CollapsibleSection>
          </div>

          <AppCard :title="t('route.whereFaster')" :origin="r.data.value.alternativesModel ? 'ml' : undefined" style="margin-top: 16px">
            <RouteAlternatives :items="r.data.value.alternatives" audience="doctor" :acting="r.acting.value" :action-label="t('route.referHere')" @act="redirect($event)" />
          </AppCard>

          <AppCard :title="t('route.signalsTitle')" style="margin-top: 16px"><RouteFeed :entries="r.entries.value" audience="doctor" /></AppCard>
          <AppCard :title="t('route.pastReferrals')" style="margin-top: 16px"><RouteHistory :items="r.data.value.history" /></AppCard>
        </div>
      </div>

      <div class="sticky-actions">
        <div v-if="!r.openSig.value" class="field reason-inline">
          <label>{{ t('route.reason') }}</label>
          <Textarea v-model="reason" rows="1" auto-resize :placeholder="t('route.reason')" data-testid="redirect-reason" />
        </div>
        <span class="spacer" />
        <RouterLink :to="{ name: 'referral', query: { moCode: r.data.value.organization.moCode, profileCode: r.data.value.organization.profileCode } }">
          <Button :label="t('route.referralAssistant')" icon="pi pi-compass" severity="secondary" outlined />
        </RouterLink>
      </div>
      <p class="muted small">{{ r.data.value.basis }} · {{ t('route.synthetic', { asOf: dateShort(r.data.value.asOf) }) }}</p>
    </template>
  </PageShell>
</template>

<style scoped>
.ref { font-weight: 400; font-size: 0.8em; }
.head-chips { margin-top: 10px; }
.next-step { margin-bottom: 6px; }
.next-text { font-size: 1.1rem; font-weight: 600; }
.signal { margin-top: 12px; padding: 12px; border-radius: var(--dm-radius-sm); background: var(--dm-accent-soft); }
.signal-title { font-weight: 600; }
.signal .actions { margin-top: 8px; }
.why { margin-top: 12px; }
.stages { list-style: none; margin: 0; padding: 0; }
.stages li { display: flex; justify-content: space-between; gap: 12px; padding: 6px 0 6px 14px; border-left: 2px solid var(--dm-hairline); }
.stages li.done { border-color: var(--dm-accent); }
.stages li.current { border-color: var(--dm-accent); }
.stages li.current .stage-title { font-weight: 600; }
.stages li.upcoming .stage-title { color: var(--dm-muted); }
.sticky-actions .spacer { flex: 1; }
.reason-inline { flex: 1 1 320px; }
.reason-inline label { display: none; }
</style>
