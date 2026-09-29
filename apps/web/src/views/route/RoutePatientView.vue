<script setup lang="ts">
import Button from 'primevue/button'
import Checkbox from 'primevue/checkbox'
import InputText from 'primevue/inputtext'
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
import HeroNumber from '@/components/ui/HeroNumber.vue'
import PageShell from '@/components/ui/PageShell.vue'
import Skeleton from '@/components/ui/Skeleton.vue'
import StageStepper from '@/components/ui/StageStepper.vue'
import StatusTag from '@/components/ui/StatusTag.vue'
import { useRouteData } from '@/composables/useRouteData'
import { days, pct, refusalWords, shortOrgName, signed } from '@/lib/format'
import { dateShort, nextActionKey } from '@/lib/route'

/** Маршрут пациента для врача (W-Patient): «← Пациенты», реф с чипами флагов, подпись фактов, горизонтальный прогресс
 * этапов; слева «Прогноз для текущей организации» с «почему так», справа сигнал пациента (heal-wash), «Где быстрее»
 * с кнопками «Направить», анализы; внизу панель действий: причина, «Открыть направление», «Оставить в текущей»,
 * ссылка на скрайб. */
const props = defineProps<{ patientRef: string }>()
const { t } = useI18n()
const toast = useToast()
const r = useRouteData(() => props.patientRef)
const reason = ref('')
/** Клинический флаг тяжести (задача 3): применяется только к «Направить» — принимающая организация видит его в /journal/referrals/incoming. */
const severe = ref(false)

const FLAG_TONES: Record<string, 'neutral' | 'danger' | 'accent'> = { stuck_over_30: 'neutral', refusal_risk: 'danger', faster_alternative: 'accent', patient_signal: 'accent' }
const doctor = computed(() => r.data.value?.doctor ?? null)
const nextAction = computed(() => {
  const key = nextActionKey(doctor.value?.nextActionCode)
  return key ? t(key) : (doctor.value?.nextAction ?? '')
})
const alternativesCount = computed(() => r.data.value?.alternatives.length ?? 0)

function requireReason(): boolean {
  if (reason.value.trim()) return true
  toast.add({ severity: 'warn', summary: t('route.reasonRequired'), life: 3000 })
  return false
}

