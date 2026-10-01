<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import type { RouteJournalEntry, RouteJournalKind } from '@/api/types'
import { dateTime, shortOrgName } from '@/lib/format'
import { dateShort } from '@/lib/route'

/** Хроника маршрута из журнала (RouteDto.journal), свежие первыми: что сделали люди — запросы и ответы пациента,
 * решения врача, ответы принимающей больницы. Формулировки — по аудитории; у каждой записи значок, кто и когда,
 * ниже причина или комментарий отдельной плашкой и назначенная дата, если она есть. */
defineProps<{ entries: RouteJournalEntry[]; audience: 'citizen' | 'doctor' }>()
const { t } = useI18n()

const CITIZEN_KINDS = new Set<RouteJournalKind>(['request', 'prefer_current', 'still_waiting', 'withdraw', 'treated_elsewhere', 'consent_accepted', 'consent_declined'])
const ICONS: Partial<Record<RouteJournalKind, string>> = {
  redirect: 'pi-arrow-right-arrow-left', keep: 'pi-check', confirm: 'pi-calendar', reschedule: 'pi-calendar', admit: 'pi-building', discharge: 'pi-sign-out',
  reject: 'pi-times', cancel: 'pi-times', no_show: 'pi-times', close: 'pi-flag', consent_accepted: 'pi-thumbs-up', consent_declined: 'pi-thumbs-down',
}

function byCitizen(e: RouteJournalEntry) {
  return CITIZEN_KINDS.has(e.kind)
}
function tone(e: RouteJournalEntry): string {
  if (byCitizen(e)) return 'signal'
  if (e.kind === 'reject' || e.kind === 'cancel' || e.kind === 'no_show') return 'stop'
  if (e.kind === 'keep' || e.kind === 'confirm' || e.kind === 'admit' || e.kind === 'discharge') return 'keep'
  return 'redirect'
}
function who(e: RouteJournalEntry, audience: 'citizen' | 'doctor') {
  if (byCitizen(e)) return audience === 'doctor' ? t('route.feed.patient') : t('route.feed.you')
  return t('decision.role.' + e.role)
}
function noteLabel(e: RouteJournalEntry, audience: 'citizen' | 'doctor') {
  if (!byCitizen(e)) return t('route.feed.reason')
  return audience === 'doctor' ? t('route.feed.patientComment') : t('route.feed.yourComment')
}
</script>

<template>
  <ol class="feed" data-testid="route-decisions">
    <p v-if="entries.length === 0" class="muted">{{ t('route.noDecisions') }}</p>
    <li v-for="e in entries" :key="e.id" class="entry" :data-kind="e.kind">
      <span class="dot" :class="tone(e)" aria-hidden="true"><i class="pi" :class="ICONS[e.kind] ?? 'pi-comment'" /></span>
      <div class="body">
        <span class="title" :title="e.moName ?? undefined">{{ t(`route.journal.${audience}.${e.kind}`, { name: shortOrgName(e.moName) }) }}</span>
        <div class="meta">
          {{ dateTime(e.at) }} · {{ who(e, audience) }}
          <template v-if="audience === 'doctor' && e.severe"> · <span class="severe">{{ t('route.severeFlag') }}</span></template>
        </div>
        <p v-if="e.plannedAt" class="planned">{{ t('route.journal.planned', { date: dateShort(e.plannedAt) }) }}</p>
        <p v-if="e.reason" class="note"><span class="note-label">{{ noteLabel(e, audience) }}</span>{{ e.reason }}</p>
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
.dot.stop { background: var(--surface-muted); color: var(--text-secondary); }
.body { display: flex; flex-direction: column; gap: 3px; min-width: 0; flex: 1; }
.title { font-size: var(--fs-base); font-weight: var(--fw-semibold); line-height: 1.4; }
.meta { font-size: var(--fs-sm); color: var(--text-muted); }
.severe { color: var(--danger-text); font-weight: var(--fw-semibold); }
.planned { margin: 2px 0 0; font-size: var(--fs-base-sm); font-weight: var(--fw-semibold); }
.note { margin: 4px 0 0; padding: 8px 12px; border-radius: var(--radius-md); background: var(--surface-muted); font-size: var(--fs-base-sm); line-height: 1.45; overflow-wrap: anywhere; }
.note-label { display: block; font-size: var(--fs-xs); font-weight: var(--fw-bold); color: var(--text-muted); margin-bottom: 2px; }
</style>
