<script setup lang="ts">
import Popover from 'primevue/popover'
import { ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRouter } from 'vue-router'
import { useLocaleFormat } from '@/composables/useLocaleFormat'
import { useNotificationBell } from '@/composables/useNotificationBell'

/** Колокольчик персонала (задача 13 плана прозрачности, упрощена до внутрисистемных уведомлений): видна только
 * ролям с worklist.view и организацией (composable сам решает, звать ли сервер вообще — для остальных всегда пусто).
 * Опрашивается раз в 45 секунд, пока страница открыта; список кликабелен — открывает «Входящие направления» и
 * попутно отмечает событие прочитанным. Отдельной ссылки «все входящие» нет: сами уведомления ведут туда,
 * а раздел «Входящие» есть в меню. */
const { t } = useI18n()
const { dateTime } = useLocaleFormat()
const router = useRouter()
const bell = useNotificationBell()
const panel = ref<InstanceType<typeof Popover> | null>(null)

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
</script>

<template>
  <button type="button" class="bell" :aria-label="t('bell.title')" data-testid="notification-bell" @click="toggle">
    <i class="pi pi-bell icon" aria-hidden="true" />
    <span v-if="bell.unreadCount.value > 0" class="badge" data-testid="notification-bell-count">{{ bell.unreadCount.value }}</span>
  </button>
  <Popover ref="panel" class="bell-panel">
    <div class="bell-content">
      <div class="bell-header">{{ t('bell.title') }}</div>
      <div v-if="!bell.data.value || bell.unreadCount.value === 0" class="bell-empty">{{ t('bell.empty') }}</div>
      <template v-else>
        <button v-if="bell.data.value.pendingIncomingCount > 0" type="button" class="bell-item" data-testid="bell-pending-incoming" @click="openIncoming">
          <i class="pi pi-inbox icon" aria-hidden="true" />
          <span>{{ t('bell.pendingIncoming', { n: bell.data.value.pendingIncomingCount }) }}</span>
        </button>
        <button v-for="c in bell.data.value.unreadConfirmations" :key="c.decisionId" type="button" class="bell-item" data-testid="bell-confirmation"
          @click="openConfirmation(c.decisionId)">
          <i class="pi pi-check-circle icon" aria-hidden="true" />
          <span>{{ t('bell.confirmed', { org: c.toMoName }) }}<span class="caption">{{ dateTime(c.confirmedAt) }}</span></span>
        </button>
        <button v-for="d in bell.data.value.unreadDischarges" :key="d.decisionId" type="button" class="bell-item" data-testid="bell-discharge"
          @click="openDischarge(d.decisionId)">
          <i class="pi pi-file-check icon" aria-hidden="true" />
          <span>{{ t('bell.discharged', { org: d.fromMoName }) }}<span class="caption">{{ dateTime(d.dischargedAt) }}</span></span>
        </button>
      </template>
    </div>
  </Popover>
</template>

<style scoped>
.bell { position: relative; display: inline-flex; align-items: center; justify-content: center; width: 36px; height: 36px; border: 0; border-radius: 50%; background: transparent; color: var(--dm-muted); cursor: pointer; }
.bell:hover { background: var(--dm-bg); color: var(--dm-ink); }
.bell .icon { font-size: 16px; }
.badge { position: absolute; top: 2px; right: 2px; min-width: 16px; height: 16px; padding: 0 4px; border-radius: 999px; background: var(--dm-danger, #e5484d); color: #fff; font-size: 11px; font-weight: 600; line-height: 16px; text-align: center; }
.bell-content { display: flex; flex-direction: column; gap: 2px; width: min(340px, 88vw); }
.bell-header { font-weight: 600; padding: 4px 4px 8px; }
.bell-empty { padding: 8px 4px; color: var(--dm-muted); font-size: var(--dm-text-sm); }
.bell-item { display: flex; align-items: center; gap: 10px; padding: 8px; border: 0; border-radius: var(--dm-radius-md, 8px); background: transparent; text-align: left; font: inherit; color: var(--dm-ink); cursor: pointer; }
.bell-item:hover { background: var(--dm-bg); }
.bell-item .icon { flex: none; color: var(--dm-accent); }
.bell-item .caption { display: block; color: var(--dm-muted); font-size: var(--dm-text-xs, 11px); }
</style>
