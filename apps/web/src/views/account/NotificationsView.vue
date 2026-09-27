<script setup lang="ts">
import Button from 'primevue/button'
import Checkbox from 'primevue/checkbox'
import Select from 'primevue/select'
import { useToast } from 'primevue/usetoast'
import { computed, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { account } from '@/api/endpoints'
import type { NotificationEvent, NotificationSettings } from '@/api/types'
import AccountTabs from '@/components/account/AccountTabs.vue'
import ErrorBox from '@/components/ErrorBox.vue'
import AsyncState from '@/components/states/AsyncState.vue'
import AppCard from '@/components/ui/AppCard.vue'
import PageShell from '@/components/ui/PageShell.vue'
import { useAsync } from '@/composables/useAsync'
import { useAuthStore } from '@/stores/auth'

/** Уведомления (W-Account-Notifications): матрица «событие × канал» (в системе · почта · SMS · push), событие
 * `security` всегда включено и не редактируется; тихие часы «с … до …» с исключением для сигналов Минздрава; сводка
 * (нет / ежедневно / еженедельно). Сохранение — PUT /me/notifications. */
const CHANNELS = ['inApp', 'email', 'sms', 'push'] as const
type Channel = (typeof CHANNELS)[number]
const LOCKED_EVENT = 'security'
const HOURS = Array.from({ length: 24 }, (_, h) => `${String(h).padStart(2, '0')}:00`)

const { t, te } = useI18n()
const toast = useToast()
const auth = useAuthStore()
const { data: settings, loading, error, run } = useAsync<NotificationSettings>(() => account.notifications())
const draft = ref<NotificationSettings | null>(null)
const saving = ref(false)
const saveError = ref<unknown>(null)

watch(settings, (value) => {
  draft.value = value ? { ...value, events: value.events.map((e) => ({ ...e })) } : null
})

const { locale } = useI18n()
/** Название события — из API (titleRu/titleKk), иначе из словаря, иначе код. */
function eventLabel(event: NotificationEvent): string {
  const fromApi = locale.value === 'kk' ? event.titleKk || event.titleRu : event.titleRu
  if (fromApi) return fromApi
  return te(`account.notifications.events.${event.code}`) ? t(`account.notifications.events.${event.code}`) : event.code
}
/** Событие «безопасность» не отключается: признак locked от API, без него — по коду. */
const isLocked = (event: NotificationEvent) => event.locked ?? event.code === LOCKED_EVENT
const hourOptions = HOURS.map((h) => ({ value: h, label: h }))
const digestOptions = computed(() => (['off', 'daily', 'weekly'] as const).map((value) => ({ value, label: t(`account.notifications.digest.${value}`) })))
const summary = computed(() => {
  const d = draft.value
  if (!d) return ''
  const quiet = d.quietFrom && d.quietTo ? t('account.notifications.quietSummary', { from: d.quietFrom, to: d.quietTo }) : t('account.notifications.quietOff')
  return [auth.displayName ?? auth.actor, t('account.notifications.eventsCount', { n: d.events.length }), t('account.notifications.channelsCount', { n: CHANNELS.length }), quiet].join(' · ')
})

function toggle(event: NotificationEvent, channel: Channel, value: boolean) {
  if (!draft.value || isLocked(event)) return
  draft.value = { ...draft.value, events: draft.value.events.map((e) => (e.code === event.code ? { ...e, [channel]: value } : e)) }
}

async function save() {
  if (!draft.value) return
  saving.value = true
  saveError.value = null
  try {
    settings.value = await account.saveNotifications(draft.value)
    toast.add({ severity: 'success', summary: t('account.saved'), life: 3000 })
  } catch (e) {
    saveError.value = e
  } finally {
    saving.value = false
  }
}

onMounted(run)
</script>

<template>
  <PageShell :title="t('account.notifications.title')" :lead="summary || undefined">
    <AccountTabs />
    <div class="account-col">
      <AsyncState :loading="loading" :error="error" :empty="!draft" skeleton="table" :lines="7" :empty-title="t('account.notifications.empty')" @retry="run">
        <template v-if="draft">
        <AppCard :title="t('account.notifications.matrixTitle')">
          <template #header><span class="caption">{{ t('account.notifications.matrixHint') }}</span></template>
          <div class="table-wrap">
            <table class="dense-table matrix" data-testid="notifications-matrix">
              <thead><tr><th>{{ t('account.notifications.event') }}</th><th v-for="c in CHANNELS" :key="c" class="center">{{ t(`account.notifications.channel.${c}`) }}</th></tr></thead>
              <tbody>
                <tr v-for="event in draft.events" :key="event.code">
                  <td>{{ eventLabel(event) }}<div v-if="isLocked(event)" class="caption">{{ t('account.notifications.locked') }}</div></td>
                  <td v-for="c in CHANNELS" :key="c" class="center">
                    <Checkbox :model-value="event[c]" binary :disabled="isLocked(event)" :aria-label="`${eventLabel(event)} · ${t(`account.notifications.channel.${c}`)}`" @update:model-value="(v: boolean) => toggle(event, c, v)" />
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </AppCard>
        <div class="grid cols-2">
          <AppCard :title="t('account.notifications.quietTitle')">
            <div class="form-grid two">
              <div class="field"><label for="q-from">{{ t('account.notifications.from') }}</label><Select id="q-from" v-model="draft.quietFrom" :options="hourOptions" option-label="label" option-value="value" show-clear :placeholder="t('account.notifications.none')" /></div>
              <div class="field"><label for="q-to">{{ t('account.notifications.to') }}</label><Select id="q-to" v-model="draft.quietTo" :options="hourOptions" option-label="label" option-value="value" show-clear :placeholder="t('account.notifications.none')" /></div>
            </div>
            <div class="field checkbox quiet-except"><Checkbox v-model="draft.quietExceptRegulator" binary input-id="q-except" /><label for="q-except">{{ t('account.notifications.exceptRegulator') }}</label></div>
          </AppCard>
          <AppCard :title="t('account.notifications.digestTitle')">
            <div class="field"><label for="digest">{{ t('account.notifications.digestLabel') }}</label><Select id="digest" v-model="draft.digest" :options="digestOptions" option-label="label" option-value="value" /></div>
            <p class="caption">{{ t('account.notifications.digestHint') }}</p>
          </AppCard>
        </div>
        <ErrorBox :error="saveError" />
        <div class="form-actions"><Button :label="t('common.save')" :loading="saving" data-testid="notifications-save" @click="save" /></div>
        </template>
      </AsyncState>
    </div>
  </PageShell>
</template>

<style scoped>
.account-col { display: flex; flex-direction: column; gap: 16px; max-width: 880px; }
.matrix th.center, .matrix td.center { text-align: center; width: 96px; }
.form-grid.two { grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 16px; }
.quiet-except { margin-top: 12px; }
.form-actions { display: flex; justify-content: flex-end; }
</style>
