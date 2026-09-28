<script setup lang="ts">
import Button from 'primevue/button'
import InputText from 'primevue/inputtext'
import { useToast } from 'primevue/usetoast'
import { useI18n } from 'vue-i18n'

/** Ссылка-приглашение для ручной передачи, когда письмо не ушло (API: emailSent: false, inviteUrl): почтовый сервер
 * не настроен или не отвечает. Пояснение одно на все места — приглашение пользователя и одобрение заявки организации. */
const props = defineProps<{ url: string }>()
const { t } = useI18n()
const toast = useToast()

async function copy() {
  try {
    await navigator.clipboard.writeText(props.url)
    toast.add({ severity: 'success', summary: t('shell.copied'), life: 2500 })
  } catch {
    toast.add({ severity: 'warn', summary: t('admin.invite.copyManual'), life: 4000 })
  }
}
</script>

<template>
  <div class="invite-link">
    <p class="manual" data-testid="invite-manual">{{ t('admin.invite.noEmail') }}</p>
    <div class="link-row">
      <InputText :model-value="url" readonly class="link-input" :aria-label="t('admin.invite.linkLabel')" data-testid="invite-url" @focus="($event.target as HTMLInputElement).select()" />
      <Button :label="t('admin.invite.copy')" icon="pi pi-copy" severity="secondary" data-testid="invite-copy" @click="copy" />
    </div>
  </div>
</template>

<style scoped>
.invite-link { display: flex; flex-direction: column; gap: 12px; }
.manual { margin: 0; }
.link-row { display: flex; gap: 8px; }
.link-input { flex: 1; min-width: 0; font-family: var(--dm-font-mono); font-size: var(--dm-text-sm); }
</style>
