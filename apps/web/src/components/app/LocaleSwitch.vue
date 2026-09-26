<script setup lang="ts">
import Button from 'primevue/button'
import SelectButton from 'primevue/selectbutton'
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { setLocale } from '@/i18n'

/** Переключатель языка: segment — две кнопки RU | KK; toggle — одна кнопка с текущим языком (свёрнутый сайдбар). */
withDefaults(defineProps<{ mode?: 'segment' | 'toggle' }>(), { mode: 'segment' })
const { locale } = useI18n()
const options = [
  { label: 'RU', value: 'ru' },
  { label: 'KK', value: 'kk' },
]
const other = computed<'ru' | 'kk'>(() => (locale.value === 'kk' ? 'ru' : 'kk'))

function onLocale(value: 'ru' | 'kk' | null) {
  if (value) setLocale(value)
}
</script>

<template>
  <Button
    v-if="mode === 'toggle'"
    :label="locale === 'kk' ? 'KK' : 'RU'"
    :title="other === 'kk' ? 'Қазақша' : 'Русский'"
    size="small"
    severity="secondary"
    text
    data-testid="locale-switch"
    @click="onLocale(other)"
  />
  <SelectButton
    v-else
    :model-value="locale"
    :options="options"
    option-label="label"
    option-value="value"
    size="small"
    :allow-empty="false"
    data-testid="locale-switch"
    @update:model-value="onLocale"
  />
</template>
