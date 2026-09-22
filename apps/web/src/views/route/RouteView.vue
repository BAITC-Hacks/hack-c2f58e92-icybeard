<script setup lang="ts">
import Button from 'primevue/button'
import Tag from 'primevue/tag'
import Textarea from 'primevue/textarea'
import Timeline from 'primevue/timeline'
import { useToast } from 'primevue/usetoast'
import { computed, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { ApiError } from '@/api/client'
import { route as routeApi } from '@/api/endpoints'
import type { PatientRoute } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import OriginTag from '@/components/OriginTag.vue'
import { days, pct, refusalWords } from '@/lib/format'
import { checklistTone, dateShort, outcomeTone, stageTone } from '@/lib/route'

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
  <main class="page">
    <h1>
      {{ patientRef ? t('route.patientTitle') : t('route.myTitle') }}
      <span v-if="patientRef" class="muted mono">{{ patientRef }}</span>
    </h1>
    <p v-if="data" class="lead synthetic">{{ t('route.synthetic', { asOf: dateShort(data.asOf) }) }}</p>
    <ErrorBox :error="error" />
    <p v-if="notFound" class="muted">{{ t('route.notFound') }} — <RouterLink to="/wait">{{ t('nav.wait') }}</RouterLink></p>
    <p v-else-if="busy && !data" class="muted">{{ t('common.loading') }}</p>

    <template v-if="data">
      <div class="card">
        <h2>{{ data.organization.profileName }}</h2>
        <p class="muted">{{ data.organization.moName }}</p>
        <p>
          <Tag :value="t('route.stage.' + data.stage)" :severity="stageTone(data.stage)" data-testid="route-stage" />
          <span class="muted"> {{ t('route.since', { date: dateShort(data.dates.registeredAt), days: data.daysWaiting }) }}</span>
        </p>
        <p v-if="expired" class="muted">{{ t('route.expiredCount', { count: expired }) }}</p>
      </div>

      <div v-if="data.doctor" class="card" style="margin-top: 16px" data-testid="doctor-panel">
        <h2>{{ t('route.doctorPanel') }} <OriginTag kind="ml" /></h2>
        <p>
          {{ t('route.priority') }}: <b>{{ data.doctor.priority }}</b>
          <Tag v-for="f in data.doctor.riskFlags" :key="f" :value="t('route.flags.' + f)" severity="warn" style="margin-left: 6px" />
        </p>
        <p>{{ t('route.nextAction') }}: {{ data.doctor.nextAction }}</p>
        <p class="muted">{{ data.doctor.explanation }}</p>
        <RouterLink :to="{ name: 'referral', query: { moCode: data.organization.moCode, profileCode: data.organization.profileCode } }">
          {{ t('route.referralAssistant') }}
        </RouterLink>
      </div>

      <div class="grid cols-2" style="margin-top: 16px">
        <div class="card">
          <h2>{{ t('route.forecast') }} <OriginTag :kind="data.forecast.fromModel ? 'ml' : 'formula'" /></h2>
          <div class="kpi">
            <div class="item"><div class="value">{{ days(data.forecast.p50Days) }}</div><div class="label">{{ t('route.p50') }}</div></div>
            <div class="item"><div class="value">{{ days(data.forecast.p90Days) }}</div><div class="label">{{ t('route.p90') }}</div></div>
            <div v-if="data.doctor" class="item">
              <div class="value">{{ data.doctor.refusalOrgInTraining ? pct(data.doctor.pRefusal) : refusalWords(data.doctor.pRefusal) }}</div>
              <div class="label">{{ t('route.refusal') }}</div>
            </div>
            <div v-else class="item"><div class="value">{{ pct(data.forecast.pWithin30Days) }}</div><div class="label">{{ t('route.within30') }}</div></div>
          </div>
          <p v-if="target" class="muted" style="margin-top: 8px">
            {{ t('route.benchmark', { days: days(target.value), source: target.source }) }} <OriginTag kind="formula" />
          </p>
        </div>
        <div class="card">
          <h2>{{ t('route.checklist') }} <OriginTag kind="formula" /></h2>
          <div v-for="c in data.checklist" :key="c.code" class="factor">
            <span>{{ c.title }} <span class="muted">· {{ c.validityLabel }}</span></span>
            <span class="contribution">
              <span class="muted">{{ t('route.validUntil', { date: dateShort(c.validUntil) }) }}</span>
              <Tag :value="t('route.status.' + c.status)" :severity="checklistTone(c.status)" style="margin-left: 6px" />
            </span>
          </div>
          <p class="muted" style="margin-top: 8px">{{ t('route.checklistNote', { source: data.standard.source, date: dateShort(data.standard.sourceDate) }) }}</p>
        </div>
      </div>

      <div class="card" style="margin-top: 16px">
        <h2>{{ t('route.stages') }} <OriginTag kind="formula" /></h2>
        <Timeline :value="data.timeline" class="route-timeline">
          <template #marker="{ item }"><span class="marker" :class="item.status" /></template>
          <template #content="{ item }">
            <div :class="['stage', item.status]">{{ item.title }}</div>
            <div class="muted">{{ item.date ? dateShort(item.date) : (item.norm ?? '') }}</div>
          </template>
        </Timeline>
        <p class="muted">{{ t('route.stagesSource') }}</p>
      </div>

      <div class="card" style="margin-top: 16px">
        <h2>{{ t('route.whereFaster') }} <OriginTag v-if="data.alternativesModel" kind="ml" /></h2>
        <p v-if="data.alternatives.length === 0" class="muted">{{ t('doctor.referral.noAlternatives') }}</p>
        <table v-else style="width: 100%; border-collapse: collapse">
          <thead>
            <tr class="muted" style="text-align: left">
              <th>{{ t('common.organization') }}</th><th>p50, {{ t('common.days') }}</th><th>p90, {{ t('common.days') }}</th>
              <th v-if="isDoctor">{{ t('doctor.referral.refusalShort') }}</th><th v-if="isDoctor"></th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="a in data.alternatives" :key="a.mo.moCode" style="border-top: 1px solid var(--darumen-border)">
              <td style="padding: 8px 4px">{{ a.mo.name }} <span class="muted">({{ a.mo.moCode }})</span></td>
              <td>{{ days(a.p50Days) }}</td>
              <td>{{ days(a.p90Days) }}</td>
              <td v-if="isDoctor">{{ pct(a.pRefusal) }}</td>
              <td v-if="isDoctor">
                <Button :label="t('route.referHere')" size="small" severity="secondary" :loading="redirecting === a.mo.moCode" :disabled="redirecting !== null" data-testid="redirect" @click="redirect(a.mo.moCode)" />
              </td>
            </tr>
          </tbody>
        </table>
        <div v-if="isDoctor" class="field" style="margin-top: 12px">
          <label>{{ t('route.reason') }}</label>
          <Textarea v-model="reason" rows="2" auto-resize data-testid="redirect-reason" />
        </div>
        <p v-else class="muted" style="margin-top: 8px">{{ t('route.doctorOnly') }}</p>
      </div>

      <div class="grid cols-2" style="margin-top: 16px">
        <div class="card" data-testid="route-decisions">
          <h2>{{ t('route.decisions') }}</h2>
          <p v-if="data.decisions.length === 0" class="muted">{{ t('route.noDecisions') }}</p>
          <div v-for="d in data.decisions" :key="d.decisionId" class="decision">
            <div>{{ d.kind === 'redirect' ? t('route.redirect', { name: d.toMoName }) : t('route.keep') }}</div>
            <div class="muted">{{ dateShort(d.recordedAt) }} · {{ t('decision.role.' + d.role) }}<template v-if="d.reason"> · {{ d.reason }}</template></div>
          </div>
        </div>
        <div class="card">
          <h2>{{ t('route.history') }}</h2>
          <div v-for="h in data.history" :key="h.registeredAt + h.moCode" class="factor">
            <span>{{ dateShort(h.registeredAt) }} · {{ h.profileName }} <span class="muted">· {{ h.moName }}</span></span>
            <span class="contribution">
              <Tag :value="t('route.outcome.' + h.outcome)" :severity="outcomeTone(h.outcome)" />
              <span class="muted"> {{ t('route.waited', { days: h.waitDays }) }}</span>
            </span>
          </div>
        </div>
      </div>
      <p class="muted" style="margin-top: 16px">{{ data.basis }}</p>
    </template>
  </main>
</template>

<style scoped>
.mono { font-family: 'IBM Plex Mono', ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 0.9em; font-weight: 400; }
.marker { display: inline-block; width: 14px; height: 14px; border-radius: 50%; border: 2px solid var(--darumen-accent); background: #fff; }
.marker.done { background: var(--darumen-accent); }
.marker.current { background: #fff; box-shadow: 0 0 0 3px #e6f4f6; }
.marker.upcoming { border-color: var(--darumen-border); }
.stage.current { font-weight: 600; }
.stage.upcoming { color: var(--darumen-muted); }
.decision { padding: 6px 0; border-bottom: 1px dashed var(--darumen-border); }
.route-timeline :deep(.p-timeline-event-opposite) { display: none; }
</style>
