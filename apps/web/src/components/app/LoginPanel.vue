<script setup lang="ts">
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import { ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { useAuthStore } from '@/stores/auth'
import { useServiceStatusStore } from '@/stores/serviceStatus'

/** Карточка «Вход» (W-Home): eGov mobile и вход по логину. Гостевого режима нет: без входа приложение не открывается.
 * `hint` — подсказка над кнопками (какая роль нужна для страницы из ?denied). Доступность eGov — из
 * GET /public/service-status (`egov.available`): пока адрес сервиса eGov mobile (Smart Bridge) не предоставлен, кнопка
 * остаётся на месте, но становится вторичной, под ней — подпись «недоступно», а нажатие открывает пояснение с входом по
 * логину и паролю; вход не имитируется. Когда сервис доступен — вход через брокер realm (idpHint egov, docs/egov-auth.md). */
defineProps<{ hint?: string }>()
const { t } = useI18n()
const auth = useAuthStore()
const services = useServiceStatusStore()
const egovInfo = ref(false)

function onEgov() {
  if (services.egovAvailable) void auth.login({ idpHint: 'egov' })
  else egovInfo.value = true
}

function loginWithPassword() {
  egovInfo.value = false
  void auth.login()
}
</script>

<template>
  <section class="card login-panel">
    <h2>{{ t('auth.loginTitle') }}</h2>
    <p class="muted small lead-text">{{ t('auth.loginLead') }}</p>
    <p v-if="hint" class="hint" data-testid="denied">{{ hint }}</p>
    <div class="buttons">
      <div class="egov">
        <Button
          :label="t('auth.loginEgov')"
          icon="pi pi-mobile"
          :severity="services.egovAvailable ? undefined : 'secondary'"
          :aria-describedby="services.egovAvailable ? undefined : 'egov-off-caption'"
          data-testid="login-egov"
          @click="onEgov"
        />
        <p v-if="!services.egovAvailable" id="egov-off-caption" class="caption egov-off" data-testid="egov-unavailable">{{ t('auth.egovOffCaption') }}</p>
      </div>
      <Button
        :label="t('auth.login')"
        :severity="services.egovAvailable ? 'secondary' : undefined"
        :disabled="auth.keycloakUnavailable"
        :title="auth.keycloakUnavailable ? t('auth.unavailable') : undefined"
        data-testid="login-primary"
        @click="auth.login()"
      />
    </div>
    <p class="caption note">{{ auth.keycloakUnavailable ? t('auth.unavailable') : t('auth.syntheticNote') }}</p>
    <Dialog v-model:visible="egovInfo" modal :header="t('auth.egovOffTitle')" :style="{ width: 'min(480px, 92vw)' }" data-testid="egov-roadmap">
      <p class="egov-text">{{ t('auth.egovOffText') }}</p>
      <template #footer>
        <Button :label="t('auth.loginPassword')" :disabled="auth.keycloakUnavailable" data-testid="login-from-roadmap" @click="loginWithPassword" />
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
.buttons :deep(.p-button) { justify-content: center; width: 100%; }
.egov { display: flex; flex-direction: column; gap: 6px; }
.egov-off { margin: 0; text-align: center; }
.note { margin: 0; }
.egov-text { margin: 0; line-height: 1.5; }
</style>
