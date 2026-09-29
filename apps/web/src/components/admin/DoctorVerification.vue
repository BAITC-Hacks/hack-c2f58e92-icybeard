<script setup lang="ts">
import Button from 'primevue/button'
import { useI18n } from 'vue-i18n'
import type { AdminDoctor } from '@/api/types'
import StateError from '@/components/states/StateError.vue'
import Skeleton from '@/components/ui/Skeleton.vue'
import StatusTag from '@/components/ui/StatusTag.vue'
import { useLocaleFormat } from '@/composables/useLocaleFormat'
import { shortOrgName } from '@/lib/format'

/** Карточка «Верификация · N ожидают» (W-Admin-Doctors): врачи со статусом pending, «Подтвердить» / «Отклонить». */
defineProps<{ items: AdminDoctor[]; total: number; loading: boolean; error: unknown; busyId: string | null }>()
const emit = defineEmits<{ verify: [AdminDoctor]; reject: [AdminDoctor]; retry: [] }>()
const { t } = useI18n()
const { date } = useLocaleFormat()
</script>

<template>
  <section class="card verification" data-testid="doctor-verification">
    <div class="head"><h2>{{ t('admin.doctors.verificationTitle') }}</h2><StatusTag v-if="total" :value="t('admin.doctors.pendingCount', { n: total })" tone="info" /></div>
    <StateError v-if="error" :error="error" compact @retry="emit('retry')" />
    <Skeleton v-else-if="loading && items.length === 0" :lines="3" />
    <p v-else-if="items.length === 0" class="muted small">{{ t('admin.doctors.noPending') }}</p>
    <div v-for="doctor in items" v-else :key="doctor.id" class="pending">
      <div class="strong">{{ doctor.displayName ?? '—' }}<template v-if="doctor.specialty"> · {{ doctor.specialty }}</template></div>
      <div class="caption">{{ [doctor.moName ? shortOrgName(doctor.moName) : null, doctor.moCode, doctor.requestedAt ? t('admin.doctors.requested', { date: date(doctor.requestedAt) }) : null].filter(Boolean).join(' · ') }}</div>
      <div class="buttons">
        <Button :label="t('admin.doctors.verify')" size="small" :loading="busyId === doctor.id" :disabled="busyId !== null" @click="emit('verify', doctor)" />
        <Button :label="t('admin.doctors.reject')" size="small" severity="secondary" :disabled="busyId !== null" @click="emit('reject', doctor)" />
      </div>
    </div>
  </section>
</template>

<style scoped>
.verification { display: flex; flex-direction: column; gap: 12px; }
.head { display: flex; align-items: center; gap: 10px; }
.head h2 { margin: 0; }
.pending { display: flex; flex-direction: column; gap: 4px; padding-bottom: 12px; border-bottom: 1px solid var(--dm-hairline); }
.pending:last-child { border-bottom: 0; padding-bottom: 0; }
.strong { font-weight: var(--fw-bold); }
.buttons { display: flex; gap: 8px; margin-top: 6px; }
</style>
