<script setup lang="ts">
import Button from 'primevue/button'
import Checkbox from 'primevue/checkbox'
import InputText from 'primevue/inputtext'
import Password from 'primevue/password'
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { ApiError } from '@/api/client'
import { pub } from '@/api/endpoints'
import type { InviteInfo } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import PasswordPolicy from '@/components/public/PasswordPolicy.vue'
import StateBlock from '@/components/states/StateBlock.vue'
import StateError from '@/components/states/StateError.vue'
import Skeleton from '@/components/ui/Skeleton.vue'
import StatusTag from '@/components/ui/StatusTag.vue'
import { useLocaleFormat } from '@/composables/useLocaleFormat'
import { shortOrgName } from '@/lib/format'
import { roleTitle } from '@/lib/labels'
import { passwordValid } from '@/lib/validation'
import { useAuthStore } from '@/stores/auth'

/** Принятие приглашения (W-Auth-Invite), без входа: кто и куда пригласил, ФИО и почта (задал администратор), пароль
 * с тем же чек-листом политики, что в Keycloak, повтор пароля, согласие с правилами работы с данными пациентов.
 * POST /public/invites/{token}/accept; 422 от API — у поля пароля. Ссылка устарела (404/410) — отдельное состояние. */
const props = defineProps<{ token: string }>()
const { t } = useI18n()
const { date } = useLocaleFormat()
const auth = useAuthStore()

const invite = ref<InviteInfo | null>(null)
const loading = ref(true)
const loadError = ref<unknown>(null)
const password = ref('')
const repeat = ref('')
const rules = ref(false)
const touched = ref(false)
const sending = ref(false)
const error = ref<unknown>(null)
const result = ref<'accepted' | 'declined' | null>(null)
const acceptedUsername = ref('')
const { locale } = useI18n()
/** Роль приглашения — название из API (roleTitleRu/Kk), иначе из словаря. */
const inviteRole = computed(() => {
  const i = invite.value
  if (!i) return ''
  return (locale.value === 'kk' ? i.roleTitleKk || i.roleTitleRu : i.roleTitleRu) || roleTitle(i.role)
})

const expired = computed(() => loadError.value instanceof ApiError && [404, 410].includes(loadError.value.status))
const username = computed(() => invite.value?.email.split('@')[0] ?? '')
const passwordError = computed(() => {
  if (error.value instanceof ApiError && error.value.status === 422) return error.value.field('password') ?? error.value.detail ?? error.value.title
  return touched.value && !passwordValid(password.value, username.value) ? t('password.invalid') : ''
})
const repeatError = computed(() => (touched.value && repeat.value !== password.value ? t('password.mismatch') : ''))
const rulesError = computed(() => (touched.value && !rules.value ? t('validation.consent') : ''))

async function load() {
  loading.value = true
  loadError.value = null
  try {
    invite.value = await pub.invite(props.token)
  } catch (e) {
    loadError.value = e
  } finally {
    loading.value = false
  }
}

async function accept() {
  touched.value = true
  error.value = null
  if (!passwordValid(password.value, username.value) || repeat.value !== password.value || !rules.value) return
  sending.value = true
  try {
    const accepted = await pub.acceptInvite(props.token, password.value)
    acceptedUsername.value = accepted?.username ?? ''
    result.value = 'accepted'
  } catch (e) {
    error.value = e
  } finally {
    sending.value = false
  }
}

async function decline() {
  if (!window.confirm(t('invite.declineConfirm'))) return
  sending.value = true
  error.value = null
  try {
    await pub.declineInvite(props.token)
    result.value = 'declined'
  } catch (e) {
    error.value = e
  } finally {
    sending.value = false
  }
}

onMounted(load)
</script>

