<script setup lang="ts">
import Button from 'primevue/button'
import { useToast } from 'primevue/usetoast'
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { account } from '@/api/endpoints'
import type { SecurityResponse, SessionRecord } from '@/api/types'
import AccountTabs from '@/components/account/AccountTabs.vue'
import ErrorBox from '@/components/ErrorBox.vue'
import AsyncState from '@/components/states/AsyncState.vue'
import AppCard from '@/components/ui/AppCard.vue'
import PageShell from '@/components/ui/PageShell.vue'
import StatusTag from '@/components/ui/StatusTag.vue'
import { useAsync } from '@/composables/useAsync'
import { useLocaleFormat } from '@/composables/useLocaleFormat'
import { useAuthStore } from '@/stores/auth'

/** Безопасность (W-Account-Security): пароль и приложение-аутентификатор меняются в Keycloak (kc_action
 * UPDATE_PASSWORD / CONFIGURE_TOTP), SMS — «после интеграции», резервных кодов в системе входа нет; последние входы и
 * активные сессии — GET /me/security, «Завершить» — DELETE /me/sessions/{id}, «Завершить все, кроме текущей». */
const { t, te } = useI18n()
const toast = useToast()
const auth = useAuthStore()
const { dateTime } = useLocaleFormat()
const { data: security, loading, error, run } = useAsync<SecurityResponse>(() => account.security())
const ending = ref<string | null>(null)
const actionError = ref<unknown>(null)

const passwordAge = computed(() => {
  const changed = security.value?.passwordChangedAt
  if (!changed) return t('account.security.passwordUnknown')
  const daysAgo = Math.max(0, Math.floor((Date.now() - new Date(changed).getTime()) / 86_400_000))
  return daysAgo === 0 ? t('account.security.passwordToday') : t('account.security.passwordDaysAgo', { days: daysAgo })
})
const otherSessions = computed(() => (security.value?.sessions ?? []).filter((s) => !s.current))


async function endSession(session: SessionRecord) {
  ending.value = session.id
  actionError.value = null
  try {
    await account.endSession(session.id)
    toast.add({ severity: 'success', summary: t('account.security.sessionEnded'), life: 3000 })
    await run()
  } catch (e) {
    actionError.value = e
  } finally {
    ending.value = null
  }
}

async function endOthers() {
  ending.value = 'others'
  actionError.value = null
  try {
    await account.endOtherSessions()
    toast.add({ severity: 'success', summary: t('account.security.othersEnded'), life: 3000 })
    await run()
  } catch (e) {
    actionError.value = e
  } finally {
    ending.value = null
  }
}

onMounted(run)
</script>

