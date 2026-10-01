<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'

/** Листание короткого списка внутри карточки: «1–8 из 12» и стрелки влево/вправо. Скрыто, если всё влезает. */
const props = defineProps<{ total: number; size: number }>()
const page = defineModel<number>('page', { required: true })
const { t } = useI18n()
const pages = computed(() => Math.max(1, Math.ceil(props.total / props.size)))
const from = computed(() => (props.total ? page.value * props.size + 1 : 0))
const to = computed(() => Math.min(props.total, (page.value + 1) * props.size))
</script>

<template>
  <div v-if="pages > 1" class="arrow-pager">
    <span class="caption tabular">{{ t('pager.range', { from, to, total }) }}</span>
    <button type="button" class="arrow" :disabled="page === 0" :aria-label="t('pager.prev')" @click="page -= 1"><i class="pi pi-chevron-left" aria-hidden="true" /></button>
    <button type="button" class="arrow" :disabled="page + 1 >= pages" :aria-label="t('pager.next')" @click="page += 1"><i class="pi pi-chevron-right" aria-hidden="true" /></button>
  </div>
</template>

<style scoped>
.arrow-pager { display: flex; align-items: center; justify-content: flex-end; gap: 6px; margin-top: 10px; }
.arrow-pager .caption { margin-right: 6px; }
.arrow { width: 32px; height: 32px; border-radius: 50%; border: 1px solid var(--border-soft); background: var(--surface); color: var(--text); display: grid; place-items: center; cursor: pointer; }
.arrow:hover:not(:disabled) { background: var(--surface-muted); }
.arrow:disabled { opacity: 0.4; cursor: default; }
.arrow .pi { font-size: 12px; }
</style>
