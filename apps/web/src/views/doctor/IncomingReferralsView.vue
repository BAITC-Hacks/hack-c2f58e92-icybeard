<script setup lang="ts">
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import Textarea from 'primevue/textarea'
import { computed, onMounted, ref } from 'vue'
import { useToast } from 'primevue/usetoast'
import { useI18n } from 'vue-i18n'
import type { IncomingReferral } from '@/api/types'
import AsyncState from '@/components/states/AsyncState.vue'
import AppCard from '@/components/ui/AppCard.vue'
import PageShell from '@/components/ui/PageShell.vue'
import StatusTag from '@/components/ui/StatusTag.vue'
import { useIncomingReferrals } from '@/composables/useIncomingReferrals'
import { useLocaleFormat } from '@/composables/useLocaleFormat'
import { shortOrgName } from '@/lib/format'
import { useRefdataStore } from '@/stores/refdata'

/** Входящие направления (W-Incoming, задача 4): redirect от других организаций, ещё не подтверждённые своей —
 * /route/{patientRef} для них недоступен (реф закодирован под отправителя), это отдельный, специально для приёма
 * построенный список. Подтвердить можно только когда пациент уже согласился (patientConsent === accepted).
 * Выписка/эпикриз (задача 11) — доступна только после подтверждения, диалог с текстом по образцу
 * OrgApplications.vue (отклонение заявки с причиной). */
const { t } = useI18n()
const { dateTime } = useLocaleFormat()
const toast = useToast()
const refdata = useRefdataStore()
const r = useIncomingReferrals()

const CONSENT_TONES: Record<string, 'ok' | 'neutral' | 'accent'> = { accepted: 'ok', declined: 'neutral', pending: 'accent' }
const severeCount = computed(() => r.items.value.filter((i) => i.severe).length)
const discharging = ref<IncomingReferral | null>(null)
const summary = ref('')

async function confirm(decisionId: string, patientRef: string) {
  if (await r.confirm(decisionId, patientRef)) {
    toast.add({ severity: 'success', summary: t('doctor.incoming.confirmed'), life: 4000 })
  }
}

async function confirmDischarge() {
  if (!discharging.value || !summary.value.trim()) return
  const item = discharging.value
  if (await r.discharge(item.decisionId, item.patientRef, summary.value)) {
    toast.add({ severity: 'success', summary: t('doctor.incoming.discharged'), life: 4000 })
    discharging.value = null
  }
}

function toggleSevere() {
  r.severeOnly.value = !r.severeOnly.value
  r.load()
}

function toggleConfirmed() {
  r.showConfirmed.value = !r.showConfirmed.value
  r.load()
}

onMounted(async () => {
  await refdata.load()
  await r.load()
})
</script>

<template>
  <PageShell :title="t('doctor.incoming.title')">
    <template #subtitle>{{ t('doctor.incoming.subtitle') }} · {{ t('doctor.incoming.total', { n: r.items.value.length }) }}</template>
    <template #actions>
      <Button :label="t('doctor.incoming.refresh')" icon="pi pi-refresh" size="small" severity="secondary" text :loading="r.loading.value" @click="r.load" />
    </template>
    <div class="chips">
      <button type="button" class="chip-filter" :class="{ active: r.severeOnly.value }" data-testid="filter-severe" @click="toggleSevere">
        {{ t('doctor.incoming.severeOnly') }} · {{ severeCount }}
      </button>
      <button type="button" class="chip-filter" :class="{ active: r.showConfirmed.value }" data-testid="filter-confirmed" @click="toggleConfirmed">
        {{ t('doctor.incoming.includeConfirmed') }}
      </button>
    </div>

    <AppCard>
      <AsyncState :loading="r.loading.value" :error="r.error.value" :empty="r.items.value.length === 0" :lines="6"
        :empty-title="t('doctor.incoming.empty')" :empty-text="t('doctor.incoming.emptyText')" empty-icon="pi pi-inbox" @retry="r.load">
        <div class="table-wrap">
          <table class="dense-table" data-testid="incoming-table">
            <thead>
              <tr>
                <th>{{ t('doctor.incoming.colPatient') }}</th><th>{{ t('doctor.incoming.colFrom') }}</th><th>{{ t('doctor.incoming.colWhen') }}</th>
                <th>{{ t('doctor.incoming.colConsent') }}</th><th>{{ t('doctor.incoming.colSeverity') }}</th><th>{{ t('doctor.incoming.colAction') }}</th><th>{{ t('doctor.incoming.colDischarge') }}</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="i in r.items.value" :key="i.decisionId">
                <td><span class="mono strong">{{ i.patientRef }}</span><div class="caption">{{ refdata.profileName(i.profileCode) }}</div></td>
                <td :title="i.fromMoName">{{ shortOrgName(i.fromMoName) }}<div class="caption">{{ i.fromMoCode }}</div></td>
                <td class="nowrap muted">{{ dateTime(i.recordedAt) }}</td>
                <td><StatusTag :value="t('route.consentStatus.' + i.patientConsent)" :tone="CONSENT_TONES[i.patientConsent]" /></td>
                <td><StatusTag v-if="i.severe" :value="t('route.severeFlag')" tone="danger" /><span v-else class="muted">—</span></td>
                <td>
                  <StatusTag v-if="i.confirmed" :value="t('doctor.incoming.alreadyConfirmed')" tone="ok" />
                  <Button v-else :label="t('doctor.incoming.confirm')" size="small" :disabled="i.patientConsent !== 'accepted' || r.acting.value !== null"
                    :loading="r.acting.value === i.decisionId" data-testid="confirm-referral" @click="confirm(i.decisionId, i.patientRef)" />
                </td>
                <td>
                  <StatusTag v-if="i.discharged" :value="t('doctor.incoming.alreadyDischarged')" tone="ok" />
                  <Button v-else-if="i.confirmed" :label="t('doctor.incoming.discharge')" size="small" severity="secondary"
                    :disabled="r.acting.value !== null" data-testid="discharge-referral" @click="discharging = i; summary = ''" />
                  <span v-else class="muted">—</span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </AsyncState>
      <p class="caption" style="margin: 12px 0 0">{{ t('doctor.incoming.note') }}</p>
    </AppCard>
    <Dialog :visible="discharging !== null" modal :header="t('doctor.incoming.dischargeTitle')" :style="{ width: 'min(520px, 94vw)' }"
      @update:visible="(v: boolean) => !v && (discharging = null)">
      <div class="field">
        <label for="discharge-summary">{{ t('doctor.incoming.dischargeSummary') }}</label>
        <Textarea id="discharge-summary" v-model="summary" rows="4" auto-resize :placeholder="t('doctor.incoming.dischargeSummaryPlaceholder')" style="width: 100%" />
      </div>
      <template #footer>
        <Button :label="t('common.cancel')" severity="secondary" @click="discharging = null" />
        <Button :label="t('doctor.incoming.discharge')" :disabled="!summary.trim()" :loading="r.acting.value === discharging?.decisionId"
          data-testid="confirm-discharge" @click="confirmDischarge" />
      </template>
    </Dialog>
  </PageShell>
</template>

<style scoped>
.strong { font-weight: 500; }
.nowrap { white-space: nowrap; }
</style>
