<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { setLocale } from '@/i18n'

/** Переключатель языка — пилюля RU | KK (активный ink/белый): на ground белая (верхняя полоса), в сайдбаре — на soft.
 * mode="toggle" — одна кнопка с текущим языком (свёрнутый сайдбар). */
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
.locale { display: inline-flex; background: var(--dm-surface); border-radius: var(--dm-radius-pill); padding: 3px; font-size: var(--dm-text-xs); font-weight: 500; }
.locale.soft { background: var(--dm-surface-2); }
.opt { border: 0; background: transparent; color: var(--dm-muted); padding: 4px 10px; border-radius: var(--dm-radius-pill); font: inherit; cursor: pointer; line-height: 1.3; }
.opt.active { background: var(--dm-ink); color: var(--dm-surface); }
.locale-toggle { border: 0; background: var(--dm-surface-2); color: var(--dm-ink); font: inherit; font-size: var(--dm-text-xs); font-weight: 500; width: 36px; height: 36px; border-radius: 50%; cursor: pointer; }
</style>
