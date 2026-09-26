<script setup lang="ts">
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import { ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { useAuthStore } from '@/stores/auth'

/** Вход: eGov mobile — единственная заливная кнопка, вход по логину — контурная, гость — текстом.
 * `hint` — подсказка над кнопкой входа (например, какая роль нужна для страницы из ?denied). */
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
    <p class="muted">{{ t('auth.loginLead') }}</p>
    <p v-if="hint" class="hint" data-testid="denied">{{ hint }}</p>
    <div class="buttons">
      <Button :label="t('auth.loginEgov')" icon="pi pi-mobile" data-testid="login-egov" @click="onEgov" />
      <Button
        :label="t('auth.login')"
        severity="secondary"
        outlined
        :disabled="auth.keycloakUnavailable"
        :title="auth.keycloakUnavailable ? t('auth.unavailable') : undefined"
        data-testid="login-primary"
        @click="auth.login()"
      />
      <RouterLink class="guest" to="/wait" data-testid="continue-guest">{{ t('auth.continueGuest') }}</RouterLink>
    </div>
    <p class="muted note">{{ auth.keycloakUnavailable ? t('auth.unavailable') : t('auth.syntheticNote') }}</p>
    <Dialog v-model:visible="roadmap" modal :header="t('auth.roadmapTitle')" :style="{ width: 'min(480px, 92vw)' }" data-testid="egov-roadmap">
      <p class="roadmap">{{ t('auth.roadmap') }}</p>
      <template #footer>
        <Button :label="t('auth.login')" data-testid="login-from-roadmap" @click="loginFromRoadmap" />
      </template>
    </Dialog>
  </section>
</template>

<style scoped>
.login-panel h2 { margin-bottom: 4px; }
.hint { margin: 8px 0 0; padding: 8px 10px; border-radius: var(--dm-radius-sm); background: var(--dm-warn-soft); color: var(--dm-warn); font-size: 0.9rem; }
.buttons { display: flex; flex-direction: column; gap: 8px; margin-top: 12px; }
.buttons :deep(.p-button) { justify-content: center; }
.guest { text-align: center; font-size: 0.9rem; padding: 6px; }
.note { font-size: 0.85rem; margin: 12px 0 0; }
.roadmap { margin: 0; line-height: 1.5; }
</style>
