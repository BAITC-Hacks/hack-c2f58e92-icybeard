<script setup lang="ts" generic="T extends object">
import Select from 'primevue/select'
import { computed } from 'vue'

/** Селект с поиском для длинных списков (регионы, профили, организации, МНН). Подпись опции — поле или функция;
 * `optionTitle` даёт полный текст в title (например, полное юридическое имя при коротком в списке). */
const props = defineProps<{
  options: T[]
  optionLabel: keyof T | ((option: T) => string)
  optionValue: keyof T
  optionTitle?: (option: T) => string
  placeholder?: string
  disabled?: boolean
  loading?: boolean
  showClear?: boolean
  size?: 'small' | 'large'
  emptyMessage?: string
}>()
const model = defineModel<string | null>({ default: null })

const label = computed(() => (option: T) => (typeof props.optionLabel === 'function' ? props.optionLabel(option) : String(option[props.optionLabel] ?? '')))
</script>

<template>
  <Select
    v-model="model"
    :options="options"
    :option-label="label"
    :option-value="String(optionValue)"
    :placeholder="placeholder"
    :disabled="disabled"
    :loading="loading"
    :show-clear="showClear"
    :size="size"
    :empty-message="emptyMessage"
    filter
    auto-filter-focus
    class="search-select"
  >
    <template #option="{ option }">
      <span class="option" :title="optionTitle ? optionTitle(option) : undefined">{{ label(option) }}</span>
    </template>
  </Select>
</template>

<style scoped>
.search-select { width: 100%; }
.option { white-space: normal; }
</style>
