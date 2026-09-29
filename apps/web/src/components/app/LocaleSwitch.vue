<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { setLocale } from '@/i18n'

/** Переключатель языка — пилюля RU | KK: трек --surface-muted, активный — синий --accent с белым текстом.
 * mode="toggle" — одна кнопка с текущим языком (свёрнутый сайдбар). Проп surface оставлен для прежних вызовов. */
withDefaults(defineProps<{ mode?: 'segment' | 'toggle'; surface?: 'white' | 'soft' }>(), { mode: 'segment', surface: 'white' })
const { locale } = useI18n()
const options = [
  { label: 'RU', value: 'ru', title: 'Русский' },
  { label: 'KK', value: 'kk', title: 'Қазақша' },
] as const
const other = computed<'ru' | 'kk'>(() => (locale.value === 'kk' ? 'ru' : 'kk'))
</script>

<template>
  <button v-if="mode === 'toggle'" type="button" class="locale-toggle" :title="other === 'kk' ? 'Қазақша' : 'Русский'" data-testid="locale-switch" @click="setLocale(other)">
    {{ locale === 'kk' ? 'KK' : 'RU' }}
  </button>
  <div v-else class="locale" :class="surface" role="group" data-testid="locale-switch">
    <button v-for="o in options" :key="o.value" type="button" class="opt" :class="{ active: locale === o.value }" :title="o.title" :aria-pressed="locale === o.value" @click="setLocale(o.value)">
      {{ o.label }}
    </button>
  </div>
</template>

<style scoped>
.locale { display: inline-flex; background: var(--surface-muted); border-radius: var(--radius-pill); padding: 3px; font-size: var(--fs-xs); font-weight: var(--fw-bold); }
.locale.soft { background: var(--surface-muted); }
.opt { border: 0; background: transparent; color: var(--text-muted); padding: 4px 10px; border-radius: var(--radius-pill); font: inherit; cursor: pointer; line-height: 1.3; }
.opt.active { background: var(--accent); color: var(--text-on-accent); }
.locale-toggle { border: 0; background: var(--surface-muted); color: var(--text); font: inherit; font-size: var(--fs-xs); font-weight: var(--fw-bold); width: 36px; height: 36px; border-radius: 50%; cursor: pointer; }
</style>
