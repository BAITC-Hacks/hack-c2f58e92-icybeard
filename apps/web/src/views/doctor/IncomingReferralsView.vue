<script setup lang="ts">
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import IconField from 'primevue/iconfield'
import InputIcon from 'primevue/inputicon'
import InputText from 'primevue/inputtext'
import Select from 'primevue/select'
import Textarea from 'primevue/textarea'
import { computed, onMounted, ref } from 'vue'
import { useToast } from 'primevue/usetoast'
import { useI18n } from 'vue-i18n'
import type { IncomingReferral, OrganizationItem } from '@/api/types'
import AsyncState from '@/components/states/AsyncState.vue'
import AppCard from '@/components/ui/AppCard.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import PageShell from '@/components/ui/PageShell.vue'
import SearchSelect from '@/components/ui/SearchSelect.vue'
import StatusTag from '@/components/ui/StatusTag.vue'
import { useIncomingReferrals } from '@/composables/useIncomingReferrals'
import { useLocaleFormat } from '@/composables/useLocaleFormat'
import { shortOrgName } from '@/lib/format'
import { addDays, almatyToday, dateShort } from '@/lib/route'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'

/** Входящие направления (W-Incoming): переводы из других больниц в свою. Порядок: пациент соглашается → больница
 * подтверждает приём и назначает дату (до 30 дней) или отказывает с причиной → в день госпитализации отмечает приём
 * или неявку (дату можно перенести) → выписывает с эпикризом. Кнопки — только из item.allowed. */
const { t } = useI18n()
const { dateTime } = useLocaleFormat()
const toast = useToast()
const refdata = useRefdataStore()
const auth = useAuthStore()
const r = useIncomingReferrals()
/** У врача и администратора организации больница своя (mo_code); администратор системы и регулятор выбирают её из списка. */
const ownOrg = computed(() => !!auth.moCode)
const organizations = ref<OrganizationItem[]>([])
const orgLabel = (o: OrganizationItem) => `${shortOrgName(o.name)} · ${refdata.regionName(o.regionKato)}`
const orgTitle = (o: OrganizationItem) => `${o.name} · ${o.moCode}`

type Mode = 'confirm' | 'reject' | 'reschedule' | 'discharge'
const CONSENT_TONES: Record<string, 'ok' | 'neutral' | 'accent' | 'warn'> = { accepted: 'ok', declined: 'neutral', pending: 'warn' }
const severeCount = computed(() => r.items.value.filter((i) => i.severe).length)
const today = almatyToday()
const maxDate = addDays(today, 30)

const dialog = ref<{ mode: Mode; item: IncomingReferral } | null>(null)
const plannedAt = ref(today)
const text = ref('')
const needsDate = computed(() => dialog.value?.mode === 'confirm' || dialog.value?.mode === 'reschedule')
const needsText = computed(() => dialog.value !== null && dialog.value.mode !== 'confirm')
const dateValid = computed(() => !needsDate.value || (plannedAt.value >= today && plannedAt.value <= maxDate))
const canSubmit = computed(() => dateValid.value && (!needsText.value || text.value.trim().length > 0))
const TITLES: Record<Mode, string> = { confirm: 'confirmTitle', reject: 'rejectTitle', reschedule: 'rescheduleTitle', discharge: 'dischargeTitle' }
const TEXT_LABELS: Record<Mode, string> = { confirm: 'comment', reject: 'rejectReason', reschedule: 'rescheduleReason', discharge: 'dischargeSummary' }

function open(mode: Mode, item: IncomingReferral) {
  dialog.value = { mode, item }
  plannedAt.value = mode === 'reschedule' && item.plannedAt ? item.plannedAt : today
  text.value = ''
}

async function submit() {
  if (!dialog.value || !canSubmit.value) return
  const { mode, item } = dialog.value
  const ok = mode === 'confirm' ? await r.confirm(item, plannedAt.value, text.value)
    : mode === 'reject' ? await r.reject(item, text.value)
      : mode === 'reschedule' ? await r.reschedule(item, plannedAt.value, text.value)
        : await r.discharge(item, text.value)
  if (ok) {
    const done = { confirm: 'confirmed', reject: 'rejected', reschedule: 'rescheduled', discharge: 'discharged' }[mode]
    toast.add({ severity: 'success', summary: t('doctor.incoming.' + done), life: 4000 })
    dialog.value = null
  }
}