async function redirect(toMoCode: string) {
  if (!requireReason()) return
  if (await r.redirect(toMoCode, reason.value.trim(), severe.value)) {
    toast.add({ severity: 'success', summary: t('route.redirected'), life: 4000 })
    reason.value = ''
    severe.value = false
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
  <PageShell :title="patientRef" :back="{ to: { name: 'worklist' }, label: t('nav.group.patients') }">
    <template v-if="doctor" #title-extra>
      <StatusTag v-for="f in doctor.riskFlags" :key="f" :value="t('route.flags.' + f)" :tone="FLAG_TONES[f] ?? 'neutral'" />
    </template>
    <template v-if="r.data.value && doctor" #subtitle>
      {{ r.data.value.organization.profileName }} · <span :title="r.data.value.organization.moName">{{ shortOrgName(r.data.value.organization.moName) }}</span> · {{ r.data.value.organization.moCode }} ·
      {{ t('route.since', { date: dateShort(r.data.value.dates.registeredAt), days: r.data.value.daysWaiting }) }} · {{ t('route.priority').toLowerCase() }} {{ Math.round(doctor.priority) }} · {{ t('shell.asOf', { date: dateShort(r.data.value.asOf) }) }}
    </template>
    <ErrorBox :error="r.error.value" />
    <EmptyState v-if="r.forbidden.value" :title="t('route.forbidden')" icon="pi pi-lock"><RouterLink class="link-arrow" :to="{ name: 'worklist' }">{{ t('nav.worklist') }}</RouterLink></EmptyState>
    <EmptyState v-else-if="r.notFound.value" :title="t('route.refNotFound')" :text="patientRef" icon="pi pi-search"><RouterLink class="link-arrow" :to="{ name: 'worklist' }">{{ t('nav.worklist') }}</RouterLink></EmptyState>
    <div v-else-if="r.busy.value && !r.data.value" class="main-grid">
      <AppCard><Skeleton :lines="6" /></AppCard>
      <AppCard><Skeleton :lines="5" /></AppCard>
    </div>

    <template v-if="r.data.value && doctor">
      <StageStepper :stages="r.data.value.timeline" norms class="progress" />

      <div class="main-grid">
        <AppCard :title="t('route.forecastCurrentOrg')" label :origin="r.data.value.forecast.fromModel ? 'ml' : 'formula'" data-testid="doctor-panel">
          <div class="org-line" :title="r.data.value.organization.moName">{{ shortOrgName(r.data.value.organization.moName) }} <span class="caption">{{ r.data.value.organization.moCode }}</span></div>
          <HeroNumber :value="days(r.data.value.forecast.p50Days)" :unit="`${t('common.days')} — ${t('hero.half')}`" label="" compact class="hero-line" />
          <div class="facts-line muted tabular">
            <span>{{ t('hero.nineOfTen', { days: days(r.data.value.forecast.p90Days) }) }}</span><span>·</span>
            <span>{{ t('route.refusal') }} <b class="ink">{{ doctor.refusalOrgInTraining ? pct(doctor.pRefusal) : refusalWords(doctor.pRefusal) }}</b></span>
            <template v-if="alternativesCount"><span>·</span><span>{{ t('route.alternativesCount', { n: alternativesCount }) }}</span></template>
          </div>
          <div class="next-step"><span class="eyebrow">{{ t('route.nextAction') }}</span><div class="next-text">{{ nextAction }}</div><p class="muted small" style="margin: 4px 0 0">{{ doctor.explanation }}</p></div>
          <template v-if="doctor.shap">
            <div class="eyebrow why-title">{{ t('explanationCard.title') }}</div>
            <div v-for="f in doctor.shap.factors" :key="f.name" class="factor small">
              <span>{{ f.text }}</span>
              <span class="contribution" :class="f.contribution >= 0 ? 'plus' : 'minus'">{{ signed(f.contribution) }} {{ t('common.days') }}</span>
            </div>
          </template>
          <p class="caption" style="margin: 10px 0 0">
            <template v-if="r.target.value">{{ t('route.benchmark', { days: days(r.target.value.value), source: r.target.value.source }) }} · </template>{{ t('route.expectedDateShort', { date: dateShort(r.data.value.dates.expectedAt) }) }}
          </p>
        </AppCard>

        <div class="col">
          <section v-if="r.openSig.value" class="card signal-banner" data-testid="signal-banner">
            <i class="pi pi-comment" aria-hidden="true" />
            <span class="signal-text">
              <span class="signal-title" :title="r.openSig.value.toMoName ?? ''">{{ t('route.patientSignal.' + r.openSig.value.kind, { name: shortOrgName(r.openSig.value.toMoName) }) }}</span>
              <span class="muted small"><template v-if="r.openSig.value.comment">«{{ r.openSig.value.comment }}» · </template>{{ dateShort(r.openSig.value.recordedAt) }}</span>
            </span>
          </section>

          <AppCard :title="t('route.whereFaster')" :origin="r.data.value.alternativesModel ? 'ml' : undefined">
            <template #header><span class="caption">{{ t('route.sameRegionProfile') }}</span></template>
            <RouteAlternatives :items="r.data.value.alternatives" audience="doctor" :acting="r.acting.value" :action-label="t('route.referHere')" @act="redirect($event)" />
            <div class="row current-row">
              <div class="row-main" :title="r.data.value.organization.moName">{{ shortOrgName(r.data.value.organization.moName) }} · {{ t('route.current') }}</div>
              <div class="row-value muted">{{ days(r.data.value.forecast.p50Days) }} / {{ days(r.data.value.forecast.p90Days) }} {{ t('common.days') }}</div>
            </div>
          </AppCard>

          <CollapsibleSection :title="t('route.checklist')" :summary="t('route.checklistSummary', { expired: r.expired.value, valid: r.valid.value })" :tone="r.expired.value ? 'danger' : undefined" origin="formula">
            <RouteChecklist :items="r.data.value.checklist" :standard="r.data.value.standard" />
          </CollapsibleSection>
        </div>
      </div>

      <div class="grid cols-2">
        <AppCard :title="t('route.signalsTitle')"><RouteFeed :entries="r.entries.value" audience="doctor" /></AppCard>
        <AppCard :title="t('route.pastReferrals')"><RouteHistory :items="r.data.value.history" /></AppCard>
      </div>

      <div class="sticky-actions">
        <InputText v-model="reason" :placeholder="t('route.reason')" class="reason-inline" data-testid="redirect-reason" />
        <label class="severe-check"><Checkbox v-model="severe" binary input-id="severe" data-testid="redirect-severe" /> <span>{{ t('route.severeCheckbox') }}</span></label>
        <RouterLink :to="{ name: 'referral', query: { moCode: r.data.value.organization.moCode, profileCode: r.data.value.organization.profileCode } }">
          <Button :label="t('route.openReferral')" />
        </RouterLink>
        <Button :label="t('route.keepCurrent')" severity="secondary" :loading="r.acting.value === 'keep'" :disabled="r.acting.value !== null" data-testid="keep" @click="keep()" />
        <Button v-if="r.openSig.value && r.requestedAlternative.value" :label="t('route.referHere')" severity="secondary" :loading="r.acting.value === r.requestedAlternative.value.mo.moCode" :disabled="r.acting.value !== null" @click="redirect(r.requestedAlternative.value.mo.moCode)" />
        <span class="spacer" />
        <RouterLink class="link-arrow small" :to="{ name: 'scribe' }">{{ t('route.scribeLink') }}</RouterLink>
      </div>
      <p class="caption">{{ r.data.value.basis }} · {{ t('route.synthetic', { asOf: dateShort(r.data.value.asOf) }) }}</p>
    </template>
  </PageShell>
</template>

<style scoped>
.progress { padding-top: 4px; }
.main-grid { display: grid; grid-template-columns: minmax(0, 1.2fr) minmax(0, 1fr); gap: var(--dm-space-4); align-items: start; }
.col { display: flex; flex-direction: column; gap: var(--dm-space-4); min-width: 0; }
.org-line { font-size: var(--dm-text-lg); font-weight: 500; letter-spacing: -0.01em; display: flex; align-items: baseline; gap: 8px; }
.hero-line { margin: 10px 0 2px; }
.hero-line :deep(.hero-label) { display: none; }
.facts-line { display: flex; align-items: center; gap: 12px; flex-wrap: wrap; font-size: var(--dm-text-base); padding-bottom: 8px; }
.facts-line .ink { color: var(--dm-ink); font-weight: 500; }
.next-step { border-top: 1px solid var(--dm-hairline); padding-top: 12px; margin-top: 4px; }
.next-text { font-size: var(--dm-text-base); font-weight: 500; margin-top: 4px; }
.why-title { padding: 12px 0 4px; border-top: 1px solid var(--dm-hairline); margin-top: 12px; }
.signal-banner { background: var(--dm-accent-soft); display: flex; align-items: center; gap: 12px; padding: 16px 24px; }
.signal-banner i { font-size: 1.3rem; }
.signal-text { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
.signal-title { font-size: var(--dm-text-md); font-weight: 500; }
.current-row { color: var(--dm-muted); border-top: 1px solid var(--dm-hairline); }
.sticky-actions { gap: 12px; }
.reason-inline { flex: 1 1 280px; }
.severe-check { display: flex; align-items: center; gap: 8px; white-space: nowrap; }
.spacer { flex: 1; }
@media (max-width: 900px) { .main-grid { grid-template-columns: 1fr; } }
</style>
