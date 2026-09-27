<script setup lang="ts">
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import ToggleSwitch from 'primevue/toggleswitch'
import { useToast } from 'primevue/usetoast'
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { account } from '@/api/endpoints'
import type { AccessLogEntry, Consent, ConsentsResponse } from '@/api/types'
import AccountTabs from '@/components/account/AccountTabs.vue'
import ErrorBox from '@/components/ErrorBox.vue'
import AsyncState from '@/components/states/AsyncState.vue'
import AppCard from '@/components/ui/AppCard.vue'
import PageShell from '@/components/ui/PageShell.vue'
import StatusTag from '@/components/ui/StatusTag.vue'
import { useAsync } from '@/composables/useAsync'
import { useLocaleFormat } from '@/composables/useLocaleFormat'
import { roleTitle } from '@/lib/labels'
import { useAuthStore } from '@/stores/auth'

/** Данные и согласия (W-Account-Consents): переключатели согласий (forecasts — обязательное, замок), журнал доступа
 * к моим данным (GET /me/access-log — из аудита), «Выгрузить копию (CSV)» (GET /me/export) и «Запросить удаление
 * учётной записи» (POST /me/deletion-request, с подтверждением). */
const { t, te } = useI18n()
const toast = useToast()
const auth = useAuthStore()
const { date, dateTime } = useLocaleFormat()
const consents = useAsync<ConsentsResponse>(() => account.consents())
const log = useAsync<{ items: AccessLogEntry[] }>(() => account.accessLog())
const pending = ref<string | null>(null)
const actionError = ref<unknown>(null)
const exporting = ref(false)
const confirmDelete = ref(false)
const deleting = ref(false)

const { locale } = useI18n()
/** Название согласия — из API (titleRu/titleKk), иначе из словаря; пояснение — из словаря. */
function label(consent: Consent, part: 'title' | 'text'): string {
  if (part === 'title') {
    const fromApi = locale.value === 'kk' ? consent.titleKk || consent.titleRu : consent.titleRu
    if (fromApi) return fromApi
  } else if (consent.titleRu) return ''
  const key = `account.consents.items.${consent.code}.${part}`
  return te(key) ? t(key) : part === 'title' ? consent.code : ''
}
const subtitle = computed(() => [auth.displayName ?? auth.actor, consents.data.value ? t('account.consents.count', { n: consents.data.value.items.length }) : null, t('account.consents.auditNote')].filter(Boolean).join(' · '))

async function setConsent(consent: Consent, granted: boolean) {
  if (consent.required) return
  pending.value = consent.code
  actionError.value = null
  try {
    await account.setConsent(consent.code, granted)
    await consents.run()
  } catch (e) {
    actionError.value = e
  } finally {
    pending.value = null
  }
}

async function exportCopy() {
  exporting.value = true
  actionError.value = null
  try {
    await account.exportCsv()
  } catch (e) {
    actionError.value = e
  } finally {
    exporting.value = false
  }
}

async function requestDeletion() {
  deleting.value = true
  actionError.value = null
  try {
    await account.requestDeletion()
    confirmDelete.value = false
    toast.add({ severity: 'success', summary: t('account.consents.deletionSent'), life: 5000 })
  } catch (e) {
    actionError.value = e
    confirmDelete.value = false
  } finally {
    deleting.value = false
  }
}

onMounted(() => Promise.all([consents.run(), log.run()]))
</script>

