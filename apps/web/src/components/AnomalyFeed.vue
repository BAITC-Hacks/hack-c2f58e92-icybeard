<script setup lang="ts">
import Button from 'primevue/button'
import InputText from 'primevue/inputtext'
import { ref } from 'vue'
import { useI18n } from 'vue-i18n'
import type { Anomaly } from '@/api/types'
import StatusTag from '@/components/ui/StatusTag.vue'
import { anomalySentence, describeEntity, severityLabel, statusLabel, streamTitle, type EntityNames } from '@/lib/anomaly'
import { num, severityTone, shortOrgName } from '@/lib/format'
import { useRefdataStore } from '@/stores/refdata'

/** Лента сигналов строками: уровень чипом и что отклонилось, ниже — где (регион, больница, профиль) и одной фразой
 * «дата: было N, обычно около M — больше/меньше обычного»; сила отклонения — во всплывающей подсказке. «Подтвердить» /
 * «Ложный сигнал» — справа (в compact — под текстом) с необязательным комментарием. */
/** compact — лента внутри кабинета одной организации: регион и название не повторяются, действия — под текстом.
 * compact="region" — лента страницы региона: не повторяется только регион, больница остаётся. */
const props = defineProps<{ items: Anomaly[]; canAck?: boolean; compact?: boolean | 'region' }>()
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

function entityText(anomaly: Anomaly): string {
  if (!props.compact) return describeEntity(anomaly.entity, anomaly.regionKato, names).join(' · ')
  if (props.compact === 'region') {
    const { region_kato: _region, ...withOrg } = anomaly.entity
    return describeEntity(withOrg, null, names).join(' · ')
  }
  const { region_kato: _r, mo_code: _m, mo_key: _k, ...rest } = anomaly.entity
  return describeEntity(rest, null, names).join(' · ')
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
  <div class="rows feed" :class="{ compact }">
    <p v-if="items.length === 0" class="muted">{{ t('anomalyFeed.empty') }}</p>
    <div v-for="anomaly in items" :key="anomaly.id" class="row feed-row" :data-testid="`anomaly-${anomaly.id}`">
      <div class="row-main">
        <div class="head">
          <StatusTag :value="severityLabel(anomaly.severity)" :tone="TONES[severityTone(anomaly.severity)]" />
          <span class="strong">{{ streamTitle(anomaly.streamId) }}</span>
          <span v-if="anomaly.kind === 'shared'" class="wave" :title="t('anomalyFeed.waveHint')">{{ anomaly.affected ? t('anomalyFeed.waveCount', { n: anomaly.affected }) : t('anomalyFeed.wave') }}</span>
          <StatusTag v-if="anomaly.status !== 'open'" :value="statusLabel(anomaly.status)" tone="neutral" />
        </div>
        <div v-if="entityText(anomaly)" class="entity">{{ entityText(anomaly) }}</div>
        <div class="row-sub" :title="t('anomalyFeed.scoreHint', { score: anomaly.score.toFixed(1) })">
          {{ anomalySentence(anomaly, num) }}<template v-if="anomaly.comment"> · «{{ anomaly.comment }}»</template>
        </div>
        <div v-if="answering?.id === anomaly.id" class="answer">
          <InputText v-model="comment" size="small" :placeholder="t('anomalyFeed.commentPlaceholder')" @keyup.enter="send" />
          <Button :label="answering.dismiss ? t('anomalyFeed.falseSignal') : t('common.confirm')" size="small" :severity="answering.dismiss ? 'secondary' : undefined" @click="send" />
          <Button :label="t('common.cancel')" size="small" text severity="secondary" @click="answering = null" />
        </div>
      </div>
      <div v-if="canAck && anomaly.status === 'open' && answering?.id !== anomaly.id" class="row-value actions">
        <Button :label="t('common.confirm')" size="small" icon="pi pi-check" text @click="begin(anomaly, false)" />
        <Button :label="t('anomalyFeed.falseSignal')" size="small" icon="pi pi-times" text severity="secondary" @click="begin(anomaly, true)" />
      </div>
    </div>
  </div>
</template>

<style scoped>
.feed-row { align-items: flex-start; padding: 16px 0; gap: 16px; }
.strong { font-weight: var(--fw-bold); }
.head { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; row-gap: 6px; }
.entity { margin-top: 6px; color: var(--text-secondary); line-height: 1.45; }
.row-sub { margin-top: 4px; line-height: 1.5; }
.wave { font-size: var(--dm-text-sm); color: var(--text-secondary); border-bottom: 1px dotted currentColor; cursor: help; }
.actions { flex-wrap: nowrap; }
.compact .feed-row { flex-direction: column; align-items: stretch; gap: 6px; padding: 14px 0; }
.compact .row-value { justify-content: flex-start; margin-left: -10px; }
.answer { display: flex; gap: 6px; align-items: center; flex-wrap: wrap; margin-top: 8px; }
.answer .p-inputtext { flex: 1 1 220px; }
</style>
