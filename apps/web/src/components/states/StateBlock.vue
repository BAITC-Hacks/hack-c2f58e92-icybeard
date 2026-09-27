<script setup lang="ts">
/** Общая раскладка состояний экрана (W-States): иконка в круге 48 px, заголовок 17 / 500, одна-две строки ink-2 и
 * действия. Тон круга: neutral — inset, warn — attention (ошибка), info — info-soft (данные устарели), accent — selected. */
withDefaults(defineProps<{ icon: string; title: string; text?: string; tone?: 'neutral' | 'warn' | 'info' | 'accent' | 'danger'; compact?: boolean }>(), { tone: 'neutral' })
</script>

<template>
  <div class="state" :class="{ compact }" role="status">
    <span class="state-icon" :class="tone" aria-hidden="true"><i :class="icon" /></span>
    <div class="state-title">{{ title }}</div>
    <p v-if="text" class="state-text">{{ text }}</p>
    <slot name="text" />
    <div v-if="$slots.default" class="state-actions"><slot /></div>
  </div>
</template>

<style scoped>
.state { display: flex; flex-direction: column; align-items: center; text-align: center; gap: 8px; padding: 40px 16px; }
.state.compact { padding: 20px 12px; }
.state-icon { width: 48px; height: 48px; border-radius: 50%; display: grid; place-items: center; background: var(--dm-neutral-soft); color: var(--dm-ink); margin-bottom: 8px; }
.state.compact .state-icon { width: 40px; height: 40px; margin-bottom: 4px; }
.state-icon.warn { background: var(--dm-warn-soft); color: var(--dm-warn); }
.state-icon.info { background: var(--dm-info-soft); color: var(--dm-info); }
.state-icon.accent { background: var(--dm-accent-soft); color: var(--dm-accent-hover); }
.state-icon.danger { background: var(--dm-danger-soft); color: var(--dm-danger); }
.state-title { font-size: var(--dm-text-base); font-weight: 500; color: var(--dm-ink); }
.state-text { margin: 0; max-width: 52ch; font-size: var(--dm-text-sm); color: var(--dm-muted); }
.state-actions { display: flex; flex-wrap: wrap; gap: 16px; align-items: center; justify-content: center; margin-top: 8px; }
</style>