<template>
  <PageShell :title="t('account.consents.title')" :lead="subtitle">
    <AccountTabs />
    <div class="account-col">
      <AppCard :title="t('account.consents.consentsTitle')">
        <template #header><span class="caption">{{ t('account.consents.revokeNote') }}</span></template>
        <AsyncState :loading="consents.loading.value" :error="consents.error.value" :empty="!consents.data.value?.items.length" skeleton="lines" :lines="3" :empty-title="t('account.consents.empty')" @retry="consents.run">
          <div class="rows">
            <div v-for="c in consents.data.value!.items" :key="c.code" class="row" :data-testid="`consent-${c.code}`">
              <span class="row-main">
                <span>{{ label(c, 'title') }}</span>
                <div class="row-sub">{{ [c.required ? t('account.consents.required') : label(c, 'text'), c.updatedAt ? t('account.consents.updated', { date: date(c.updatedAt) }) : null].filter(Boolean).join(' · ') }}</div>
              </span>
              <span class="row-value">
                <i v-if="c.required" class="pi pi-lock muted" :title="t('account.consents.required')" aria-hidden="true" />
                <ToggleSwitch :model-value="c.granted" :disabled="c.required || pending === c.code" :aria-label="label(c, 'title')" @update:model-value="(v: boolean) => setConsent(c, v)" />
              </span>
            </div>
          </div>
        </AsyncState>
      </AppCard>

      <AppCard :title="t('account.consents.logTitle')">
        <template v-if="auth.can('admin.users')" #header><RouterLink class="link-arrow small" to="/gov/audit">{{ t('account.consents.fullLog') }}</RouterLink></template>
        <AsyncState :loading="log.loading.value" :error="log.error.value" :empty="!log.data.value?.items.length" :lines="4" :empty-title="t('account.consents.logEmpty')" empty-icon="pi pi-eye" @retry="log.run">
          <div class="table-wrap">
            <table class="dense-table" data-testid="access-log">
              <thead><tr><th>{{ t('account.consents.colDate') }}</th><th>{{ t('account.consents.colWho') }}</th><th>{{ t('account.consents.colRole') }}</th><th>{{ t('account.consents.colWhat') }}</th><th>{{ t('account.consents.colResult') }}</th></tr></thead>
              <tbody>
                <tr v-for="(entry, i) in log.data.value!.items" :key="entry.at + i">
                  <td class="tabular nowrap">{{ dateTime(entry.at) }}</td><td>{{ entry.actor }}</td><td class="muted">{{ roleTitle(entry.role) }}</td><td class="mono small">{{ entry.method }} {{ entry.path.replace(/^\/api\/v1/, '') }}</td><td><StatusTag :value="String(entry.status)" :tone="entry.status < 300 ? 'ok' : entry.status < 500 ? 'warn' : 'danger'" /></td>
                </tr>
              </tbody>
            </table>
          </div>
        </AsyncState>
      </AppCard>

      <AppCard :title="t('account.consents.myData')">
        <div class="buttons">
          <Button :label="t('account.consents.export')" severity="secondary" :loading="exporting" data-testid="export-csv" @click="exportCopy" />
          <Button :label="t('account.consents.requestDeletion')" severity="danger" data-testid="request-deletion" @click="confirmDelete = true" />
        </div>
        <p class="caption">{{ t('account.consents.deletionNote') }}</p>
        <ErrorBox :error="actionError" />
      </AppCard>
    </div>

    <Dialog v-model:visible="confirmDelete" modal :header="t('account.consents.confirmTitle')" :style="{ width: 'min(480px, 92vw)' }">
      <p class="dialog-text">{{ t('account.consents.confirmText') }}</p>
      <template #footer>
        <Button :label="t('common.cancel')" severity="secondary" @click="confirmDelete = false" />
        <Button :label="t('account.consents.requestDeletion')" severity="danger" :loading="deleting" data-testid="confirm-deletion" @click="requestDeletion" />
      </template>
    </Dialog>
  </PageShell>
</template>

<style scoped>
.account-col { display: flex; flex-direction: column; gap: 16px; max-width: 880px; }
.row-value { gap: 12px; }
/* обязательное согласие: включено и заблокировано — фиолетовый ползунок, как на доске, а не «выключенный» серый */
.row-value :deep(.p-toggleswitch.p-disabled.p-toggleswitch-checked) { opacity: 0.7; }
.row-value :deep(.p-toggleswitch.p-disabled.p-toggleswitch-checked .p-toggleswitch-slider) { background: var(--dm-primary); border-color: var(--dm-primary); }
.row-value :deep(.p-toggleswitch.p-disabled.p-toggleswitch-checked .p-toggleswitch-handle) { background: var(--dm-primary-contrast); }
.nowrap { white-space: nowrap; }
.buttons { display: flex; flex-wrap: wrap; gap: 12px; }
.dialog-text { margin: 0; line-height: 1.5; }
</style>
