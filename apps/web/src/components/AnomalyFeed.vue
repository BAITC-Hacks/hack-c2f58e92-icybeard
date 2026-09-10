<script setup lang="ts">
import Button from 'primevue/button'
import InputText from 'primevue/inputtext'
import Tag from 'primevue/tag'
import { ref } from 'vue'
import type { Anomaly } from '@/api/types'
import { num, severityTone } from '@/lib/format'

defineProps<{ items: Anomaly[]; canAck?: boolean }>()
const emit = defineEmits<{ ack: [id: string, comment: string] }>()
const comments = ref<Record<string, string>>({})

function entityText(anomaly: Anomaly): string {
  return Object.entries(anomaly.entity)
    .filter(([key]) => key !== 'region_kato')
    .map(([, value]) => value)
    .join(' · ')
}

const streamTitles: Record<string, string> = {
  er_visits_daily: 'приёмный покой',
  admissions_monthly: 'госпитализации',
  vac_monthly: 'вакцинация',
}
</script>

<template>
  <div>
    <p v-if="items.length === 0" class="muted">Открытых сигналов нет</p>
    <div v-for="anomaly in items" :key="anomaly.id" class="card" style="margin-bottom: 8px; padding: 12px">
      <div style="display: flex; gap: 8px; align-items: center; flex-wrap: wrap">
        <Tag :value="anomaly.severity" :severity="severityTone(anomaly.severity)" />
        <Tag :value="anomaly.kind === 'shared' ? 'общая волна' : 'организация'" severity="secondary" />
        <strong>{{ streamTitles[anomaly.streamId] ?? anomaly.streamId }}</strong>
        <span class="muted">{{ anomaly.period }}</span>
        <span v-if="anomaly.status !== 'open'" class="muted">· {{ anomaly.status }}</span>
      </div>
      <div style="margin: 6px 0">{{ entityText(anomaly) }}</div>
      <div class="muted">наблюдение {{ num(anomaly.observed) }} при ожидании {{ num(anomaly.expected) }}, сила {{ anomaly.score.toFixed(1) }}</div>
      <div v-if="anomaly.comment" class="muted">комментарий: {{ anomaly.comment }}</div>
      <div v-if="canAck && anomaly.status === 'open'" class="actions">
        <InputText v-model="comments[anomaly.id]" placeholder="что выяснили" size="small" style="flex: 1 1 200px" />
        <Button label="Подтвердить" size="small" icon="pi pi-check" @click="emit('ack', anomaly.id, comments[anomaly.id] ?? '')" />
      </div>
    </div>
  </div>
</template>
