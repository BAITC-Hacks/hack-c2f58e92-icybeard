<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import { useLocaleFormat } from '@/composables/useLocaleFormat'

/** Данные устарели (W-States): баннер над блоком — «Данные на {дата}», следующая загрузка (если известна) и «Обновить →». */
defineProps<{ asOf: string; next?: string | null }>()
const emit = defineEmits<{ refresh: [] }>()
const { t } = useI18n()
const { date } = useLocaleFormat()
</script>

<template>
  <div class="stale" role="status" data-testid="state-stale">
    <span class="stale-icon" aria-hidden="true"><i class="pi pi-clock" /></span>
    <span class="stale-text"><strong>{{ t('states.staleTitle', { date: date(asOf) }) }}</strong><template v-if="next"> · {{ t('states.staleNext', { date: date(next) }) }}</template></span>
    <button type="button" class="link-arrow small" @click="emit('refresh')">{{ t('states.refresh') }}</button>
  </div>
</template>

<style scoped>
.stale { display: flex; align-items: center; gap: 12px; flex-wrap: wrap; padding: 12px 16px; border-radius: var(--dm-radius-md); background: var(--dm-info-soft); color: var(--dm-ink); font-size: var(--dm-text-sm); }
.stale-icon { width: 28px; height: 28px; border-radius: 50%; display: grid; place-items: center; background: var(--dm-surface); color: var(--dm-info); flex: none; }
.stale-text { flex: 1; min-width: 200px; }
.stale-text strong { font-weight: 500; }
</style>
