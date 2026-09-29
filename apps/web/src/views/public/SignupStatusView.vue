<script setup lang="ts">
import Button from 'primevue/button'
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { ApiError } from '@/api/client'
import { pub } from '@/api/endpoints'
import type { OrgApplicationStatus } from '@/api/types'
import CodeInput from '@/components/public/CodeInput.vue'
import StateBlock from '@/components/states/StateBlock.vue'
import StateEmailOff from '@/components/states/StateEmailOff.vue'
import StateError from '@/components/states/StateError.vue'
import Skeleton from '@/components/ui/Skeleton.vue'
import { useLocaleFormat } from '@/composables/useLocaleFormat'
import { readApplication } from '@/lib/signupStore'
import { CODE_LENGTH, isCode } from '@/lib/validation'
import { useAuthStore } from '@/stores/auth'
import { useServiceStatusStore } from '@/stores/serviceStatus'

/** Статус заявки (W-Auth-Verify + W-Auth-Pending), без входа: statusToken берётся из localStorage этого браузера.
 * pending_email — ввод 6-значного кода из письма (автопереход, вставка целиком, «Отправить код повторно» с таймером);
 * pending_review — «Заявка на модерации» с этапами; approved / rejected — итог. Пока почтовый сервер недоступен
 * (GET /public/service-status), страница не обещает писем: код может не прийти, решение смотрят здесь. */
const RESEND_SECONDS = 60
const props = defineProps<{ id: string }>()
const { t } = useI18n()
const { date } = useLocaleFormat()
const auth = useAuthStore()
const services = useServiceStatusStore()
const saved = readApplication(props.id)

const status = ref<OrgApplicationStatus | null>(null)
const loading = ref(false)
const error = ref<unknown>(null)
const code = ref('')
const verifying = ref(false)
const codeError = ref('')
const left = ref(0)
const resendError = ref('')
/** Письмо с кодом не ушло (API: emailSent: false): почтовый сервер не настроен или не отвечает. */
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
/** Итог заявки под этапами; пока почта недоступна — без обещания письма. */
const resultNote = computed(() => {
  const s = status.value?.status
  const off = services.emailUnavailable
  if (s === 'approved') return off ? t('signup.approvedManual', { email: email.value }) : t('signup.approvedNote', { email: email.value })
  if (s === 'rejected') return off ? t('signup.rejectedManual', { email: email.value }) : t('signup.rejectedNote', { email: email.value })
  return off ? t('signup.watchStatus') : t('signup.weWillWrite', { email: email.value })
})
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
        <p v-if="emailNotSent" class="note off" data-testid="email-not-sent">{{ t('signup.emailNotSent') }}</p>
        <StateEmailOff v-else :text="t('serviceStatus.notes.code')" />
      </template>

      <template v-else-if="status">
        <span class="status-icon" :class="status.status" aria-hidden="true"><i :class="status.status === 'approved' ? 'pi pi-check' : status.status === 'rejected' ? 'pi pi-times' : 'pi pi-clock'" /></span>
        <h1 class="center">{{ t(`signup.state.${status.status}`) }}</h1>
        <p class="lead center">{{ status.orgName }}<br />{{ t('signup.numberSent', { number: status.number, date: date(status.submittedAt) }) }}</p>
        <ol v-if="status.status !== 'rejected'" class="steps">
          <li v-for="(s, i) in steps" :key="s.key" :class="{ done: s.done, current: s.current, todo: !s.done && !s.current }">
            <span class="dot" aria-hidden="true"><i v-if="s.done" class="pi pi-check" /><span v-else-if="s.current" class="dot-mark" /><template v-else>{{ i + 1 }}</template></span>{{ t(`signup.step.${s.key}`) }}
          </li>
        </ol>
        <p class="note center" :class="{ off: services.emailUnavailable }" data-testid="status-note">{{ resultNote }}</p>
        <Button v-if="status.status === 'approved'" :label="t('auth.login')" class="wide" @click="auth.login()" />
        <Button v-else :label="t('signup.refreshStatus')" severity="secondary" class="wide" :loading="loading" data-testid="status-refresh" @click="load" />
      </template>
    </section>
  </main>
</template>

<style scoped>
/* публичная карточка (public-signup-status-new): 460, radius 20, статусная ветка по центру */
.public-page { flex: 1; display: flex; justify-content: center; align-items: flex-start; padding: 60px 16px 16px; }
.public-card { width: min(460px, 100%); display: flex; flex-direction: column; gap: 16px; padding: 32px; border-radius: var(--radius-card-lg); }
.public-card h1 { font-size: var(--fs-xl); margin: 0; }
.lead { margin: -4px 0 0; color: var(--text-secondary); font-size: 13px; line-height: 1.5; }
.wide { width: 100%; justify-content: center; }
.center { text-align: center; margin: 0; }
.error-text { color: var(--danger-text); font-size: var(--fs-sm); }
.status-icon { width: 56px; height: 56px; border-radius: 50%; display: grid; place-items: center; background: var(--surface-sunken); color: var(--text-secondary); margin: 0 auto; }
.status-icon.approved { background: var(--success-bg); color: var(--success-text); }
.status-icon.rejected { background: var(--warning-bg); color: var(--warning-text); }
.steps { list-style: none; margin: 4px 0; padding: 0; display: flex; flex-direction: column; gap: 12px; }
.steps li { display: flex; align-items: center; gap: 12px; color: var(--text); font-size: 13px; }
.steps li.todo { color: var(--text-muted); }
.dot { width: 22px; height: 22px; border-radius: 50%; display: grid; place-items: center; font-size: var(--fs-2xs); font-weight: var(--fw-extrabold); flex: none; background: var(--surface-sunken); color: var(--text-faint); }
.dot i { font-size: 10px; }
.steps li.done .dot { background: var(--success-bg); color: var(--success-text); }
.steps li.current .dot { background: var(--accent-soft); color: var(--accent-strong); }
.dot-mark { width: 7px; height: 7px; border-radius: 50%; background: var(--accent-strong); }
.note { margin: 0; font-size: var(--fs-sm); color: var(--text-muted); line-height: 1.5; }
.note.off { padding: 12px 16px; border-radius: var(--radius-lg); background: var(--warning-bg); color: var(--text); text-align: left; }
</style>
