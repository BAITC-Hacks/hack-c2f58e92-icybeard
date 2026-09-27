<script setup lang="ts">
import Select from 'primevue/select'
import { computed } from 'vue'

/** Фильтр-пилюля досок администрирования: белая пилюля 36 px «Роль: все ⌄»; с `searchable` — поиск по опциям
 * (организации). `locked` — фильтр зафиксирован (scope own: своя организация). */
export interface FilterOption { value: string; label: string }
const props = defineProps<{ label: string; options: FilterOption[]; allLabel: string; searchable?: boolean; locked?: boolean; testid?: string }>()
const model = defineModel<string | null>({ default: null })
const items = computed<FilterOption[]>(() => [{ value: '', label: props.allLabel }, ...props.options])
const current = computed(() => props.options.find((o) => o.value === model.value)?.label ?? props.allLabel)
const value = computed({ get: () => model.value ?? '', set: (v: string) => (model.value = v || null) })
</script>

<template>
  <Select v-model="value" :options="items" option-label="label" option-value="value" :filter="searchable" auto-filter-focus :disabled="locked" class="filter-pill" :class="{ locked }" :data-testid="testid">
    <template #value><span class="pill-value">{{ label }}: <span class="pill-current">{{ current }}</span></span></template>
  </Select>
</template>

<style scoped>
.filter-pill { background: var(--dm-surface) !important; border-radius: var(--dm-radius-pill) !important; min-height: 36px; max-width: 320px; }
.filter-pill :deep(.p-select-label) { padding: 6px 2px 6px 16px; font-size: var(--dm-text-sm); font-weight: 500; }
.filter-pill :deep(.p-select-dropdown) { width: 30px; padding-right: 6px; }
.filter-pill :deep(.p-select-dropdown svg) { width: 11px; height: 11px; }
.filter-pill.locked { opacity: 1; }
.pill-value { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; display: block; }
.pill-current { font-weight: 500; }
</style>
