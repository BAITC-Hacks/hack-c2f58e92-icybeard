<script setup lang="ts">
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import Textarea from 'primevue/textarea'
import { ref } from 'vue'
import { useI18n } from 'vue-i18n'
import type { OrgApplication } from '@/api/types'
import AsyncState from '@/components/states/AsyncState.vue'
import StatusTag from '@/components/ui/StatusTag.vue'
import { useLocaleFormat } from '@/composables/useLocaleFormat'
import { useRefdataStore } from '@/stores/refdata'

/** «Заявки на регистрацию» (admin.orgs): заявки со статусом pending_review — «Одобрить» (создаёт администратора
 * организации с приглашением) и «Отклонить» с причиной. */
defineProps<{ items: OrgApplication[]; loading: boolean; error: unknown; busyId: string | null; bare?: boolean }>()
const emit = defineEmits<{ approve: [OrgApplication]; reject: [OrgApplication, string]; retry: [] }>()
const { t, te } = useI18n()
const { date } = useLocaleFormat()
const refdata = useRefdataStore()
const rejecting = ref<OrgApplication | null>(null)
const reason = ref('')
const typeLabel = (type: string) => (te(`signup.type.${type}`) ? t(`signup.type.${type}`) : type)

function confirmReject() {
  if (!rejecting.value || !reason.value.trim()) return
  emit('reject', rejecting.value, reason.value.trim())
  rejecting.value = null
}
</script>

<template>
  <section class="applications" :class="{ card: !bare }" data-testid="org-applications">
    <div v-if="!bare" class="head"><h2>{{ t('admin.orgs.applicationsTitle') }}</h2><StatusTag v-if="items.length" :value="t('admin.orgs.applicationsCount', { n: items.length })" tone="info" /></div>
    <AsyncState :loading="loading" :error="error" :empty="items.length === 0" skeleton="lines" :lines="3" :empty-title="t('admin.orgs.noApplications')" empty-icon="pi pi-inbox" @retry="emit('retry')">
      <div class="apps">
        <article v-for="a in items" :key="a.id" class="app">
          <header class="app-head">
            <div>
              <div class="app-name">{{ a.orgName }}</div>
              <div class="caption">{{ t('admin.orgs.appSubmitted', { number: a.number, date: date(a.submittedAt) }) }}</div>
            </div>
            <StatusTag :value="t('admin.orgs.appNew')" tone="info" />
          </header>
          <dl class="app-facts">
            <div><dt>{{ t('admin.orgs.appType') }}</dt><dd>{{ typeLabel(a.type) }}</dd></div>
            <div><dt>{{ t('admin.orgs.appRegion') }}</dt><dd>{{ refdata.regionName(a.regionKato) }}</dd></div>
            <div><dt>{{ t('admin.orgs.appBin') }}</dt><dd class="tabular">{{ a.bin }}</dd></div>
            <div v-if="a.moCode"><dt>{{ t('admin.orgs.appMoCode') }}</dt><dd class="tabular">{{ a.moCode }}</dd></div>
          </dl>
          <div class="app-contact">
            <div class="contact-title">{{ t('admin.orgs.appContact') }}</div>
            <div class="contact-name">{{ a.adminName }}</div>
            <div class="contact-line"><i class="pi pi-envelope" aria-hidden="true" /><a :href="`mailto:${a.email}`">{{ a.email }}</a></div>
            <div v-if="a.phone" class="contact-line"><i class="pi pi-phone" aria-hidden="true" /><span class="tabular">{{ a.phone }}</span></div>
          </div>
          <p class="caption app-hint">{{ t('admin.orgs.appHint') }}</p>
          <div class="buttons">
            <Button :label="t('admin.orgs.approve')" icon="pi pi-check" :loading="busyId === a.id" :disabled="busyId !== null" @click="emit('approve', a)" />
            <Button :label="t('admin.orgs.reject')" icon="pi pi-times" severity="secondary" outlined :disabled="busyId !== null" @click="rejecting = a; reason = ''" />
          </div>
        </article>
      </div>
    </AsyncState>
    <Dialog :visible="rejecting !== null" modal :header="t('admin.orgs.rejectTitle')" :style="{ width: 'min(460px, 92vw)' }" @update:visible="(v: boolean) => !v && (rejecting = null)">
      <div class="field"><label for="app-reason">{{ t('admin.orgs.rejectReason') }}</label><Textarea id="app-reason" v-model="reason" rows="3" auto-resize /></div>
      <template #footer>
        <Button :label="t('common.cancel')" severity="secondary" @click="rejecting = null" />
        <Button :label="t('admin.orgs.reject')" severity="danger" :disabled="!reason.trim()" @click="confirmReject" />
      </template>
    </Dialog>
  </section>
</template>

<style scoped>
.applications { display: flex; flex-direction: column; gap: 12px; }
.head { display: flex; align-items: center; gap: 10px; }
.head h2 { margin: 0; }
.apps { display: flex; flex-direction: column; gap: 16px; }
.app { border: 1px solid var(--dm-hairline); border-radius: 16px; padding: 18px 20px; display: flex; flex-direction: column; gap: 14px; }
.app-head { display: flex; justify-content: space-between; align-items: flex-start; gap: 12px; }
.app-name { font-size: var(--dm-text-lg); font-weight: var(--fw-bold); line-height: 1.3; margin-bottom: 2px; }
.app-facts { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 12px 20px; margin: 0; }
.app-facts dt { font-size: var(--dm-text-sm); color: var(--text-secondary); }
.app-facts dd { margin: 2px 0 0; font-size: var(--dm-text-md); }
.app-contact { background: var(--surface-muted); border-radius: 12px; padding: 12px 14px; display: flex; flex-direction: column; gap: 4px; }
.contact-title { font-size: var(--dm-text-sm); color: var(--text-secondary); }
.contact-name { font-weight: var(--fw-bold); }
.contact-line { display: flex; align-items: center; gap: 8px; }
.contact-line i { color: var(--text-secondary); font-size: 13px; }
.app-hint { margin: 0; line-height: 1.45; }
.buttons { display: flex; gap: 10px; }
</style>
