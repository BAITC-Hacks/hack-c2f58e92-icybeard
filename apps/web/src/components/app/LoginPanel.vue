<script setup lang="ts">
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import { ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { useAuthStore } from '@/stores/auth'

/** Карточка «Вход» (W-Home): eGov mobile — primary (ink), вход по логину — secondary (soft). Гостевого режима нет:
 * без входа приложение не открывается. `hint` — подсказка над кнопками (какая роль нужна для страницы из ?denied). */
defineProps<{ hint?: string }>()
const { t } = useI18n()
const auth = useAuthStore()
const roadmap = ref(false)
// Брокер eGov в realm появится после доступа к Smart Bridge (docs/egov-auth.md); до этого кнопка честно
// показывает «Скоро», а не имитирует вход.
const egovEnabled = import.meta.env.VITE_EGOV_ENABLED === 'true'

function onEgov() {
  if (egovEnabled) void auth.login({ idpHint: 'egov' })
  else roadmap.value = true
}

function loginFromRoadmap() {
  roadmap.value = false
  void auth.login()
}
</script>

<template>
  <section class="card login-panel">
    <h2>{{ t('auth.loginTitle') }}</h2>
    <p class="muted small lead-text">{{ t('auth.loginLead') }}</p>
    <p v-if="hint" class="hint" data-testid="denied">{{ hint }}</p>
    <div class="buttons">
      <Button :label="t('auth.loginEgov')" icon="pi pi-mobile" data-testid="login-egov" @click="onEgov" />
      <Button
        :label="t('auth.login')"
        severity="secondary"
        :disabled="auth.keycloakUnavailable"
        :title="auth.keycloakUnavailable ? t('auth.unavailable') : undefined"
        data-testid="login-primary"
        @click="auth.login()"
      />
    </div>
    <p class="caption note">{{ auth.keycloakUnavailable ? t('auth.unavailable') : t('auth.syntheticNote') }}</p>
    <Dialog v-model:visible="roadmap" modal :header="t('auth.roadmapTitle')" :style="{ width: 'min(480px, 92vw)' }" data-testid="egov-roadmap">
      <p class="roadmap">{{ t('auth.roadmap') }}</p>
      <template #footer>
        <Button :label="t('auth.login')" data-testid="login-from-roadmap" @click="loginFromRoadmap" />
      </template>
    </Dialog>
  </section>
</template>

<style scoped>
.login-panel { display: flex; flex-direction: column; gap: 12px; max-width: 440px; }
.login-panel h2 { margin: 0; }
.lead-text { margin: 0; }
.hint { margin: 0; padding: 10px 12px; border-radius: var(--dm-radius-sm); background: var(--dm-warn-soft); color: var(--dm-warn); font-size: var(--dm-text-sm); }
.buttons { display: flex; flex-direction: column; gap: 12px; margin-top: 4px; }
.buttons :deep(.p-button) { justify-content: center; }
.note { margin: 0; }
.roadmap { margin: 0; line-height: 1.5; }
</style>
