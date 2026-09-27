<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import type { OverloadedOrganization } from '@/api/types'
import { pct, shortOrgName } from '@/lib/format'

/** Перегруженные организации (W-Gov): строки 48 px «Организация · код | Нагрузка | Очередь | p90 | Отказы», клик —
 * кабинет организации, «в симулятор →» в строке; `limit` — сколько строк показать. */
const props = defineProps<{ items: OverloadedOrganization[]; limit?: number }>()
const emit = defineEmits<{ organization: [moCode: string]; simulate: [item: OverloadedOrganization] }>()
const { t } = useI18n()

const shown = () => (props.limit ? props.items.slice(0, props.limit) : props.items)
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
        <tr><th>{{ t('common.organization') }}</th><th class="num">{{ t('overloadedTable.load') }}</th><th class="num">{{ t('overloadedTable.queue') }}</th><th class="num">p90</th><th class="num">{{ t('overloadedTable.refusals') }}</th><th></th></tr>
      </thead>
      <tbody>
        <tr v-for="item in shown()" :key="item.moCode + item.profileCode" class="clickable" @click="emit('organization', item.moCode)">
          <td class="org" :title="item.name">{{ shortOrgName(item.name) }} <span class="muted">· {{ item.moCode }}</span></td>
          <td class="num" :class="{ 'delta-up': item.load === null || item.load > 1 }">{{ loadLabel(item.load) }}</td>
          <td class="num">{{ item.queueLen }}</td>
          <td class="num" :class="{ 'delta-up': (item.queueAgeP90 ?? 0) > 60 }">{{ item.queueAgeP90?.toFixed(0) ?? '—' }}</td>
          <td class="num">{{ pct(item.refusalRate4w) }}</td>
          <td class="num"><button type="button" class="link-arrow small" @click.stop="emit('simulate', item)">{{ t('overloadedTable.toSimulator') }}</button></td>
        </tr>
      </tbody>
    </table>
  </div>
</template>

<style scoped>
.org { max-width: 360px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
</style>
