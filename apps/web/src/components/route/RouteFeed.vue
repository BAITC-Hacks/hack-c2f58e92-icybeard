<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import StatusTag from '@/components/ui/StatusTag.vue'
import { dateTime, shortOrgName } from '@/lib/format'
import type { RouteEntry } from '@/lib/route'

/** Лента решений врача и сигналов гражданина, свежие первыми; формулировки — по аудитории. Каждая запись — лента
 * событий: значок (перевод, оставлен, запрос пациента), заголовок, дата со временем и кто, ниже — причина врача или
 * комментарий пациента отдельной плашкой; справа статус (согласие пациента, «ждёт ответа врача»). */
defineProps<{ entries: RouteEntry[]; audience: 'citizen' | 'doctor' }>()
const { t } = useI18n()

function icon(e: RouteEntry): string {
  if (e.kind === 'signal') return 'pi-comment'
  return e.decision.kind === 'redirect' ? 'pi-arrow-right-arrow-left' : 'pi-check'
}
function tone(e: RouteEntry): string {
  if (e.kind === 'signal') return 'signal'
  return e.decision.kind === 'redirect' ? 'redirect' : 'keep'
}
</script>

<template>
  <ol class="feed" data-testid="route-decisions">
    <p v-if="entries.length === 0" class="muted">{{ t('route.noDecisions') }}</p>
    <li v-for="e in entries" :key="e.kind === 'decision' ? e.decision.decisionId : e.signal.decisionId" class="entry">
      <span class="dot" :class="tone(e)" aria-hidden="true"><i class="pi" :class="icon(e)" /></span>
      <div class="body">
        <div class="head">
          <template v-if="e.kind === 'decision'">
            <span class="title" :title="e.decision.toMoName">{{ e.decision.kind === 'redirect' ? t('route.redirect', { name: shortOrgName(e.decision.toMoName) }) : t('route.keep') }}</span>
          </template>
          <span v-else class="title" :title="e.signal.toMoName ?? undefined">{{ t((audience === 'doctor' ? 'route.patientSignal.' : 'route.signal.') + e.signal.kind, { name: shortOrgName(e.signal.toMoName) }) }}</span>
          <StatusTag v-if="e.kind === 'signal' && e.signal.open" :value="t('route.awaitingDoctor')" tone="accent" />
          <StatusTag v-else-if="e.kind === 'decision' && e.decision.patientConsent" :value="t('route.consentStatus.' + e.decision.patientConsent)"
            :tone="e.decision.patientConsent === 'accepted' ? 'ok' : e.decision.patientConsent === 'declined' ? 'neutral' : 'accent'" />
        </div>
        <div class="meta">
          {{ dateTime(e.kind === 'decision' ? e.decision.recordedAt : e.signal.recordedAt) }} ·
          {{ e.kind === 'decision' ? t('decision.role.' + e.decision.role) : audience === 'doctor' ? t('route.feed.patient') : t('route.feed.you') }}
          <template v-if="audience === 'doctor' && e.kind === 'decision' && e.decision.severe"> · <span class="severe">{{ t('route.severeFlag') }}</span></template>
        </div>
        <p v-if="e.kind === 'decision' && e.decision.reason" class="note"><span class="note-label">{{ t('route.feed.reason') }}</span>{{ e.decision.reason }}</p>
        <p v-else-if="e.kind === 'signal' && e.signal.comment" class="note"><span class="note-label">{{ audience === 'doctor' ? t('route.feed.patientComment') : t('route.feed.yourComment') }}</span>{{ e.signal.comment }}</p>
      </div>
    </li>
  </ol>
</template>

<style scoped>
.feed { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; }
.entry { display: flex; gap: 12px; padding: 12px 0; border-bottom: 1px solid var(--border-soft); }
.entry:last-child { border-bottom: 0; }
.dot { width: 30px; height: 30px; flex: none; border-radius: 50%; display: grid; place-items: center; font-size: 12px; background: var(--surface-muted); color: var(--text-secondary); }
.dot.redirect { background: var(--accent-subtle); color: var(--accent-strong); }
.dot.keep { background: var(--success-bg); color: var(--success-text); }
.dot.signal { background: var(--warning-bg); color: var(--warning-text); }
.body { display: flex; flex-direction: column; gap: 3px; min-width: 0; flex: 1; }
.head { display: flex; align-items: flex-start; justify-content: space-between; gap: 10px; }
.title { font-size: var(--fs-base); font-weight: var(--fw-semibold); line-height: 1.4; }
.meta { font-size: var(--fs-sm); color: var(--text-muted); }
.severe { color: var(--danger-text); font-weight: var(--fw-semibold); }
.note { margin: 4px 0 0; padding: 8px 12px; border-radius: var(--radius-md); background: var(--surface-muted); font-size: var(--fs-base-sm); line-height: 1.45; overflow-wrap: anywhere; }
.note-label { display: block; font-size: var(--fs-xs); font-weight: var(--fw-bold); color: var(--text-muted); margin-bottom: 2px; }
</style>
