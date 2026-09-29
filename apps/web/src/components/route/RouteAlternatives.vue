<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import type { Alternative } from '@/api/types'
import StatusTag from '@/components/ui/StatusTag.vue'
import { days, pct, shortOrgName } from '@/lib/format'
import { useRefdataStore } from '@/stores/refdata'

/** «Где быстрее» (route-new / doctor-route-patient-new): гражданину — плитки с рамкой --border-soft radius 14,
 * крупный срок 26/800 зелёным (--success-text), «быстрее на N дн.» и ghost-ссылка «Попросить рассмотреть»;
 * врачу — строки с p90 и риском отказа, срок зелёным, mini-кнопка «Направить сюда». Зелёная цифра — короче,
 * чем `baselineDays` (текущая организация). Риск отказа гражданину не показывается (ТЗ §10.2). */
const props = defineProps<{
  items: Alternative[]
  audience: 'citizen' | 'doctor'
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
const faster = (a: Alternative) => props.baselineDays != null && a.p50Days < props.baselineDays
const fasterBy = (a: Alternative) => (props.baselineDays != null ? Math.round(props.baselineDays - a.p50Days) : 0)
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
        <div class="tile-days tabular">≈ {{ days(a.p50Days) }} <span class="unit">{{ t('common.days') }}</span></div>
        <div v-if="faster(a)" class="tile-faster">{{ t('route.fasterBy', { days: fasterBy(a) }) }}</div>
      </div>
    </div>
  </div>

  <!-- врач: строки со сроком, p90 и риском отказа -->
  <div v-else class="rows">
    <p v-if="items.length === 0" class="muted">{{ t('doctor.referral.noAlternatives') }}</p>
    <div v-for="a in items" :key="a.mo.moCode" class="row">
      <div class="row-main">
        <span :title="a.mo.name">{{ shortOrgName(a.mo.name) }}</span>
        <div class="row-sub">
          <span class="mono">{{ a.mo.moCode }}</span>
          <template v-if="a.isNeighborRegion"> · {{ t('citizen.wait.neighborRegion', { region: refdata.regionName(a.mo.regionKato) }) }}</template>
          · p90 {{ days(a.p90Days) }} {{ t('common.days') }} · {{ t('doctor.referral.refusalShort') }} {{ pct(a.pRefusal) }}
        </div>
      </div>
      <div class="row-value">
        <span class="wait tabular" :class="{ faster: faster(a) }">≈ {{ days(a.p50Days) }} {{ t('common.days') }}</span>
        <StatusTag v-if="pendingCode === a.mo.moCode" :value="t('route.requestPending')" tone="accent" />
        <button v-else-if="actionLabel" type="button" class="mini-btn" :disabled="acting !== null" data-testid="redirect" @click="emit('act', a.mo.moCode)">
          <i v-if="acting === a.mo.moCode" class="pi pi-spinner pi-spin" aria-hidden="true" />{{ actionLabel }}
        </button>
      </div>
    </div>
  </div>
</template>

<style scoped>
/* плитки гражданина */
.tiles { display: flex; flex-direction: column; gap: 10px; }
.tile { display: flex; align-items: center; justify-content: space-between; gap: 14px; padding: 14px 16px; border: 1px solid var(--border-soft); border-radius: var(--radius-xl); }
.tile-main { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
.tile-name { font-size: var(--fs-md); font-weight: var(--fw-bold); }
.tile-sub { font-size: var(--fs-sm); color: var(--text-muted); }
.tile-action { margin-top: 6px; align-self: flex-start; }
.tile-value { text-align: right; flex: none; }
.tile-days { font-size: 26px; font-weight: var(--fw-black); line-height: 1; letter-spacing: -0.01em; }
.tile-days .unit { font-size: 13px; font-weight: var(--fw-bold); color: var(--text-muted); letter-spacing: 0; }
.tile-value.faster .tile-days { color: var(--success-text); }
.tile-value.faster .unit { color: var(--success-soft-text); }
.tile-faster { font-size: var(--fs-sm); font-weight: var(--fw-bold); color: var(--success-text); margin-top: 3px; }
.ghost-link { border: 0; background: none; padding: 0; font: inherit; font-size: var(--fs-base-sm); font-weight: var(--fw-bold); color: var(--link); cursor: pointer; white-space: nowrap; }
.ghost-link:hover:not(:disabled) { color: var(--accent-strong); }
.ghost-link:disabled { opacity: 0.45; cursor: default; }

/* строки врача */
.wait { font-weight: var(--fw-extrabold); min-width: 5ch; text-align: right; }
.wait.faster { color: var(--success-text); }
.mini-btn { display: inline-flex; align-items: center; gap: 6px; background: var(--surface); color: var(--accent-strong); border: 1.5px solid var(--accent-line); border-radius: var(--radius-pill); padding: 5px 12px; font: inherit; font-size: var(--fs-xs); font-weight: var(--fw-bold); cursor: pointer; white-space: nowrap; }
.mini-btn:hover:not(:disabled) { background: var(--accent-subtle); }
.mini-btn:disabled { opacity: 0.45; cursor: default; }
.mini-btn i { font-size: 0.7rem; }
</style>
