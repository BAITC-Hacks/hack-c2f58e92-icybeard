<script setup lang="ts">
import Button from 'primevue/button'
import { useToast } from 'primevue/usetoast'
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute } from 'vue-router'
import { ApiError } from '@/api/client'
import { errorCode, isForbidden, supportMailto, supportReport } from '@/lib/support'
import StateBlock from './StateBlock.vue'
import StateNoAccess from './StateNoAccess.vue'

/** Ошибка загрузки (W-States): «Не удалось загрузить данные», код ответа, «Повторить» и «Сообщить в поддержку →».
 * 403 — не ошибка, а «Нет доступа к разделу» с запросом доступа. 404 от ещё не подключённого эндпоинта — тот же
 * экран ошибки с пояснением, страница не падает. */
const props = withDefaults(defineProps<{ error: unknown; compact?: boolean; retryable?: boolean }>(), { retryable: true })
const emit = defineEmits<{ retry: [] }>()
const { t } = useI18n()
const toast = useToast()
const route = useRoute()

const code = computed(() => errorCode(props.error))
const text = computed(() => {
  if (code.value === 404) return t('states.errorNotConnected')
  if (code.value === null) return t('states.errorNetwork')
  return t('states.errorCode', { code: code.value })
})
const detail = computed(() => (props.error instanceof ApiError ? props.error.detail ?? '' : ''))

async function report() {
  const body = supportReport(props.error, route.fullPath)
  const mailto = supportMailto(body)
  if (mailto) {
    window.location.href = mailto
    return
  }
  try {
    await navigator.clipboard.writeText(body)
    toast.add({ severity: 'info', summary: t('states.reportCopied'), life: 4000 })
  } catch {
    toast.add({ severity: 'warn', summary: t('states.reportManual'), detail: body, life: 8000 })
  }
}
</script>

<template>
  <StateNoAccess v-if="isForbidden(error)" :detail="(error as ApiError).detail" :permissions="(error as ApiError).permissions" :compact="compact" />
  <StateBlock v-else-if="error" icon="pi pi-exclamation-triangle" tone="warn" :title="t('states.errorTitle')" :text="text" :compact="compact" data-testid="state-error">
    <template #text><p v-if="detail" class="caption detail">{{ detail }}</p></template>
    <Button v-if="retryable" :label="t('common.retry')" severity="secondary" size="small" data-testid="retry" @click="emit('retry')" />
    <button type="button" class="link-arrow small" data-testid="report-support" @click="report">{{ t('states.report') }}</button>
  </StateBlock>
</template>

<style scoped>
.detail { margin: 0; max-width: 60ch; }
</style>