<template>
  <main class="public-page">
    <section class="card public-card" data-testid="invite-card">
      <Skeleton v-if="loading" :lines="8" />
      <StateBlock v-else-if="expired" icon="pi pi-clock" tone="warn" :title="t('invite.expiredTitle')" :text="t('invite.expiredText')" data-testid="invite-expired" />
      <StateError v-else-if="loadError" :error="loadError" @retry="load" />
      <StateBlock v-else-if="result === 'accepted'" icon="pi pi-check" tone="accent" :title="t('invite.acceptedTitle')" :text="t('invite.acceptedText', { email: invite?.email, username: acceptedUsername || invite?.email })" data-testid="invite-accepted">
        <Button :label="t('auth.login')" @click="auth.login()" />
      </StateBlock>
      <StateBlock v-else-if="result === 'declined'" icon="pi pi-times" :title="t('invite.declinedTitle')" :text="t('invite.declinedText')" />

      <form v-else-if="invite" class="form-col" novalidate @submit.prevent="accept">
        <div class="invite-head">
          <h1>{{ t('invite.heading') }}</h1>
          <div class="org" :title="invite.orgName ?? ''">{{ [invite.orgName ? shortOrgName(invite.orgName) : null, invite.moCode].filter(Boolean).join(' · ') }}</div>
          <div class="meta"><StatusTag :value="inviteRole" /><span class="caption">{{ t('invite.invitedBy', { who: invite.invitedBy, date: date(invite.invitedAt) }) }}</span></div>
        </div>
        <div class="field"><label for="inv-name">{{ t('invite.name') }}</label><InputText id="inv-name" :model-value="invite.displayName" disabled /></div>
        <div class="field"><label for="inv-email">{{ t('invite.email') }}</label><InputText id="inv-email" :model-value="invite.email" disabled /><span class="caption">{{ t('invite.emailByAdmin') }}</span></div>
        <div class="pair">
          <div class="field"><label for="inv-pass">{{ t('invite.password') }}</label><Password v-model="password" input-id="inv-pass" :feedback="false" toggle-mask autocomplete="new-password" :invalid="!!passwordError" fluid data-testid="invite-password" /></div>
          <div class="field"><label for="inv-repeat">{{ t('invite.repeat') }}</label><Password v-model="repeat" input-id="inv-repeat" :feedback="false" toggle-mask autocomplete="new-password" :invalid="!!repeatError" fluid data-testid="invite-repeat" /></div>
        </div>
        <PasswordPolicy :password="password" :username="username" />
        <span v-if="passwordError" class="error-text" data-testid="password-error">{{ passwordError }}</span>
        <span v-if="repeatError" class="error-text">{{ repeatError }}</span>
        <div class="field checkbox"><Checkbox v-model="rules" binary input-id="inv-rules" :invalid="!!rulesError" data-testid="invite-rules" /><label for="inv-rules">{{ t('invite.rules') }}</label></div>
        <span v-if="rulesError" class="error-text">{{ rulesError }}</span>
        <ErrorBox v-if="!(error instanceof ApiError && error.status === 422)" :error="error" />
        <Button type="submit" :label="t('invite.accept')" :loading="sending" class="wide" data-testid="invite-accept" />
        <button type="button" class="decline" :disabled="sending" data-testid="invite-decline" @click="decline">{{ t('invite.decline') }}</button>
        <p class="caption center">{{ t('invite.validUntil', { date: date(invite.expiresAt) }) }}</p>
      </form>
    </section>
  </main>
</template>

<style scoped>
/* публичная карточка (public-invite-new): 460, radius 20, padding 28; заголовок без плашки */
.public-page { flex: 1; display: flex; justify-content: center; align-items: flex-start; padding: 36px 16px 16px; }
.public-card { width: min(460px, 100%); padding: 28px; border-radius: var(--radius-card-lg); }
.form-col { gap: 14px; }
.invite-head { display: flex; flex-direction: column; gap: 6px; }
.invite-head h1 { font-size: var(--fs-xl); margin: 0; }
.org { font-size: var(--fs-base); font-weight: var(--fw-bold); }
.meta { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
.meta :deep(.status) { background: var(--accent-soft); color: var(--accent-strong); }
.field > label, .field :deep(label) { font-size: 12px; font-weight: var(--fw-bold); text-transform: none; letter-spacing: 0; color: var(--text-secondary); }
.field.checkbox > label { font-size: 12px; }
.pair { display: grid; grid-template-columns: 1fr 1fr; gap: 14px; }
.error-text { color: var(--danger-text); font-size: var(--fs-sm); }
.wide { width: 100%; justify-content: center; }
/* danger-ссылка по components.md: --danger-strong 12.5/700 */
.decline { border: 0; background: none; color: var(--danger-strong); font: inherit; font-size: var(--fs-base-sm); font-weight: var(--fw-bold); cursor: pointer; align-self: center; }
.decline:disabled { opacity: 0.45; cursor: default; }
.center { text-align: center; margin: 0; }
.center.caption { color: var(--text-faint); }
@media (max-width: 520px) { .pair { grid-template-columns: 1fr; } .public-card { padding: 20px; } }
</style>