async function admit(item: IncomingReferral) {
  if (await r.admit(item)) toast.add({ severity: 'success', summary: t('doctor.incoming.admitted'), life: 4000 })
}
async function noShow(item: IncomingReferral) {
  if (await r.noShow(item)) toast.add({ severity: 'success', summary: t('doctor.incoming.noShowDone'), life: 4000 })
}

// фильтры и поиск — на странице, по уже загруженному списку; по умолчанию показано всё
type Stage = 'all' | 'consent' | 'confirm' | 'scheduled' | 'admitted' | 'closed'
const stage = ref<Stage>('all')
const severity = ref<'all' | 'severe'>('all')
const search = ref('')
function stageOf(i: IncomingReferral): Exclude<Stage, 'all'> {
  if (i.discharged || i.closedReason || i.status === 'closed') return 'closed'
  if (i.admitted || i.status === 'admitted') return 'admitted'
  if (i.confirmed) return 'scheduled'
  return i.patientConsent === 'accepted' ? 'confirm' : 'consent'
}
const countBy = (s: Exclude<Stage, 'all'>) => r.items.value.filter((i) => stageOf(i) === s).length
const stageOptions = computed(() => [
  { value: 'all' as const, label: `${t('doctor.incoming.stage.all')} · ${r.items.value.length}` },
  ...(['consent', 'confirm', 'scheduled', 'admitted', 'closed'] as const).map((s) => ({ value: s, label: `${t('doctor.incoming.stage.' + s)} · ${countBy(s)}` })),
])
const severityOptions = computed(() => [
  { value: 'all' as const, label: t('doctor.incoming.severityAll') },
  { value: 'severe' as const, label: `${t('doctor.incoming.severeOnly')} · ${severeCount.value}` },
])
const visible = computed(() => {
  const q = search.value.trim().toLowerCase()
  return r.items.value.filter((i) => (stage.value === 'all' || stageOf(i) === stage.value) && (severity.value === 'all' || i.severe)
    && (!q || [i.patientRef, i.fromMoName, i.fromMoCode, refdata.profileName(i.profileCode)].join(' ').toLowerCase().includes(q)))
})
const filtered = computed(() => stage.value !== 'all' || severity.value !== 'all' || !!search.value.trim())
function resetFilters() {
  stage.value = 'all'
  severity.value = 'all'
  search.value = ''
}

async function pickOrg(code: string | null) {
  r.moCode.value = code
  if (code) await r.load()
  else r.items.value = []
}

onMounted(async () => {
  await refdata.load()
  if (ownOrg.value) await r.load()
  else organizations.value = await refdata.allOrganizations().catch(() => [])
})
</script>

