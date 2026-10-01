<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import type { RouteChecklistItem, RouteStandardRef } from '@/api/types'
import { dateShort } from '@/lib/route'

/** Анализы по Стандарту: только названия и сроки действия (логистика документов). Группы оформлены как понятные
 * блоки для любого читателя: цветная полоса слева, значок и фраза «что это значит» вместо короткого тега,
 * у каждого анализа — прямая дата «истёк …» или «действует до …». */
const props = defineProps<{ items: RouteChecklistItem[]; standard: RouteStandardRef }>()
const { t } = useI18n()

const STATUS_ORDER: RouteChecklistItem['status'][] = ['expired', 'expiring', 'valid']
const ICONS = { expired: 'pi pi-exclamation-circle', expiring: 'pi pi-clock', valid: 'pi pi-check-circle' } as const
const groups = computed(() =>
  STATUS_ORDER.map((status) => ({ status, items: props.items.filter((c) => c.status === status) })).filter((g) => g.items.length > 0),
)
const dateLabel = (c: RouteChecklistItem) =>
  t(c.status === 'expired' ? 'route.checklistGroup.expiredOn' : 'route.checklistGroup.validTill', { date: dateShort(c.validUntil) })
</script>

<template>
  <div class="checklist">
    <p v-if="items.length === 0" class="muted">{{ t('common.empty') }}</p>
    <section v-for="g in groups" :key="g.status" class="group" :class="g.status">
      <header class="group-head">
        <i :class="ICONS[g.status]" aria-hidden="true" />
        <div class="group-text">
          <span class="group-title">{{ t(`route.checklistGroup.${g.status}.title`) }}</span>
          <span class="group-hint">{{ t(`route.checklistGroup.${g.status}.hint`) }}</span>
        </div>
        <span class="group-count tabular">{{ t('route.checklistGroup.count', { n: g.items.length }) }}</span>
      </header>
      <ul class="items">
        <li v-for="c in g.items" :key="c.code" class="item">
          <div class="item-main">
            <span class="item-title">{{ c.title }}</span>
            <span class="item-sub">{{ t('route.checklistGroup.validity', { label: c.validityLabel }) }}</span>
          </div>
          <span class="item-date tabular">{{ dateLabel(c) }}</span>
        </li>
      </ul>
    </section>
    <p class="muted small note">{{ t('route.checklistNote', { source: standard.source, date: dateShort(standard.sourceDate) }) }}</p>
  </div>
</template>

<style scoped>
.checklist { display: flex; flex-direction: column; gap: 14px; }
.group { border: 1px solid var(--border-soft); border-left-width: 4px; border-radius: var(--radius-lg); background: var(--surface); overflow: hidden; }
.group.expired { border-left-color: var(--danger-text); }
.group.expiring { border-left-color: var(--warning-strong); }
.group.valid { border-left-color: var(--success-text); }
.group-head { display: flex; align-items: center; gap: 12px; padding: 14px 18px; border-bottom: 1px solid var(--border-soft); }
.group.expired .group-head { background: var(--danger-bg); }
.group.expiring .group-head { background: var(--warning-bg); }
.group.valid .group-head { background: var(--success-bg); }
.group-head i { font-size: 1.25rem; }
.group.expired .group-head i, .group.expired .group-title { color: var(--danger-text); }
.group.expiring .group-head i, .group.expiring .group-title { color: var(--warning-text); }
.group.valid .group-head i, .group.valid .group-title { color: var(--success-text); }
.group-text { display: flex; flex-direction: column; gap: 2px; flex: 1; min-width: 0; }
.group-title { font-size: 16px; font-weight: var(--fw-extrabold); }
.group-hint { font-size: var(--fs-base); color: var(--text); }
.group-count { font-size: var(--fs-base); font-weight: var(--fw-bold); color: var(--text); white-space: nowrap; }
.items { list-style: none; margin: 0; padding: 0 18px; }
.item { display: flex; align-items: center; justify-content: space-between; gap: 16px; padding: 12px 0; border-bottom: 1px solid var(--border-soft); }
.item:last-child { border-bottom: 0; }
.item-main { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
.item-title { font-size: 15px; font-weight: var(--fw-semibold); color: var(--text); line-height: 1.35; }
.item-sub { font-size: var(--fs-sm); color: var(--text-muted); }
.item-date { font-size: var(--fs-base); font-weight: var(--fw-bold); white-space: nowrap; color: var(--text); }
.group.expired .item-date { color: var(--danger-text); }
.note { margin: 2px 0 0; line-height: 1.5; }
@media (max-width: 640px) { .item { flex-direction: column; align-items: flex-start; gap: 4px; } }
</style>
