<script setup lang="ts">
import type { StatusTone } from './tones'

/** Чип статуса (components.md «Бейджи и метки»): radius 8, 11 / 700. Тона: neutral — surface-sunken/text-secondary
 * («нет данных»), ok — успех («подтверждено», «в норме»), warn — внимание («есть сигнал»; янтарь), danger — ошибка
 * («риск отказа», «истёк»), accent и info — инфо (--accent-soft/--accent-strong: «в очереди», «ожидает», роль),
 * ai и bench — бывшие лавандовый «AI» и бирюзовый ориентир, теперь нейтральная пилюля surface-muted/text-secondary. */
withDefaults(defineProps<{ value: string; tone?: StatusTone; icon?: string }>(), { tone: 'neutral' })
</script>

<template>
  <span class="status" :class="tone"><i v-if="icon" :class="icon" /> {{ value }}</span>
</template>

<style scoped>
.status { display: inline-flex; align-items: center; gap: 4px; font-size: var(--fs-xs); font-weight: var(--fw-bold); letter-spacing: 0.01em; line-height: 1.2; padding: 4px 9px; border-radius: var(--radius-sm); white-space: nowrap; vertical-align: middle; }
.status i { font-size: 0.75rem; }
.status.neutral { background: var(--surface-sunken); color: var(--text-secondary); }
.status.ok { background: var(--success-bg); color: var(--success-text); }
.status.warn { background: var(--warning-bg); color: var(--warning-text); }
.status.danger { background: var(--danger-bg); color: var(--danger-text); }
.status.accent { background: var(--accent-soft); color: var(--accent-strong); }
.status.info { background: var(--accent-soft); color: var(--accent-strong); }
.status.ai { background: var(--surface-muted); color: var(--text-secondary); }
.status.bench { background: var(--surface-muted); color: var(--text-secondary); }
</style>
