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
defineProps<{ items: OrgApplication[]; loading: boolean; error: unknown; busyId: string | null }>()
const emit = defineEmits<{ approve: [OrgApplication]; reject: [OrgApplication, string]; retry: [] }>()
const { t } = useI18n()
const { date } = useLocaleFormat()
const refdata = useRefdataStore()
const rejecting = ref<OrgApplication | null>(null)
const reason = ref('')

function confirmReject() {
  if (!rejecting.value || !reason.value.trim()) return
  emit('reject', rejecting.value, reason.value.trim())
  rejecting.value = null
}
</script>

<template>
  <section class="card applications" data-testid="org-applications">
    <div class="head"><h2>{{ t('admin.orgs.applicationsTitle') }}</h2><StatusTag v-if="items.length" :value="t('admin.orgs.applicationsCount', { n: items.length })" tone="info" /></div>
    <AsyncState :loading="loading" :error="error" :empty="items.length === 0" skeleton="lines" :lines="3" :empty-title="t('admin.orgs.noApplications')" empty-icon="pi pi-inbox" @retry="emit('retry')">
      <div class="rows">
        <div v-for="a in items" :key="a.id" class="app">
          <div class="strong">{{ a.orgName }}</div>
          <div class="caption">{{ [a.number, t('admin.orgs.bin', { bin: a.bin }), refdata.regionName(a.regionKato), date(a.submittedAt)].join(' · ') }}</div>
          <div class="caption">{{ a.adminName }} · {{ a.email }}</div>
          <div class="buttons">
            <Button :label="t('admin.orgs.approve')" size="small" :loading="busyId === a.id" :disabled="busyId !== null" @click="emit('approve', a)" />
            <Button :label="t('admin.orgs.reject')" size="small" severity="secondary" :disabled="busyId !== null" @click="rejecting = a; reason = ''" />
          </div>
        </div>
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
.app { display: flex; flex-direction: column; gap: 3px; padding: 10px 0; border-bottom: 1px solid var(--dm-hairline); }
.app:last-child { border-bottom: 0; }
.strong { font-weight: var(--fw-bold); }
.buttons { display: flex; gap: 8px; margin-top: 6px; }
</style>
