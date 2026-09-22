<script setup lang="ts">
import SelectButton from 'primevue/selectbutton'
import { useI18n } from 'vue-i18n'
import { setLocale } from '@/i18n'

const { locale } = useI18n()
const options = [
  { label: 'RU', value: 'ru' },
  { label: 'KK', value: 'kk' },
]

function onLocale(value: 'ru' | 'kk' | null) {
  if (value) setLocale(value)
}
</script>

<template>
  <SelectButton
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
