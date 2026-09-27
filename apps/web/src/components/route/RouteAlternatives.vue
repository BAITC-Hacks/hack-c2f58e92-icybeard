<script setup lang="ts">
import Button from 'primevue/button'
import { useI18n } from 'vue-i18n'
import type { Alternative } from '@/api/types'
import StatusTag from '@/components/ui/StatusTag.vue'
import { days, pct, shortOrgName } from '@/lib/format'
import { useRefdataStore } from '@/stores/refdata'

/** «Где быстрее»: строки организаций с числом справа. Врачу — ещё p90 и риск отказа и кнопка «Направить»,
 * гражданину — «Попросить» (или чип «запрос отправлен»). Риск отказа гражданину не показывается (ТЗ §10.2). */
defineProps<{
  items: Alternative[]
  audience: 'citizen' | 'doctor'
  /** код организации, для которой сейчас идёт отправка */
  acting: string | null
  /** открытая просьба гражданина — вместо кнопки чип */
  pendingCode?: string | null
  /** без кнопок (гость) */
  actionLabel?: string
}>()
const emit = defineEmits<{ act: [moCode: string] }>()
const { t } = useI18n()
const refdata = useRefdataStore()
</script>

<template>
  <div class="rows">
    <p v-if="items.length === 0" class="muted">{{ t('doctor.referral.noAlternatives') }}</p>
    <div v-for="a in items" :key="a.mo.moCode" class="row">
      <div class="row-main">
        <span :title="a.mo.name">{{ shortOrgName(a.mo.name) }}</span>
        <div class="row-sub">
          <span class="mono">{{ a.mo.moCode }}</span>
          <template v-if="a.isNeighborRegion"> · {{ t('citizen.wait.neighborRegion', { region: refdata.regionName(a.mo.regionKato) }) }}</template>
          <template v-if="audience === 'doctor'"> · p90 {{ days(a.p90Days) }} {{ t('common.days') }} · {{ t('doctor.referral.refusalShort') }} {{ pct(a.pRefusal) }}</template>
        </div>
      </div>
      <div class="row-value">
        <span class="wait">≈ {{ days(a.p50Days) }} {{ t('common.days') }}</span>
        <StatusTag v-if="pendingCode === a.mo.moCode" :value="t('route.requestPending')" tone="accent" />
        <Button v-else-if="actionLabel" :label="actionLabel" size="small" severity="secondary" :loading="acting === a.mo.moCode" :disabled="acting !== null" :data-testid="audience === 'doctor' ? 'redirect' : 'request'" @click="emit('act', a.mo.moCode)" />
      </div>
    </div>
  </div>
</template>

<style scoped>
.wait { font-weight: 500; min-width: 5ch; text-align: right; }
</style>
