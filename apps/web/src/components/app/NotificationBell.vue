<script setup lang="ts">
import Popover from 'primevue/popover'
import { computed, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRouter } from 'vue-router'
import type { CitizenNotification, PatientEvent } from '@/api/types'
import { useLocaleFormat } from '@/composables/useLocaleFormat'
import { useNotificationBell } from '@/composables/useNotificationBell'
import { shortOrgName } from '@/lib/format'
import { dateShort } from '@/lib/route'

/** Колокольчик: персоналу — входящие, подтверждения и выписки по направлениям своей организации; гражданину — что по
 * его маршруту сделали другие (composable сам решает, кого и что опрашивать). Опрос раз в 45 секунд; клик по
 * уведомлению отмечает его прочитанным и открывает нужный экран. «Нужен ваш ответ» на перевод показывается всегда. */
const { t } = useI18n()
const { dateTime } = useLocaleFormat()
const router = useRouter()
const bell = useNotificationBell()
const panel = ref<InstanceType<typeof Popover> | null>(null)
const citizenItems = computed(() => bell.citizen.value?.items ?? [])
const empty = computed(() => bell.unreadCount.value === 0 && citizenItems.value.length === 0)

const CITIZEN_ICONS: Record<string, string> = {
  redirect: 'pi-arrow-right-arrow-left', confirm: 'pi-calendar', reschedule: 'pi-calendar', reject: 'pi-times-circle', cancel: 'pi-times-circle',
  keep: 'pi-check-circle', admit: 'pi-building', discharge: 'pi-file-check', no_show: 'pi-exclamation-circle', close: 'pi-flag', tests_expiring: 'pi-clock',
  scribe_consent: 'pi-microphone', scribe_leaflet: 'pi-file',
}

function toggle(event: Event) {
  panel.value?.toggle(event)
}

function openIncoming() {
  panel.value?.hide()
  router.push('/doctor/referrals/incoming')
}

async function openConfirmation(decisionId: string) {
  await bell.markRead('referral-confirmed', decisionId)
  openIncoming()
}

async function openDischarge(decisionId: string) {
  await bell.markRead('referral-discharged', decisionId)
  openIncoming()
}

const PATIENT_ICONS: Record<string, string> = {
  request: 'pi-arrow-right-arrow-left', prefer_current: 'pi-home', still_waiting: 'pi-clock', withdraw: 'pi-times-circle', treated_elsewhere: 'pi-building',
  consent_accepted: 'pi-check-circle', consent_declined: 'pi-times-circle', scribe_granted: 'pi-microphone', scribe_declined: 'pi-microphone', scribe_withdrawn: 'pi-microphone',
}

function patientText(s: PatientEvent) {
  return t('bell.patient.' + s.kind, { ref: s.patientRef, org: shortOrgName(s.moName) })
}

/** Событие пациента: отмечаем прочитанным и открываем его маршрут (ответы на запись приёма — экран скрайба). */
async function openPatient(s: PatientEvent) {
  await bell.markRead('patient-signal', s.id)
  panel.value?.hide()
  if (s.kind.startsWith('scribe_')) router.push({ name: 'scribe', query: { patientRef: s.patientRef } })
  else router.push({ name: 'patient-route', params: { patientRef: s.patientRef } })
}

function citizenText(n: CitizenNotification) {
  return t('bell.citizen.' + n.kind, { org: shortOrgName(n.moName), date: dateShort(n.plannedAt), count: n.count ?? 0 })
}

async function openRoute(n: CitizenNotification) {
  if (!n.read) await bell.markRouteRead(n.id)
  panel.value?.hide()
  router.push({ name: 'my-route' })
}
</script>

