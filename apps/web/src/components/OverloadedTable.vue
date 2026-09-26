<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import type { OverloadedOrganization } from '@/api/types'
import { pct, shortOrgName } from '@/lib/format'

/** Ранжированные по нагрузке организации: короткие имена (полное — в title), переход в кабинет и в симулятор. */
defineProps<{ items: OverloadedOrganization[] }>()
const emit = defineEmits<{ organization: [moCode: string]; simulate: [item: OverloadedOrganization] }>()
const { t } = useI18n()

/** Больше 1 — поток направлений превышает госпитализации, очередь растёт; null — госпитализаций вообще нет
 * при живом потоке (throughput_per_day = 0), это тоже перегрузка, просто без коэффициента. */
function loadLabel(load: number | null): string {
  return load === null ? t('overloadedTable.noAdmissions') : load.toFixed(1)
}
</script>

<template>
  <p v-if="!items.length" class="muted">{{ t('overloadedTable.none') }}</p>
  <div v-else class="table-wrap">
    <table class="dense-table">
      <thead>
        <tr><th>#</th><th>{{ t('common.organization') }}</th><th class="num">{{ t('overloadedTable.load') }}</th><th class="num">{{ t('overloadedTable.queue') }}</th><th class="num">p90</th><th class="num">{{ t('overloadedTable.refusals') }}</th><th></th></tr>
      </thead>
      <tbody>
        <tr v-for="(item, i) in items" :key="item.moCode" class="clickable" @click="emit('organization', item.moCode)">
          <td class="muted">{{ i + 1 }}</td>
          <td :title="item.name">{{ shortOrgName(item.name) }} <span class="mono muted">{{ item.moCode }}</span></td>
          <td class="num" :class="{ 'delta-up': item.load === null || item.load > 1 }">{{ loadLabel(item.load) }}</td>
          <td class="num">{{ item.queueLen }}</td>
          <td class="num">{{ item.queueAgeP90?.toFixed(0) ?? '—' }}</td>
          <td class="num">{{ pct(item.refusalRate4w) }}</td>
          <td><a href="#" class="small" @click.prevent.stop="emit('simulate', item)">{{ t('overloadedTable.toSimulator') }} →</a></td>
        </tr>
      </tbody>
    </table>
  </div>
</template>
