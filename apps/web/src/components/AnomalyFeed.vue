<script setup lang="ts">
import Button from 'primevue/button'
import InputText from 'primevue/inputtext'
import Tag from 'primevue/tag'
import { ref } from 'vue'
import type { Anomaly } from '@/api/types'
import { describeEntity, deviationText, severityLabel, statusLabel, streamTitle, type EntityNames } from '@/lib/anomaly'
import { num, severityTone } from '@/lib/format'
import { useRefdataStore } from '@/stores/refdata'

defineProps<{ items: Anomaly[]; canAck?: boolean }>()
const emit = defineEmits<{ ack: [id: string, comment: string]; dismiss: [id: string, comment: string] }>()
const comments = ref<Record<string, string>>({})
const refdata = useRefdataStore()

const names: EntityNames = {
  region: (kato) => refdata.regionName(kato),
  profile: (code) => refdata.profileName(code),
  organization: (moCode) => refdata.organizationName(moCode),
}
</script>

<template>
  <div>
    <p v-if="items.length === 0" class="muted">Открытых сигналов нет</p>
    <div v-for="anomaly in items" :key="anomaly.id" class="card" style="margin-bottom: 8px; padding: 12px">
      <div style="display: flex; gap: 8px; align-items: center; flex-wrap: wrap">
        <Tag :value="severityLabel(anomaly.severity)" :severity="severityTone(anomaly.severity)" />
        <Tag :value="anomaly.kind === 'shared' ? 'общая волна' : 'отдельная сущность'" severity="secondary" />
        <span v-if="anomaly.affected" class="muted">затронуто: {{ anomaly.affected }}</span>
        <strong>{{ streamTitle(anomaly.streamId) }}</strong>
        <span class="muted">{{ anomaly.period }}</span>
        <span v-if="anomaly.status !== 'open'" class="muted">· {{ statusLabel(anomaly.status) }}</span>
      </div>
      <div style="margin: 6px 0">{{ describeEntity(anomaly.entity, anomaly.regionKato, names).join(' · ') }}</div>
      <div class="muted">
        наблюдение {{ num(anomaly.observed) }} при ожидании {{ num(anomaly.expected) }} ({{ deviationText(anomaly.observed, anomaly.expected) }}),
        сила {{ anomaly.score.toFixed(1) }}
      </div>
      <div v-if="anomaly.comment" class="muted">комментарий: {{ anomaly.comment }}</div>
      <div v-if="canAck && anomaly.status === 'open'" class="actions">
        <InputText v-model="comments[anomaly.id]" placeholder="что выяснили" size="small" style="flex: 1 1 200px" />
        <Button label="Подтвердить" size="small" icon="pi pi-check" @click="emit('ack', anomaly.id, comments[anomaly.id] ?? '')" />
        <!-- отклонение — отрицательная метка для дообучения детектора (models/anomaly_labels) -->
        <Button label="Ложный сигнал" size="small" icon="pi pi-times" severity="secondary" outlined @click="emit('dismiss', anomaly.id, comments[anomaly.id] ?? '')" />
      </div>
    </div>
  </div>
</template>
