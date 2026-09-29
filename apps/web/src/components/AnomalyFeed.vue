<script setup lang="ts">
import Button from 'primevue/button'
import InputText from 'primevue/inputtext'
import { ref } from 'vue'
import { useI18n } from 'vue-i18n'
import type { Anomaly } from '@/api/types'
import StatusTag from '@/components/ui/StatusTag.vue'
import { describeEntity, deviationText, severityLabel, statusLabel, streamTitle, type EntityNames } from '@/lib/anomaly'
import { num, severityTone, shortOrgName } from '@/lib/format'
import { useRefdataStore } from '@/stores/refdata'

/** Лента сигналов строками: уровень чипом, поток и сущность, наблюдение против ожидания; «Подтвердить» / «Ложный»
 * прямо в строке с необязательным комментарием (отклонение — отрицательная метка для дообучения детектора). */
defineProps<{ items: Anomaly[]; canAck?: boolean }>()
const emit = defineEmits<{ ack: [id: string, comment: string]; dismiss: [id: string, comment: string] }>()
const { t } = useI18n()
const refdata = useRefdataStore()
const answering = ref<{ id: string; dismiss: boolean } | null>(null)
const comment = ref('')

const TONES = { danger: 'danger', warn: 'warn', info: 'accent' } as const
const names: EntityNames = {
  region: (kato) => refdata.regionName(kato),
  profile: (code) => refdata.profileName(code),
  organization: (moCode) => shortOrgName(refdata.organizationName(moCode)),
}

function begin(anomaly: Anomaly, dismiss: boolean) {
  answering.value = { id: anomaly.id, dismiss }
  comment.value = ''
}

function send() {
  if (!answering.value) return
  if (answering.value.dismiss) emit('dismiss', answering.value.id, comment.value)
  else emit('ack', answering.value.id, comment.value)
  answering.value = null
}
</script>

<template>
  <div class="rows feed">
    <p v-if="items.length === 0" class="muted">{{ t('anomalyFeed.empty') }}</p>
    <div v-for="anomaly in items" :key="anomaly.id" class="row feed-row" :data-testid="`anomaly-${anomaly.id}`">
      <div class="row-main">
        <div class="chips head">
          <StatusTag :value="severityLabel(anomaly.severity)" :tone="TONES[severityTone(anomaly.severity)]" />
          <span class="strong">{{ streamTitle(anomaly.streamId) }}</span>
          <span class="muted">· {{ describeEntity(anomaly.entity, anomaly.regionKato, names).join(' · ') }}</span>
          <StatusTag v-if="anomaly.kind === 'shared'" :value="anomaly.affected ? `${t('anomalyFeed.sharedWave')} · ${anomaly.affected}` : t('anomalyFeed.sharedWave')" tone="neutral" />
          <StatusTag v-if="anomaly.status !== 'open'" :value="statusLabel(anomaly.status)" tone="neutral" />
        </div>
        <div class="row-sub">
          <span class="tabular">{{ anomaly.period }}</span> · {{ t('anomalyFeed.observed') }} <b class="tabular">{{ num(anomaly.observed) }}</b> {{ t('anomalyFeed.atExpected') }} {{ num(anomaly.expected) }}
          ({{ deviationText(anomaly.observed, anomaly.expected) }}) · {{ t('anomalyFeed.score') }} {{ anomaly.score.toFixed(1) }}
          <template v-if="anomaly.comment"> · «{{ anomaly.comment }}»</template>
        </div>
        <div v-if="answering?.id === anomaly.id" class="answer">
          <InputText v-model="comment" size="small" :placeholder="t('anomalyFeed.commentPlaceholder')" @keyup.enter="send" />
          <Button :label="answering.dismiss ? t('anomalyFeed.falseSignal') : t('common.confirm')" size="small" :severity="answering.dismiss ? 'secondary' : undefined" @click="send" />
          <Button :label="t('common.cancel')" size="small" text severity="secondary" @click="answering = null" />
        </div>
      </div>
      <div v-if="canAck && anomaly.status === 'open' && answering?.id !== anomaly.id" class="row-value">
        <Button :label="t('common.confirm')" size="small" icon="pi pi-check" text @click="begin(anomaly, false)" />
        <Button :label="t('anomalyFeed.falseSignal')" size="small" icon="pi pi-times" text severity="secondary" @click="begin(anomaly, true)" />
      </div>
    </div>
  </div>
</template>

<style scoped>
.feed-row { align-items: flex-start; }
.strong { font-weight: var(--fw-bold); }
.head { row-gap: 4px; }
.answer { display: flex; gap: 6px; align-items: center; flex-wrap: wrap; margin-top: 6px; }
.answer .p-inputtext { flex: 1 1 220px; }
</style>
