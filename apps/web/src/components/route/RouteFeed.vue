<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import StatusTag from '@/components/ui/StatusTag.vue'
import { shortOrgName } from '@/lib/format'
import { dateShort, type RouteEntry } from '@/lib/route'

/** Лента решений врача и сигналов гражданина, свежие первыми; формулировки — по аудитории. */
defineProps<{ entries: RouteEntry[]; audience: 'citizen' | 'doctor' }>()
const { t } = useI18n()
</script>

<template>
  <div class="rows" data-testid="route-decisions">
    <p v-if="entries.length === 0" class="muted">{{ t('route.noDecisions') }}</p>
    <div v-for="e in entries" :key="e.kind === 'decision' ? e.decision.decisionId : e.signal.decisionId" class="row feed-row">
      <div class="row-main">
        <i :class="e.kind === 'decision' ? 'pi pi-user' : 'pi pi-comment'" class="icon" aria-hidden="true" />
        <template v-if="e.kind === 'decision'">
          <span :title="e.decision.toMoName">{{ e.decision.kind === 'redirect' ? t('route.redirect', { name: shortOrgName(e.decision.toMoName) }) : t('route.keep') }}</span>
          <div class="row-sub">
            {{ dateShort(e.decision.recordedAt) }} · {{ t('decision.role.' + e.decision.role) }}<template v-if="e.decision.reason"> · «{{ e.decision.reason }}»</template>
            <template v-if="audience === 'doctor' && e.decision.severe"> · {{ t('route.severeFlag') }}</template>
          </div>
        </template>
        <template v-else>
          <span :title="e.signal.toMoName ?? undefined">{{ t((audience === 'doctor' ? 'route.patientSignal.' : 'route.signal.') + e.signal.kind, { name: shortOrgName(e.signal.toMoName) }) }}</span>
          <div class="row-sub">{{ dateShort(e.signal.recordedAt) }}<template v-if="e.signal.comment"> · «{{ e.signal.comment }}»</template></div>
        </template>
      </div>
      <div v-if="e.kind === 'signal' && e.signal.open" class="row-value"><StatusTag :value="t('route.awaitingDoctor')" tone="accent" /></div>
      <div v-else-if="e.kind === 'decision' && e.decision.patientConsent" class="row-value">
        <StatusTag :value="t('route.consentStatus.' + e.decision.patientConsent)" :tone="e.decision.patientConsent === 'accepted' ? 'ok' : e.decision.patientConsent === 'declined' ? 'neutral' : 'accent'" />
      </div>
    </div>
  </div>
</template>

<style scoped>
.feed-row { align-items: flex-start; }
.icon { color: var(--dm-muted); font-size: 0.8rem; margin-right: 6px; }
</style>
