<script setup lang="ts">
/** Чип статуса «Тихой клиники»: radius 8, 12 / 500, letter-spacing 0.02em. Тона: neutral — soft/ink-2, ok — sage-wash/
 * sage-text, warn и danger — coral-wash/coral-text, accent — heal-wash/ink, bench — bench-wash/ink (внешний ориентир). */
withDefaults(defineProps<{ value: string; tone?: 'neutral' | 'ok' | 'warn' | 'danger' | 'accent' | 'bench'; icon?: string }>(), { tone: 'neutral' })
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
.status.accent { background: var(--dm-accent-soft); color: var(--dm-ink); }
.status.bench { background: var(--dm-bench-soft); color: var(--dm-ink); }
</style>
