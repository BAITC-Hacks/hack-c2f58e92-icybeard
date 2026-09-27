<script setup lang="ts">
import Button from 'primevue/button'
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { ApiError } from '@/api/client'
import { pub } from '@/api/endpoints'
import type { OrgApplicationStatus } from '@/api/types'
import CodeInput from '@/components/public/CodeInput.vue'
import StateBlock from '@/components/states/StateBlock.vue'
import StateError from '@/components/states/StateError.vue'
import Skeleton from '@/components/ui/Skeleton.vue'
import { useLocaleFormat } from '@/composables/useLocaleFormat'
import { readApplication } from '@/lib/signupStore'
import { CODE_LENGTH, isCode } from '@/lib/validation'
import { useAuthStore } from '@/stores/auth'

/** Статус заявки (W-Auth-Verify + W-Auth-Pending), без входа: statusToken берётся из localStorage этого браузера.
 * pending_email — ввод 6-значного кода из письма (автопереход, вставка целиком, «Отправить код повторно» с таймером);
 * pending_review — «Заявка на модерации» с этапами; approved / rejected — итог. */
const RESEND_SECONDS = 60
const props = defineProps<{ id: string }>()
const { t } = useI18n()
const { date } = useLocaleFormat()
const auth = useAuthStore()
const saved = readApplication(props.id)

const status = ref<OrgApplicationStatus | null>(null)
const loading = ref(false)
const error = ref<unknown>(null)
const code = ref('')
const verifying = ref(false)
const codeError = ref('')
const left = ref(0)
const resendError = ref('')
/** Письмо с кодом не ушло: почтовый сервер стенда не настроен (API: emailSent: false). */
const emailNotSent = ref(saved?.emailSent === false)
let timer: number | undefined

// в статусе API почта маскирована (a***@…) — в этом браузере показываем полный адрес из заявки
const email = computed(() => saved?.email ?? status.value?.email ?? '')
const steps = computed(() => {
  const s = status.value?.status
  const reviewDone = s === 'approved'
  return [
    { key: 'sent', done: true, current: false },
    { key: 'email', done: s !== 'pending_email', current: s === 'pending_email' },
    { key: 'review', done: reviewDone, current: s === 'pending_review' },
    { key: 'access', done: reviewDone, current: false },
  ]
})

async function load() {
  if (!saved) return
  loading.value = true
  error.value = null
  try {
    status.value = await pub.application(props.id, saved.statusToken)
  } catch (e) {
    error.value = e
  } finally {
    loading.value = false
  }
}

function startTimer(seconds = RESEND_SECONDS) {
  left.value = seconds
  window.clearInterval(timer)
  timer = window.setInterval(() => {
    left.value = Math.max(0, left.value - 1)
    if (left.value === 0) window.clearInterval(timer)
  }, 1000)
}

async function verify(value = code.value) {
  if (!saved || !isCode(value)) {
    codeError.value = t('signup.codeIncomplete', { n: CODE_LENGTH })
    return
  }
  verifying.value = true
  codeError.value = ''
  try {
    await pub.verifyEmail(props.id, value, saved.statusToken)
    await load()
  } catch (e) {
    codeError.value = e instanceof ApiError && (e.status === 400 || e.status === 422) ? e.field('code') ?? t('signup.codeWrong') : t('signup.codeFailed', { reason: e instanceof ApiError ? e.status : '—' })
    code.value = ''
  } finally {
    verifying.value = false
  }
}

async function resend() {
  if (!saved || left.value > 0) return
  resendError.value = ''
  try {
    const sent = await pub.resendCode(props.id, saved.statusToken)
    emailNotSent.value = sent.emailSent === false
    startTimer(sent.resendAfterSeconds || RESEND_SECONDS)
  } catch (e) {
    if (e instanceof ApiError && e.status === 429) startTimer()
    else resendError.value = t('signup.resendFailed', { reason: e instanceof ApiError ? e.status : '—' })
  }
}

const timerLabel = computed(() => `${Math.floor(left.value / 60)}:${String(left.value % 60).padStart(2, '0')}`)
onMounted(async () => {
  await load()
  if (status.value?.status === 'pending_email') startTimer(saved?.resendAfterSeconds || RESEND_SECONDS)
})
onBeforeUnmount(() => window.clearInterval(timer))
</script>

