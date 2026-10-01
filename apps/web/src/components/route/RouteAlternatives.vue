<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import type { Alternative } from '@/api/types'
import StatusTag from '@/components/ui/StatusTag.vue'
import { days, shortOrgName } from '@/lib/format'
import { useRefdataStore } from '@/stores/refdata'

/** «Где быстрее» (route-new / doctor-route-patient-new): гражданину — плитки с рамкой --border-soft radius 14,
 * крупный срок 26/800 зелёным (--success-text), «быстрее на N дн.» и ghost-ссылка «Попросить рассмотреть».
 * Зелёная цифра — короче, чем `baselineDays` (текущая организация). Риск отказа гражданину не показывается (ТЗ §10.2).
 * У врача свой список с выбором — в карточке «Оставить или перевести» на странице пациента. */
const props = defineProps<{
  items: Alternative[]
  audience: 'citizen'
  /** код организации, для которой сейчас идёт отправка */
  acting: string | null
  /** открытая просьба гражданина — вместо кнопки чип */
  pendingCode?: string | null
  /** без кнопок (гость) */
  actionLabel?: string
  /** медиана текущей организации: короче неё — зелёная цифра и «быстрее на N дн.» */
  baselineDays?: number | null
}>()
const emit = defineEmits<{ act: [moCode: string] }>()
const { t } = useI18n()
const refdata = useRefdataStore()
/** Разница считается по тем же округлённым дням, что видны на экране (≈ 4 и ≈ 2 → «на 2 дн.»). */
const diff = (a: Alternative) => (props.baselineDays != null ? Math.round(props.baselineDays) - Math.round(a.p50Days) : null)
const faster = (a: Alternative) => (diff(a) ?? 0) > 0
const compare = (a: Alternative) => {
  const d = diff(a)
  if (d === null) return ''
  if (d > 0) return t('route.citizen.fasterThanYours', { days: d })
  if (d < 0) return t('route.citizen.slowerThanYours', { days: -d })
  return t('route.citizen.sameAsYours')
}
</script>

<template>
  <!-- гражданин: плитки как на доске route-new -->
  <div v-if="audience === 'citizen'" class="tiles">
    <p v-if="items.length === 0" class="muted">{{ t('doctor.referral.noAlternatives') }}</p>
    <div v-for="a in items" :key="a.mo.moCode" class="tile">
      <div class="tile-main">
        <span class="tile-name" :title="a.mo.name">{{ shortOrgName(a.mo.name) }}</span>
        <span class="tile-sub">
          <span class="mono">{{ a.mo.moCode }}</span>
          <template v-if="a.isNeighborRegion"> · {{ t('citizen.wait.neighborRegion', { region: refdata.regionName(a.mo.regionKato) }) }}</template>
        </span>
        <StatusTag v-if="pendingCode === a.mo.moCode" class="tile-action" :value="t('route.requestPending')" tone="accent" />
        <button v-else-if="actionLabel" type="button" class="ghost-link tile-action" :disabled="acting !== null" data-testid="request" @click="emit('act', a.mo.moCode)">{{ actionLabel }}</button>
      </div>
      <div class="tile-value" :class="{ faster: faster(a) }">
        <div class="tile-lead">{{ t('route.citizen.tileLead') }}</div>
        <div class="tile-days tabular">≈ {{ days(a.p50Days) }} <span class="unit">{{ t('common.days') }}</span></div>
        <div v-if="compare(a)" class="tile-faster">{{ compare(a) }}</div>
      </div>
    </div>
  </div>

</template>

<style scoped>
/* плитки гражданина */
.tiles { display: flex; flex-direction: column; gap: 10px; }
.tile { display: flex; align-items: center; justify-content: space-between; gap: 14px; padding: 14px 16px; border: 1px solid var(--border-soft); border-radius: var(--radius-xl); }
.tile-main { display: flex; flex-direction: column; align-items: flex-start; gap: 2px; min-width: 0; }
.tile-name { font-size: var(--fs-md); font-weight: var(--fw-bold); }
.tile-sub { font-size: var(--fs-sm); color: var(--text-muted); }
.tile-action { margin-top: 8px; }
.tile-value { text-align: right; flex: none; max-width: 46%; }
.tile-lead { font-size: var(--fs-sm); color: var(--text-muted); margin-bottom: 4px; line-height: 1.3; }
.tile-days { font-size: 26px; font-weight: var(--fw-black); line-height: 1; letter-spacing: -0.01em; }
.tile-days .unit { font-size: 14px; font-weight: var(--fw-bold); color: var(--text-muted); letter-spacing: 0; }
.tile-value.faster .tile-days { color: var(--success-text); }
.tile-value.faster .unit { color: var(--success-soft-text); }
.tile-faster { font-size: var(--fs-sm); color: var(--text-muted); margin-top: 3px; }
.ghost-link { border: 0; background: none; padding: 0; font: inherit; font-size: var(--fs-base-sm); font-weight: var(--fw-bold); color: var(--link); cursor: pointer; white-space: nowrap; }
.ghost-link:hover:not(:disabled) { color: var(--accent-strong); }
.ghost-link:disabled { opacity: 0.45; cursor: default; }

</style>
