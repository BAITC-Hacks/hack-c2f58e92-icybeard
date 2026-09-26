<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import type { RouteHistoryItem } from '@/api/types'
import StatusTag from '@/components/ui/StatusTag.vue'
import { shortOrgName } from '@/lib/format'
import { dateShort } from '@/lib/route'

/** Прошлые направления: дата · профиль · организация, справа исход и сколько ждал. */
defineProps<{ items: RouteHistoryItem[] }>()
const { t } = useI18n()
</script>

<template>
  <div class="rows">
    <p v-if="items.length === 0" class="muted">{{ t('common.empty') }}</p>
    <div v-for="h in items" :key="h.registeredAt + h.moCode" class="row">
      <div class="row-main">
        <span class="tabular">{{ dateShort(h.registeredAt) }}</span> · {{ h.profileName }}
        <div class="row-sub" :title="h.moName">{{ shortOrgName(h.moName) }}</div>
      </div>
      <div class="row-value">
        <StatusTag :value="t('route.outcome.' + h.outcome)" :tone="h.outcome === 'hospitalized' ? 'ok' : 'danger'" />
        <span class="muted small">{{ t('route.waited', { days: h.waitDays }) }}</span>
      </div>
    </div>
  </div>
</template>