<template>
  <main class="public-page">
    <section class="card public-card" data-testid="signup-status">
      <StateBlock v-if="!saved" icon="pi pi-link" :title="t('signup.noToken')" :text="t('signup.noTokenText')">
        <RouterLink class="link-arrow" to="/signup">{{ t('signup.newApplication') }}</RouterLink>
      </StateBlock>
      <StateError v-else-if="error" :error="error" @retry="load" />
      <Skeleton v-else-if="loading && !status" :lines="6" />

      <template v-else-if="status?.status === 'pending_email'">
        <h1>{{ t('signup.verifyTitle') }}</h1>
        <p class="lead">{{ t('signup.verifyLead', { email }) }}</p>
        <CodeInput v-model="code" :disabled="verifying" :invalid="!!codeError" @complete="verify" />
        <span v-if="codeError" class="error-text" data-testid="code-error">{{ codeError }}</span>
        <Button :label="t('signup.confirm')" :loading="verifying" class="wide" data-testid="code-submit" @click="verify()" />
        <p class="center small">
          <span v-if="left > 0" class="muted">{{ t('signup.resendIn', { time: timerLabel }) }}</span>
          <button v-else type="button" class="text-link" data-testid="code-resend" @click="resend">{{ t('signup.resend') }}</button>
          <span class="muted"> · </span><RouterLink class="text-link" to="/signup">{{ t('signup.changeData') }}</RouterLink>
        </p>
        <span v-if="resendError" class="error-text center">{{ resendError }}</span>
        <p v-if="emailNotSent" class="note" data-testid="email-not-sent">{{ t('signup.emailNotSent') }}</p>
      </template>

      <template v-else-if="status">
        <span class="status-icon" :class="status.status" aria-hidden="true"><i :class="status.status === 'approved' ? 'pi pi-check' : status.status === 'rejected' ? 'pi pi-times' : 'pi pi-clock'" /></span>
        <h1>{{ t(`signup.state.${status.status}`) }}</h1>
        <p class="lead">{{ status.orgName }}<br />{{ t('signup.numberSent', { number: status.number, date: date(status.submittedAt) }) }}</p>
        <ol v-if="status.status !== 'rejected'" class="steps">
          <li v-for="s in steps" :key="s.key" :class="{ done: s.done, current: s.current }"><span class="dot" aria-hidden="true"><i v-if="s.done" class="pi pi-check" /></span>{{ t(`signup.step.${s.key}`) }}</li>
        </ol>
        <p class="note">{{ status.status === 'approved' ? t('signup.approvedNote', { email }) : status.status === 'rejected' ? t('signup.rejectedNote', { email }) : t('signup.weWillWrite', { email }) }}</p>
        <Button v-if="status.status === 'approved'" :label="t('auth.login')" class="wide" @click="auth.login()" />
        <Button v-else :label="t('signup.refreshStatus')" severity="secondary" class="wide" :loading="loading" data-testid="status-refresh" @click="load" />
      </template>
    </section>
  </main>
</template>

<style scoped>
.public-page { flex: 1; display: flex; justify-content: center; align-items: flex-start; padding: 64px 16px 16px; }
.public-card { width: min(440px, 100%); display: flex; flex-direction: column; gap: 16px; padding: 32px; }
.public-card h1 { font-size: var(--dm-text-xl); margin: 0; }
.lead { margin: -4px 0 0; color: var(--dm-muted); }
.wide { width: 100%; justify-content: center; }
.center { text-align: center; margin: 0; }
.error-text { color: var(--dm-danger); font-size: var(--dm-text-sm); }
.status-icon { width: 48px; height: 48px; border-radius: 50%; display: grid; place-items: center; background: var(--dm-neutral-soft); }
.status-icon.approved { background: var(--dm-ok-soft); color: var(--dm-ok); }
.status-icon.rejected { background: var(--dm-warn-soft); color: var(--dm-warn); }
.steps { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; gap: 14px; position: relative; }
.steps li { display: flex; align-items: center; gap: 12px; color: var(--dm-muted); font-size: var(--dm-text-md); }
.steps li.done, .steps li.current { color: var(--dm-ink); }
.dot { width: 16px; height: 16px; border-radius: 50%; background: var(--dm-dot-idle); display: grid; place-items: center; color: #fff; font-size: 9px; flex: none; }
.steps li.done .dot, .steps li.current .dot { background: var(--dm-primary); }
.note { margin: 0; padding: 12px 16px; border-radius: var(--dm-radius-md); background: var(--dm-neutral-soft); font-size: var(--dm-text-sm); }
</style>
