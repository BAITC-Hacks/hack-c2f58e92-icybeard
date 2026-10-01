<script setup lang="ts">
/** Общая раскладка состояний экрана (states-new): иконка в круге 48 px, заголовок 16 / 800, одна-две строки
 * --text-secondary и действия. Тон круга: neutral — --surface-muted, warn — внимание (ошибка загрузки),
 * info и accent — --accent-soft/--accent-strong (данные устарели), danger — «нет доступа» на отдельной странице. */
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
.state-icon { width: 48px; height: 48px; border-radius: 50%; display: grid; place-items: center; background: var(--surface-muted); color: var(--text-secondary); margin-bottom: 8px; }
.state.compact .state-icon { width: 40px; height: 40px; margin-bottom: 4px; }
.state-icon.warn { background: var(--warning-bg); color: var(--warning-text); }
.state-icon.info { background: var(--accent-soft); color: var(--accent-strong); }
.state-icon.accent { background: var(--accent-soft); color: var(--accent-strong); }
.state-icon.danger { background: var(--danger-bg); color: var(--danger-text); }
.state-title { font-size: var(--fs-lg); font-weight: var(--fw-extrabold); color: var(--text); line-height: 1.35; }
.state-text { margin: 0; max-width: 52ch; font-size: 14px; color: var(--text-secondary); line-height: 1.5; }
.state-actions { display: flex; flex-wrap: wrap; gap: 16px; align-items: center; justify-content: center; margin-top: 8px; }
</style>
