<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { useLocaleFormat } from '@/composables/useLocaleFormat'

/** Постраничная навигация таблиц администрирования: «Показаны 1–7 из 1 248 · страница 1 из 179», «‹ Назад» / «Дальше ›»
 * (пилюли selected). Страницы с 1, как в API ({ items, total, page, size }). */
const props = defineProps<{ total: number; size: number; note?: string }>()
const page = defineModel<number>('page', { default: 1 })
const { t } = useI18n()
const { num } = useLocaleFormat()
const pages = computed(() => Math.max(1, Math.ceil(props.total / props.size)))
const from = computed(() => (props.total === 0 ? 0 : (page.value - 1) * props.size + 1))
const to = computed(() => Math.min(props.total, page.value * props.size))
</script>

<template>
  <div class="pager">
    <span class="caption">
      <template v-if="note">{{ note }} · </template>{{ t('pager.shown', { from: num(from), to: num(to), total: num(total) }) }} · {{ t('pager.page', { page: num(page), pages: num(pages) }) }}
    </span>
    <span class="spacer" />
    <button type="button" class="pager-btn" :disabled="page <= 1" data-testid="pager-prev" @click="page -= 1"><i class="pi pi-angle-left" aria-hidden="true" /> {{ t('pager.prev') }}</button>
    <button type="button" class="pager-btn" :disabled="page >= pages" data-testid="pager-next" @click="page += 1">{{ t('pager.next') }} <i class="pi pi-angle-right" aria-hidden="true" /></button>
  </div>
</template>

<style scoped>
.pager { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; margin-top: 16px; }
.spacer { flex: 1; }
.pager-btn { display: inline-flex; align-items: center; gap: 6px; height: 36px; padding: 0 14px; border: 0; border-radius: var(--dm-radius-pill); background: var(--dm-accent-soft); color: var(--dm-ink); font: inherit; font-size: var(--dm-text-sm); font-weight: 500; cursor: pointer; }
.pager-btn:hover:not(:disabled) { color: var(--dm-accent-hover); }
.pager-btn:disabled { opacity: 0.45; cursor: default; }
</style>