<template>
  <PageShell :title="t('doctor.incoming.title')">
    <template #subtitle>{{ ownOrg ? t('doctor.incoming.subtitle') : t('doctor.incoming.subtitlePick') }}<template v-if="ownOrg || r.moCode.value"> · {{ t('doctor.incoming.total', { n: r.items.value.length }) }}</template></template>
    <template v-if="!ownOrg" #actions>
      <SearchSelect :model-value="r.moCode.value" :options="organizations" :option-label="orgLabel" option-value="moCode" :option-title="orgTitle" :placeholder="t('doctor.incoming.pickOrg')" class="org-pick" data-testid="incoming-org" @update:model-value="pickOrg" />
    </template>
    <AppCard v-if="!ownOrg && !r.moCode.value">
      <EmptyState :title="t('doctor.incoming.noOrgTitle')" :text="t('doctor.incoming.noOrgText')" icon="pi pi-building" />
    </AppCard>
    <AppCard v-else>
      <div class="toolbar list-toolbar">
        <span class="caption">{{ t('doctor.worklist.shown', { shown: visible.length, total: r.items.value.length }) }}</span>
        <span class="spacer" />
        <Select v-model="stage" :options="stageOptions" option-label="label" option-value="value" class="f-select" :aria-label="t('doctor.incoming.colStatus')" data-testid="filter-stage" />
        <Select v-model="severity" :options="severityOptions" option-label="label" option-value="value" class="f-select" :aria-label="t('doctor.incoming.severeOnly')" data-testid="filter-severe" />
        <IconField class="search-field">
          <InputIcon class="pi pi-search" />
          <InputText v-model="search" :placeholder="t('doctor.incoming.search')" :aria-label="t('doctor.incoming.search')" data-testid="incoming-search" />
        </IconField>
        <Button icon="pi pi-refresh" size="small" severity="secondary" text rounded :aria-label="t('doctor.incoming.refresh')" :title="t('doctor.incoming.refresh')" :loading="r.loading.value" @click="r.load" />
      </div>
      <AsyncState :loading="r.loading.value" :error="r.error.value" :empty="visible.length === 0" :filtered="r.items.value.length > 0 && filtered" @reset="resetFilters" :lines="6"
        :empty-title="t('doctor.incoming.empty')" :empty-text="t('doctor.incoming.emptyText')" empty-icon="pi pi-inbox" @retry="r.load">
        <div class="table-wrap">
          <table class="dense-table" data-testid="incoming-table">
            <thead>
              <tr>
                <th>{{ t('doctor.incoming.colPatient') }}</th><th>{{ t('doctor.incoming.colFrom') }}</th><th>{{ t('doctor.incoming.colWhen') }}</th>
                <th>{{ t('doctor.incoming.colConsent') }}</th><th>{{ t('doctor.incoming.colStatus') }}</th><th>{{ t('doctor.incoming.colAction') }}</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="i in visible" :key="i.decisionId" :data-status="i.status ?? ''">
                <td>
                  <RouterLink v-if="i.confirmed" class="mono strong" :to="{ name: 'patient-route', params: { patientRef: i.patientRef } }">{{ i.patientRef }}</RouterLink>
                  <span v-else class="mono strong">{{ i.patientRef }}</span>
                  <div class="caption">{{ refdata.profileName(i.profileCode) }}<template v-if="i.severe"> · <span class="severe">{{ t('route.severeFlag') }}</span></template></div>
                </td>
                <td :title="i.fromMoName">{{ shortOrgName(i.fromMoName) }}<div class="caption">{{ i.fromMoCode }}</div></td>
                <td class="nowrap muted">{{ dateTime(i.recordedAt) }}</td>
                <td><StatusTag :value="t('route.consentStatus.' + i.patientConsent)" :tone="CONSENT_TONES[i.patientConsent]" /></td>
                <td>
                  <span v-if="i.status">{{ t('route.progress.status.' + i.status) }}</span>
                  <div v-if="i.plannedAt" class="caption">{{ t('doctor.incoming.colDate') }}: <span class="tabular">{{ dateShort(i.plannedAt) }}</span></div>
                  <StatusTag v-if="i.overdue" :value="t('doctor.incoming.overdue')" tone="danger" />
                  <div v-if="i.closedReason" class="caption">{{ t('route.progress.closed.' + i.closedReason) }}</div>
                </td>
                <td>
                  <div class="actions">
                    <Button v-if="i.allowed.includes('confirm')" :label="t('doctor.incoming.confirm')" size="small" class="cell-btn" :disabled="r.acting.value !== null"
                      data-testid="confirm-referral" @click="open('confirm', i)" />
                    <Button v-if="i.allowed.includes('reject')" :label="t('doctor.incoming.reject')" size="small" severity="secondary" class="cell-btn" :disabled="r.acting.value !== null"
                      data-testid="reject-referral" @click="open('reject', i)" />
                    <Button v-if="i.allowed.includes('admit')" :label="t('doctor.incoming.admit')" size="small" class="cell-btn" :disabled="r.acting.value !== null"
                      :loading="r.acting.value === i.decisionId" data-testid="admit-referral" @click="admit(i)" />
                    <Button v-if="i.allowed.includes('discharge')" :label="t('doctor.incoming.discharge')" size="small" class="cell-btn" :severity="i.allowed.includes('admit') ? 'secondary' : undefined"
                      :disabled="r.acting.value !== null" data-testid="discharge-referral" @click="open('discharge', i)" />
                    <Button v-if="i.allowed.includes('reschedule')" :label="t('doctor.incoming.reschedule')" size="small" severity="secondary" class="cell-btn" :disabled="r.acting.value !== null"
                      data-testid="reschedule-referral" @click="open('reschedule', i)" />
                    <Button v-if="i.allowed.includes('no_show')" :label="t('doctor.incoming.noShow')" size="small" severity="secondary" class="cell-btn" :disabled="r.acting.value !== null"
                      data-testid="no-show-referral" @click="noShow(i)" />
                    <span v-if="i.discharged" class="cell-pill done"><i class="pi pi-check" aria-hidden="true" /> {{ t('doctor.incoming.alreadyDischarged') }}</span>
                    <span v-else-if="!i.allowed.length" class="caption">{{ t('doctor.incoming.noActions') }}</span>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </AsyncState>
      <p class="caption" style="margin: 12px 0 0">{{ t('doctor.incoming.note') }}</p>
    </AppCard>
    <Dialog :visible="dialog !== null" modal :header="dialog ? t('doctor.incoming.' + TITLES[dialog.mode]) : ''" :style="{ width: 'min(520px, 94vw)' }"
      @update:visible="(v: boolean) => !v && (dialog = null)">
      <div v-if="dialog" class="dialog-body">
        <p class="muted small">{{ dialog.item.patientRef }} · {{ shortOrgName(dialog.item.fromMoName) }}</p>
        <div v-if="needsDate" class="field">
          <label for="planned-at">{{ t('doctor.incoming.plannedAt') }}</label>
          <input id="planned-at" v-model="plannedAt" type="date" class="p-inputtext date-input" :min="today" :max="maxDate" data-testid="planned-at" />
          <small class="caption">{{ t('doctor.incoming.plannedHint') }}</small>
        </div>
        <div class="field">
          <label for="dialog-text">{{ t('doctor.incoming.' + TEXT_LABELS[dialog.mode]) }}</label>
          <Textarea id="dialog-text" v-model="text" rows="3" auto-resize
            :placeholder="dialog.mode === 'discharge' ? t('doctor.incoming.dischargeSummaryPlaceholder') : ''" style="width: 100%" data-testid="dialog-text" />
        </div>
      </div>
      <template #footer>
        <Button :label="t('common.cancel')" severity="secondary" @click="dialog = null" />
        <Button :label="dialog ? t('doctor.incoming.' + (dialog.mode === 'confirm' ? 'confirm' : dialog.mode)) : ''" :disabled="!canSubmit"
          :loading="r.acting.value === dialog?.item.decisionId" :data-testid="dialog?.mode === 'discharge' ? 'confirm-discharge' : 'dialog-submit'" @click="submit" />
      </template>
    </Dialog>
  </PageShell>