<template>
  <button type="button" class="bell" :aria-label="t('bell.title')" data-testid="notification-bell" @click="toggle">
    <i class="pi pi-bell icon" aria-hidden="true" />
    <span v-if="bell.unreadCount.value > 0" class="badge" data-testid="notification-bell-count">{{ bell.unreadCount.value }}</span>
  </button>
  <Popover ref="panel" class="bell-panel">
    <div class="bell-content">
      <div class="bell-header">{{ t('bell.title') }}<span v-if="bell.unreadCount.value" class="bell-count">{{ t('bell.unread', { n: bell.unreadCount.value }) }}</span></div>
      <div v-if="empty" class="bell-empty">{{ t('bell.empty') }}</div>
      <div v-else class="bell-list">
      <template v-if="bell.data.value">
        <button v-if="bell.data.value.pendingIncomingCount > 0" type="button" class="bell-item" data-testid="bell-pending-incoming" @click="openIncoming">
          <i class="pi pi-inbox icon" aria-hidden="true" />
          <span class="text">{{ t('bell.pendingIncoming', { n: bell.data.value.pendingIncomingCount }) }}</span>
        </button>
        <button v-for="c in bell.data.value.unreadConfirmations" :key="c.decisionId" type="button" class="bell-item" data-testid="bell-confirmation"
          @click="openConfirmation(c.decisionId)">
          <i class="pi pi-check-circle icon" aria-hidden="true" />
          <span class="text">{{ t('bell.confirmed', { org: c.toMoName }) }}<span class="caption">{{ dateTime(c.confirmedAt) }}</span></span>
        </button>
        <button v-for="d in bell.data.value.unreadDischarges" :key="d.decisionId" type="button" class="bell-item" data-testid="bell-discharge"
          @click="openDischarge(d.decisionId)">
          <i class="pi pi-file-check icon" aria-hidden="true" />
          <span class="text">{{ t('bell.discharged', { org: d.fromMoName }) }}<span class="caption">{{ dateTime(d.dischargedAt) }}</span></span>
        </button>
        <button v-for="s in bell.data.value.patientSignals ?? []" :key="s.id" type="button" class="bell-item" data-testid="bell-patient" :data-kind="s.kind"
          @click="openPatient(s)">
          <i class="pi icon" :class="PATIENT_ICONS[s.kind] ?? 'pi-user'" aria-hidden="true" />
          <span class="text">{{ patientText(s) }}<span v-if="s.comment" class="comment">«{{ s.comment }}»</span><span class="caption">{{ dateTime(s.at) }}</span></span>
        </button>
      </template>
      <button v-for="n in citizenItems" :key="n.id" type="button" class="bell-item" :class="{ read: n.read }" data-testid="bell-citizen" :data-kind="n.kind"
        @click="openRoute(n)">
        <i class="pi icon" :class="CITIZEN_ICONS[n.kind] ?? 'pi-info-circle'" aria-hidden="true" />
        <span class="text">{{ citizenText(n) }}<span class="caption">{{ dateTime(n.at) }}<template v-if="n.needsAction"> · <b class="needs">{{ t('bell.citizen.needsAction') }}</b></template></span></span>
      </button>
      </div>
    </div>
  </Popover>
</template>

<style scoped>
.bell { position: relative; display: inline-flex; align-items: center; justify-content: center; width: 36px; height: 36px; border: 0; border-radius: 50%; background: transparent; color: var(--text-muted); cursor: pointer; }
.bell:hover { background: var(--surface-muted); color: var(--text); }
.bell .icon { font-size: 16px; }
.badge { position: absolute; top: 2px; right: 2px; min-width: 16px; height: 16px; padding: 0 4px; border-radius: 999px; background: var(--danger, #e5484d); color: #fff; font-size: 11px; font-weight: 600; line-height: 16px; text-align: center; }
.bell-content { display: flex; flex-direction: column; width: min(380px, 88vw); }
.bell-header { display: flex; align-items: baseline; justify-content: space-between; gap: 8px; font-weight: var(--fw-bold); font-size: var(--fs-base); padding: 2px 4px 10px; border-bottom: 1px solid var(--border-soft); }
.bell-count { font-size: var(--fs-xs); font-weight: 600; color: var(--text-muted); }
.bell-list { display: flex; flex-direction: column; gap: 2px; max-height: min(440px, 60vh); overflow-y: auto; padding: 6px 2px 2px; margin-right: -6px; padding-right: 6px; }
.bell-empty { padding: 16px 4px; color: var(--text-muted); font-size: var(--fs-sm); text-align: center; }
.bell-item { display: flex; align-items: flex-start; gap: 12px; padding: 10px 8px; border: 0; border-radius: 10px; background: transparent; text-align: left; font: inherit; font-size: var(--fs-sm); line-height: 1.4; color: var(--text); cursor: pointer; }
.bell-item:hover { background: var(--surface-muted); }
.bell-item.read { color: var(--text-muted); }
.bell-item .icon { flex: none; width: 32px; height: 32px; display: grid; place-items: center; border-radius: 50%; background: var(--accent-soft); color: var(--accent-strong); font-size: 14px; }
.bell-item.read .icon { background: var(--surface-muted); color: var(--text-muted); }
.bell-item .text { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
.bell-item .comment { color: var(--text-secondary); font-style: italic; }
.bell-item .caption { color: var(--text-muted); font-size: var(--fs-xs, 11px); }
.needs { color: var(--danger, #e5484d); font-weight: 600; }
</style>
