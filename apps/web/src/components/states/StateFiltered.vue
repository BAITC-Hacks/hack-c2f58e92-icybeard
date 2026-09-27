<script setup lang="ts">
import Button from 'primevue/button'
import { useI18n } from 'vue-i18n'
import StateBlock from './StateBlock.vue'

/** Пусто по фильтру (W-States): «Ничего не найдено», подсказка, что снять, и «Сбросить фильтры». */
defineProps<{ hint?: string }>()
const emit = defineEmits<{ reset: [] }>()
const { t } = useI18n()
</script>

<template>
  <StateBlock icon="pi pi-filter" :title="t('states.filteredTitle')" :text="hint ?? t('states.filteredText')" data-testid="state-filtered">
    <Button :label="t('states.resetFilters')" severity="secondary" size="small" data-testid="reset-filters" @click="emit('reset')" />
  </StateBlock>
</template>