</template>

<style scoped>
.list-toolbar { margin-bottom: var(--gap-cabinet, 16px); row-gap: 8px; }
.f-select { min-width: 220px; }
.org-pick { min-width: 340px; }
.search-field { flex: 0 1 340px; min-width: 260px; }
.search-field :deep(.p-inputtext) { width: 100%; }
@media (max-width: 900px) { .f-select, .search-field { flex: 1 1 100%; } }
.strong { font-weight: var(--fw-bold); }
.nowrap { white-space: nowrap; }
.severe { color: var(--danger-text); font-weight: var(--fw-semibold); }
.actions { display: flex; flex-wrap: wrap; gap: 6px; align-items: center; }
.cell-pill { display: inline-flex; align-items: center; justify-content: center; gap: 5px; height: 30px; border-radius: var(--radius-pill); font-size: var(--fs-sm); font-weight: var(--fw-bold); box-sizing: border-box; white-space: nowrap; padding: 0 12px; }
.cell-pill.done { background: var(--success-bg); color: var(--success-text); }
.cell-pill.done i { font-size: 11px; }
:deep(.cell-btn.p-button) { min-width: 120px; height: 30px; min-height: 30px; padding: 0 10px; font-size: var(--fs-sm); justify-content: center; }
.dialog-body { display: flex; flex-direction: column; gap: 14px; }
.dialog-body .muted { margin: 0; }
.field { display: flex; flex-direction: column; gap: 6px; }
.date-input { max-width: 200px; }
</style>
