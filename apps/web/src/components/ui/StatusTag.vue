<script setup lang="ts">
import type { StatusTone } from './tones'

/** Чип статуса (доска C-Tokens): radius 8, 12 / 500, letter-spacing 0.02em. Тона: neutral — inset/ink-2 («нет данных»),
 * ok — good («подтверждено», «в норме»), warn — attention («риск», «перегрузка»; янтарь), danger — critical («отказ»),
 * accent — selected/accent-hover («текущая»), info — info-soft/ink («приглашён», «ожидает»), ai — lavender,
 * bench — внешний ориентир. */
withDefaults(defineProps<{ value: string; tone?: StatusTone; icon?: string }>(), { tone: 'neutral' })
</script>

<template>
  <span class="status" :class="tone"><i v-if="icon" :class="icon" /> {{ value }}</span>
</template>

<style scoped>
.status { display: inline-flex; align-items: center; gap: 4px; font-size: var(--dm-text-xs); font-weight: 500; letter-spacing: 0.02em; line-height: 1.2; padding: 4px 10px; border-radius: var(--dm-radius-sm); white-space: nowrap; vertical-align: middle; }
.status i { font-size: 0.75rem; }
.status.neutral { background: var(--dm-neutral-soft); color: var(--dm-muted); }
.status.ok { background: var(--dm-ok-soft); color: var(--dm-ok); }
.status.warn { background: var(--dm-warn-soft); color: var(--dm-warn); }
.status.danger { background: var(--dm-danger-soft); color: var(--dm-danger); }
.status.accent { background: var(--dm-accent-soft); color: var(--dm-accent-hover); }
.status.info { background: var(--dm-info-soft); color: var(--dm-ink); }
.status.ai { background: var(--dm-ai-soft); color: var(--dm-ai); }
.status.bench { background: var(--dm-bench-soft); color: var(--dm-ink); }
</style>
