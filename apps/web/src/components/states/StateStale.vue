<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import { useLocaleFormat } from '@/composables/useLocaleFormat'

/** Данные устарели (W-States): баннер над блоком — «Данные на {дата}» и следующая загрузка (если известна). Кнопки
 * «Обновить» нет: данные обновляет загрузка витрин, а не пользователь страницы. */
defineProps<{ asOf: string; next?: string | null }>()
const { t } = useI18n()
const { date } = useLocaleFormat()
</script>

<template>
  <div class="stale" role="status" data-testid="state-stale">
    <span class="stale-icon" aria-hidden="true"><i class="pi pi-clock" /></span>
    <span class="stale-text"><strong>{{ t('states.staleTitle', { date: date(asOf) }) }}</strong><template v-if="next"> · {{ t('states.staleNext', { date: date(next) }) }}</template></span>
  </div>
</template>

<style scoped>
.stale { display: flex; align-items: center; gap: 12px; flex-wrap: wrap; padding: 12px 16px; border-radius: var(--radius-lg); background: var(--accent-subtle); color: var(--text); font-size: var(--fs-base-sm); }
.stale-icon { width: 28px; height: 28px; border-radius: 50%; display: grid; place-items: center; background: var(--accent-soft); color: var(--accent-strong); flex: none; }
.stale-text { flex: 1; min-width: 200px; font-variant-numeric: tabular-nums; }
.stale-text strong { font-weight: var(--fw-bold); }
</style>
