<script setup lang="ts">
import Button from 'primevue/button'
import Textarea from 'primevue/textarea'
import Timeline from 'primevue/timeline'
import { useToast } from 'primevue/usetoast'
import { computed, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { ApiError } from '@/api/client'
import { route as routeApi } from '@/api/endpoints'
import type { PatientRoute, SignalKind } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import OriginTag from '@/components/OriginTag.vue'
import AppCard from '@/components/ui/AppCard.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import KpiRow from '@/components/ui/KpiRow.vue'
import KpiTile from '@/components/ui/KpiTile.vue'
import PageShell from '@/components/ui/PageShell.vue'
import Section from '@/components/ui/Section.vue'
import Skeleton from '@/components/ui/Skeleton.vue'
import StatusTag from '@/components/ui/StatusTag.vue'
import { days, pct, refusalWords } from '@/lib/format'
import { checklistTone, dateShort, nextActionKey, openRequest, openSignal, outcomeTone, routeEntries, stageTone, type Tone } from '@/lib/route'

/** Один экран для двух ролей: без patientRef — «Мой путь» гражданина (/route/me), с ним — маршрут пациента для врача
 * (/route/{ref}) с панелью врача и перенаправлением. Числа — только из API, каждое с меткой происхождения. */
const props = defineProps<{ patientRef?: string }>()
const { t } = useI18n()
const toast = useToast()
const data = ref<PatientRoute | null>(null)
const error = ref<unknown>(null)
const notFound = ref(false)
const busy = ref(false)
const reason = ref('')
const redirecting = ref<string | null>(null)
// один ключ идемпотентности на загруженный маршрут: повторный клик не создаёт вторую запись в журнале
let redirectKey = ''

const isDoctor = computed(() => data.value?.doctor !== null && data.value?.doctor !== undefined)
const target = computed(() => data.value?.benchmarks.find((b) => b.code === 'moh_target_wait_days') ?? null)
const expired = computed(() => data.value?.checklist.filter((c) => c.status === 'expired').length ?? 0)
// двусторонний маршрут: сигналы гражданина (валидация листа ожидания, просьба «быстрее») и ответы врача
const requestComment = ref('')
const signalling = ref<string | null>(null)
const openSig = computed(() => (data.value ? openSignal(data.value) : null))
const pendingRequest = computed(() => (data.value ? openRequest(data.value) : null))
const entries = computed(() => (data.value ? routeEntries(data.value) : []))
const requestedAlternative = computed(() => data.value?.alternatives.find((a) => a.mo.moCode === openSig.value?.toMoCode) ?? null)

async function signal(kind: SignalKind, toMoCode?: string) {
  signalling.value = toMoCode ?? kind
  try {
    await routeApi.signal({ kind, toMoCode, comment: requestComment.value.trim() || undefined }, crypto.randomUUID())
    toast.add({ severity: 'success', summary: t(toMoCode ? 'route.requestSent' : 'route.signalSent'), life: 4000 })
    requestComment.value = ''
    await load()
  } catch (e) {
    error.value = e
  } finally {
    signalling.value = null
  }
}

async function keep() {
  if (!props.patientRef) return
  if (!reason.value.trim()) {
    toast.add({ severity: 'warn', summary: t('route.reasonRequired'), life: 3000 })
    return
  }
  redirecting.value = 'keep'
  try {
    await routeApi.keep(props.patientRef, { reason: reason.value.trim() }, redirectKey)
    toast.add({ severity: 'success', summary: t('route.keepDone'), life: 4000 })
    reason.value = ''
    await load()
  } catch (e) {
    error.value = e
  } finally {
    redirecting.value = null
  }
}
// тон PrimeVue-подобных помощников lib/route → тон StatusTag
const STATUS_TONES = { success: 'ok', warn: 'warn', danger: 'danger', info: 'accent', secondary: 'neutral' } as const satisfies Record<Tone, string>
const tone = (severity: Tone): (typeof STATUS_TONES)[Tone] => STATUS_TONES[severity]

async function load() {
  busy.value = true
  error.value = null
  notFound.value = false
  try {
    data.value = props.patientRef ? await routeApi.patient(props.patientRef) : await routeApi.me()
    redirectKey = crypto.randomUUID()
  } catch (e) {
    if (e instanceof ApiError && e.status === 404) notFound.value = true
    else error.value = e
  } finally {
    busy.value = false
  }
}

async function redirect(toMoCode: string) {
  if (!props.patientRef) return
  if (!reason.value.trim()) {
    toast.add({ severity: 'warn', summary: t('route.reasonRequired'), life: 3000 })
    return
  }
  redirecting.value = toMoCode
  try {
    await routeApi.redirect(props.patientRef, { toMoCode, reason: reason.value.trim() }, redirectKey)
    toast.add({ severity: 'success', summary: t('route.redirected'), life: 4000 })
    reason.value = ''
    await load()
  } catch (e) {
    error.value = e
  } finally {
    redirecting.value = null
  }
}

onMounted(load)
watch(() => props.patientRef, load)
</script>

<template>
  <PageShell :title="patientRef ? t('route.patientTitle') : t('route.myTitle')" :synthetic="data ? t('route.synthetic', { asOf: dateShort(data.asOf) }) : undefined">
    <template v-if="patientRef" #title-extra> <span class="muted mono">{{ patientRef }}</span></template>
    <ErrorBox :error="error" />
    <EmptyState v-if="notFound" :title="t('route.notFound')" icon="pi pi-map">
      <RouterLink to="/wait">{{ t('nav.wait') }}</RouterLink>
    </EmptyState>
    <template v-else-if="busy && !data">
      <AppCard><Skeleton :lines="3" /></AppCard>
      <Section :cols="2"><AppCard><Skeleton kind="kpi" /></AppCard><AppCard><Skeleton :lines="6" /></AppCard></Section>
    </template>

    <template v-if="data">
      <AppCard :title="data.organization.profileName">
        <p class="muted">{{ data.organization.moName }}</p>
        <p>
          <StatusTag :value="t('route.stage.' + data.stage)" :tone="tone(stageTone(data.stage))" data-testid="route-stage" />
          <span class="muted"> {{ t('route.since', { date: dateShort(data.dates.registeredAt), days: data.daysWaiting }) }}</span>
        </p>
        <p v-if="expired" class="muted">{{ t('route.expiredCount', { count: expired }) }}</p>
      </AppCard>

      <AppCard v-if="!isDoctor && data.validationDue" :title="t('route.validationTitle')" data-testid="validation-card">
        <p class="muted">{{ t('route.validationBody') }}</p>
        <div class="actions">
          <Button :label="t('route.validationStill')" :loading="signalling === 'still_waiting'" :disabled="signalling !== null" data-testid="still-waiting" @click="signal('still_waiting')" />
          <Button :label="t('route.validationTreated')" severity="secondary" :loading="signalling === 'treated_elsewhere'" :disabled="signalling !== null" @click="signal('treated_elsewhere')" />
          <Button :label="t('route.validationWithdraw')" severity="secondary" text :loading="signalling === 'withdraw'" :disabled="signalling !== null" @click="signal('withdraw')" />
        </div>
      </AppCard>

      <AppCard v-if="isDoctor && openSig" :title="t('route.patientSignal.' + openSig.kind, { name: openSig.toMoName ?? '' })" data-testid="signal-banner">
        <p class="muted">{{ dateShort(openSig.recordedAt) }}<template v-if="openSig.comment"> · «{{ openSig.comment }}»</template></p>
        <div class="actions">
          <Button v-if="requestedAlternative" :label="t('route.referHere')" :loading="redirecting === requestedAlternative.mo.moCode" :disabled="redirecting !== null" @click="redirect(requestedAlternative.mo.moCode)" />
          <Button :label="t('route.keepHere')" severity="secondary" :loading="redirecting === 'keep'" :disabled="redirecting !== null" data-testid="keep" @click="keep()" />
        </div>
        <p class="muted" style="margin-top: 8px">{{ t('route.reasonBelow') }}</p>
      </AppCard>

      <Section v-if="data.doctor" :cols="1">
        <AppCard :title="t('route.doctorPanel')" origin="ml" data-testid="doctor-panel">
          <p>
            {{ t('route.priority') }}: <b class="tabular">{{ data.doctor.priority }}</b>
            <StatusTag v-for="f in data.doctor.riskFlags" :key="f" :value="t('route.flags.' + f)" tone="warn" style="margin-left: 6px" />
          </p>
          <p>{{ t('route.nextAction') }}: {{ nextActionKey(data.doctor.nextActionCode) ? t(nextActionKey(data.doctor.nextActionCode)!) : data.doctor.nextAction }}</p>
          <p class="muted">{{ data.doctor.explanation }}</p>
          <RouterLink :to="{ name: 'referral', query: { moCode: data.organization.moCode, profileCode: data.organization.profileCode } }">
            {{ t('route.referralAssistant') }}
          </RouterLink>
        </AppCard>
      </Section>

      <Section :cols="2">
        <AppCard :title="t('route.forecast')" :origin="data.forecast.fromModel ? 'ml' : 'formula'">
          <KpiRow>
            <KpiTile :value="days(data.forecast.p50Days)" :label="t('route.p50')" />
            <KpiTile :value="days(data.forecast.p90Days)" :label="t('route.p90')" />
            <KpiTile v-if="data.doctor" :value="data.doctor.refusalOrgInTraining ? pct(data.doctor.pRefusal) : refusalWords(data.doctor.pRefusal)" :label="t('route.refusal')" />
            <KpiTile v-else :value="pct(data.forecast.pWithin30Days)" :label="t('route.within30')" />
          </KpiRow>
          <p v-if="target" class="muted" style="margin-top: 8px">
            {{ t('route.benchmark', { days: days(target.value), source: target.source }) }} <OriginTag kind="formula" />
          </p>
        </AppCard>
        <AppCard :title="t('route.checklist')" origin="formula">
          <div v-for="c in data.checklist" :key="c.code" class="factor">
            <span>{{ c.title }} <span class="muted">· {{ c.validityLabel }}</span></span>
            <span class="contribution">
              <span class="muted">{{ t('route.validUntil', { date: dateShort(c.validUntil) }) }}</span>
              <StatusTag :value="t('route.status.' + c.status)" :tone="tone(checklistTone(c.status))" style="margin-left: 6px" />
            </span>
          </div>
          <p class="muted" style="margin-top: 8px">{{ t('route.checklistNote', { source: data.standard.source, date: dateShort(data.standard.sourceDate) }) }}</p>
        </AppCard>
      </Section>

      <Section :cols="1">
        <AppCard :title="t('route.stages')" origin="formula">
          <Timeline :value="data.timeline" class="route-timeline">
            <template #marker="{ item }"><span class="marker" :class="item.status" /></template>
            <template #content="{ item }">
              <div :class="['stage', item.status]">{{ item.title }}</div>
              <div class="muted">{{ item.date ? dateShort(item.date) : (item.norm ?? '') }}</div>
            </template>
          </Timeline>
          <p class="muted">{{ t('route.stagesSource') }}</p>
        </AppCard>
      </Section>

      <Section :cols="1">
        <AppCard :title="t('route.whereFaster')" :origin="data.alternativesModel ? 'ml' : undefined">
          <p v-if="data.alternatives.length === 0" class="muted">{{ t('doctor.referral.noAlternatives') }}</p>
          <table v-else class="plain">
            <thead>
              <tr class="muted">
                <th>{{ t('common.organization') }}</th><th>p50, {{ t('common.days') }}</th><th>p90, {{ t('common.days') }}</th>
                <th v-if="isDoctor">{{ t('doctor.referral.refusalShort') }}</th><th></th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="a in data.alternatives" :key="a.mo.moCode">
                <td>{{ a.mo.name }} <span class="muted">({{ a.mo.moCode }})</span></td>
                <td class="tabular">{{ days(a.p50Days) }}</td>
                <td class="tabular">{{ days(a.p90Days) }}</td>
                <td v-if="isDoctor" class="tabular">{{ pct(a.pRefusal) }}</td>
                <td v-if="isDoctor">
                  <Button :label="t('route.referHere')" size="small" severity="secondary" :loading="redirecting === a.mo.moCode" :disabled="redirecting !== null" data-testid="redirect" @click="redirect(a.mo.moCode)" />
                </td>
                <td v-else>
                  <StatusTag v-if="pendingRequest?.toMoCode === a.mo.moCode" :value="t('route.requestPending')" tone="accent" />
                  <Button v-else :label="t('route.requestConsider')" size="small" severity="secondary" :loading="signalling === a.mo.moCode" :disabled="signalling !== null" data-testid="request" @click="signal('request_redirect', a.mo.moCode)" />
                </td>
              </tr>
            </tbody>
          </table>
          <div v-if="isDoctor" class="field" style="margin-top: 12px">
            <label>{{ t('route.reason') }}</label>
            <Textarea v-model="reason" rows="2" auto-resize data-testid="redirect-reason" />
          </div>
          <div v-else class="field" style="margin-top: 12px">
            <label>{{ t('route.requestComment') }}</label>
            <Textarea v-model="requestComment" rows="2" auto-resize data-testid="request-comment" />
          </div>
          <p v-if="!isDoctor" class="muted" style="margin-top: 8px">{{ t('route.doctorOnly') }}</p>
        </AppCard>
      </Section>

      <Section :cols="2">
        <AppCard :title="t('route.signalsTitle')" data-testid="route-decisions">
          <p v-if="entries.length === 0" class="muted">{{ t('route.noDecisions') }}</p>
          <div v-for="e in entries" :key="e.kind === 'decision' ? e.decision.decisionId : e.signal.decisionId" class="decision">
            <template v-if="e.kind === 'decision'">
              <div>{{ e.decision.kind === 'redirect' ? t('route.redirect', { name: e.decision.toMoName }) : t('route.keep') }}</div>
              <div class="muted">{{ dateShort(e.decision.recordedAt) }} · {{ t('decision.role.' + e.decision.role) }}<template v-if="e.decision.reason"> · {{ e.decision.reason }}</template></div>
            </template>
            <template v-else>
              <div>{{ t((isDoctor ? 'route.patientSignal.' : 'route.signal.') + e.signal.kind, { name: e.signal.toMoName ?? '' }) }}</div>
              <div class="muted">{{ dateShort(e.signal.recordedAt) }}<template v-if="e.signal.comment"> · {{ e.signal.comment }}</template><template v-if="e.signal.open"> · {{ t('route.awaitingDoctor') }}</template></div>
            </template>
          </div>
        </AppCard>
        <AppCard :title="t('route.history')">
          <div v-for="h in data.history" :key="h.registeredAt + h.moCode" class="factor">
            <span>{{ dateShort(h.registeredAt) }} · {{ h.profileName }} <span class="muted">· {{ h.moName }}</span></span>
            <span class="contribution">
              <StatusTag :value="t('route.outcome.' + h.outcome)" :tone="tone(outcomeTone(h.outcome))" />
              <span class="muted"> {{ t('route.waited', { days: h.waitDays }) }}</span>
            </span>
          </div>
        </AppCard>
      </Section>
      <p class="muted" style="margin-top: 16px">{{ data.basis }}</p>
    </template>
  </PageShell>
</template>

<style scoped>
.mono { font-family: 'IBM Plex Mono', ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 0.9em; font-weight: 400; }
.marker { display: inline-block; width: 14px; height: 14px; border-radius: 50%; border: 2px solid var(--dm-accent); background: var(--dm-surface); }
.marker.done { background: var(--dm-accent); }
.marker.current { box-shadow: 0 0 0 3px var(--dm-accent-soft); }
.marker.upcoming { border-color: var(--dm-hairline); }
.stage.current { font-weight: 600; }
.stage.upcoming { color: var(--dm-muted); }
.decision { padding: 6px 0; border-bottom: 1px dashed var(--dm-hairline); }
.actions { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 8px; }
.route-timeline :deep(.p-timeline-event-opposite) { display: none; }
table.plain { width: 100%; border-collapse: collapse; }
table.plain th { text-align: left; font-weight: 500; }
table.plain td { padding: 8px 4px; border-top: 1px solid var(--dm-hairline); }
</style>
