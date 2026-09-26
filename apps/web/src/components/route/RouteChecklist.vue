<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import type { RouteChecklistItem, RouteStandardRef } from '@/api/types'
import StatusTag from '@/components/ui/StatusTag.vue'
import { dateShort } from '@/lib/route'

/** Анализы по Стандарту: только названия и сроки действия (логистика документов), группами «истекли / действуют». */
const props = defineProps<{ items: RouteChecklistItem[]; standard: RouteStandardRef }>()
const { t } = useI18n()

const STATUS_ORDER: RouteChecklistItem['status'][] = ['expired', 'expiring', 'valid']
const TONES = { expired: 'danger', expiring: 'warn', valid: 'ok' } as const
const groups = computed(() =>
  STATUS_ORDER.map((status) => ({ status, items: props.items.filter((c) => c.status === status) })).filter((g) => g.items.length > 0),
)
</script>

<template>
  <div class="checklist">
    <p v-if="items.length === 0" class="muted">{{ t('common.empty') }}</p>
    <div v-for="g in groups" :key="g.status" class="group">
      <div class="group-title"><StatusTag :value="t('route.status.' + g.status)" :tone="TONES[g.status]" /> <span class="muted">· {{ g.items.length }}</span></div>
      <div class="rows">
        <div v-for="c in g.items" :key="c.code" class="row">
          <div class="row-main">{{ c.title }} <span class="row-sub">· {{ c.validityLabel }}</span></div>
          <div class="row-value muted">{{ t('route.validUntil', { date: dateShort(c.validUntil) }) }}</div>
        </div>
      </div>
    </div>
    <p class="muted small note">{{ t('route.checklistNote', { source: standard.source, date: dateShort(standard.sourceDate) }) }}</p>
  </div>
</template>

<style scoped>
.group + .group { margin-top: var(--dm-space-3); }
.group-title { margin-bottom: 4px; }
.note { margin: var(--dm-space-3) 0 0; }
</style>
