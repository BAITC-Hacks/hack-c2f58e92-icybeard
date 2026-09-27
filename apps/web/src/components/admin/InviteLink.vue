<script setup lang="ts">
import Button from 'primevue/button'
import InputText from 'primevue/inputtext'
import { useToast } from 'primevue/usetoast'
import { useI18n } from 'vue-i18n'

/** Ссылка-приглашение для ручной передачи, когда почтовый сервер не настроен (API: emailSent: false, inviteUrl). */
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
  <div class="link-row">
    <InputText :model-value="url" readonly class="link-input" data-testid="invite-url" @focus="($event.target as HTMLInputElement).select()" />
    <Button :label="t('admin.invite.copy')" icon="pi pi-copy" severity="secondary" data-testid="invite-copy" @click="copy" />
  </div>
</template>

<style scoped>
.link-row { display: flex; gap: 8px; }
.link-input { flex: 1; min-width: 0; font-family: var(--dm-font-mono); font-size: var(--dm-text-sm); }
</style>
