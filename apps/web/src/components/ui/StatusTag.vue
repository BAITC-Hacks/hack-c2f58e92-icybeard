<script setup lang="ts">
/** Пилюля статуса в приглушённых тонах токенов — вместо PrimeVue Tag с насыщенными палитрами. */
withDefaults(defineProps<{ value: string; tone?: 'neutral' | 'ok' | 'warn' | 'danger' | 'accent'; icon?: string }>(), { tone: 'neutral' })
</script>

<template>
  <span class="status" :class="tone"><i v-if="icon" :class="icon" /> {{ value }}</span>
</template>

<style scoped>
.status { display: inline-flex; align-items: center; gap: 4px; font-size: 0.8rem; font-weight: 600; line-height: 1; padding: 5px 9px; border-radius: var(--dm-radius-pill); white-space: nowrap; vertical-align: middle; }
.status i { font-size: 0.75rem; }
.status.neutral { background: var(--dm-neutral-soft); color: var(--dm-muted); }
.status.ok { background: var(--dm-ok-soft); color: var(--dm-ok); }
.status.warn { background: var(--dm-warn-soft); color: var(--dm-warn); }
.status.danger { background: var(--dm-danger-soft); color: var(--dm-danger); }
.status.accent { background: var(--dm-accent-soft); color: var(--dm-accent); }
</style>