<template>
  <PageShell :title="t('account.security.title')" :lead="[auth.displayName ?? auth.actor, auth.email].filter(Boolean).join(' · ')">
    <AccountTabs />
    <div class="security-grid">
      <div class="col">
        <AppCard>
          <div class="line">
            <div><h2>{{ t('account.security.password') }}</h2><span class="muted small">{{ passwordAge }}</span></div>
            <Button :label="t('account.security.changePassword')" severity="secondary" data-testid="change-password" @click="auth.accountAction('UPDATE_PASSWORD')" />
          </div>
        </AppCard>
        <AppCard :title="t('account.security.twoFactor')" label>
          <div class="rows">
            <div class="row">
              <span class="row-main">{{ t('account.security.sms') }}</span>
              <span class="row-value"><StatusTag :value="t('account.security.afterIntegration')" /></span>
            </div>
            <div class="row">
              <span class="row-main">{{ t('account.security.otp') }} <StatusTag v-if="security" :value="security.otpConfigured ? t('account.security.configured') : t('account.security.notConfigured')" :tone="security.otpConfigured ? 'ok' : 'neutral'" /></span>
              <span class="row-value"><Button :label="security?.otpConfigured ? t('account.security.reconfigure') : t('account.security.configure')" size="small" :severity="security?.otpConfigured ? 'secondary' : undefined" data-testid="configure-otp" @click="auth.accountAction('CONFIGURE_TOTP')" /></span>
            </div>
            <div class="row">
              <span class="row-main">{{ t('account.security.recoveryCodes') }}</span>
              <span class="row-value muted small">{{ security?.recoveryCodes ? t('account.security.codesLeft', { n: security.recoveryCodes.length }) : t('account.security.noRecoveryCodes') }}</span>
            </div>
          </div>
        </AppCard>
      </div>
      <AppCard :title="t('account.security.recentLogins')" label>
        <AsyncState :loading="loading" :error="error" :empty="!security?.recentLogins.length" skeleton="lines" :lines="4" :empty-title="t('account.security.noLogins')" empty-icon="pi pi-sign-in" @retry="run">
          <!-- список входов прокручивается внутри карточки: видно около четырёх, остальные — прокруткой -->
          <div class="rows logins-scroll" tabindex="0" :aria-label="t('account.security.recentLogins')">
            <div v-for="login in security!.recentLogins" :key="login.at + login.method" class="row">
              <span class="row-main stack"><span class="tabular">{{ dateTime(login.at) }}</span><div class="row-sub">{{ te(`account.security.method.${login.method}`) ? t(`account.security.method.${login.method}`) : login.method }}<template v-if="login.ip"> · {{ login.ip }}</template></div></span>
              <span class="row-value"><StatusTag :value="login.success ? t('account.security.loginOk') : t('account.security.loginFailed')" :tone="login.success ? 'ok' : 'warn'" /></span>
            </div>
          </div>
        </AsyncState>
      </AppCard>
    </div>

    <AppCard :title="t('account.security.sessions')" label class="sessions">
      <template #header><span class="caption">{{ t('account.security.sessionsNote', { n: security?.sessions.length ?? 0 }) }}</span></template>
      <AsyncState :loading="loading" :error="error" :empty="!security?.sessions.length" :lines="3" :empty-title="t('account.security.noSessions')" empty-icon="pi pi-desktop" @retry="run">
        <div class="table-wrap">
          <table class="dense-table" data-testid="sessions-table">
            <thead><tr><th>{{ t('account.security.device') }}</th><th>{{ t('account.security.ip') }}</th><th>{{ t('account.security.activity') }}</th><th class="num">{{ t('account.security.status') }}</th></tr></thead>
            <tbody>
              <tr v-for="session in security!.sessions" :key="session.id">
                <td><span class="strong">{{ session.device ?? '—' }}</span><div class="caption">{{ session.browser ?? '' }}</div></td>
                <td class="tabular">{{ session.ip ?? '—' }}</td>
                <td class="tabular">{{ session.current ? t('account.security.now') : dateTime(session.lastAccess) }}</td>
                <td class="num">
                  <StatusTag v-if="session.current" :value="t('account.security.current')" tone="accent" />
                  <Button v-else :label="t('account.security.end')" size="small" text severity="danger" :loading="ending === session.id" @click="endSession(session)" />
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <div class="sessions-foot">
          <Button :label="t('account.security.endOthers')" severity="secondary" :disabled="otherSessions.length === 0" :loading="ending === 'others'" data-testid="end-others" @click="endOthers" />
          <span class="caption">{{ otherSessions.length === 0 ? t('account.security.noOtherSessions') : t('account.security.endOthersNote') }}</span>
        </div>
      </AsyncState>
      <ErrorBox :error="actionError" />
    </AppCard>
  </PageShell>
</template>

<style scoped>
/* аккаунт (account-security-new): колонка 880 по центру, карточки padding 24 */
.page { max-width: 1120px; }
.card { padding: 24px; }
.security-grid { display: grid; grid-template-columns: minmax(0, 1.4fr) minmax(0, 1fr); gap: 16px; align-items: start; }
.col { display: flex; flex-direction: column; gap: 16px; }
.line { display: flex; align-items: center; justify-content: space-between; gap: 12px; flex-wrap: wrap; }
.line h2 { margin: 0 0 4px; font-size: 15px; font-weight: var(--fw-extrabold); }
.line .small { font-size: var(--fs-base-sm); }
.row-main { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
.row-main.stack { display: block; }
.row-main .tabular { font-weight: var(--fw-bold); font-size: 14px; }
.strong { font-weight: var(--fw-bold); }
.logins-scroll { max-height: 300px; overflow-y: auto; padding-right: 8px; scrollbar-width: thin; scrollbar-color: var(--border) transparent; }
.logins-scroll:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; border-radius: var(--radius-md); }
.sessions-foot { display: flex; align-items: center; gap: 12px; flex-wrap: wrap; margin-top: 14px; }
@media (max-width: 900px) { .security-grid { grid-template-columns: 1fr; } }
</style>
