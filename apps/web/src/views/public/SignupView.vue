<script setup lang="ts">
import Button from 'primevue/button'
import Checkbox from 'primevue/checkbox'
import InputText from 'primevue/inputtext'
import Select from 'primevue/select'
import { computed, onMounted, reactive, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRouter } from 'vue-router'
import { ApiError } from '@/api/client'
import { pub } from '@/api/endpoints'
import ErrorBox from '@/components/ErrorBox.vue'
import { saveApplication } from '@/lib/signupStore'
import { formatKzPhone, isBin, isEmail, isKzPhone, phoneDigits } from '@/lib/validation'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'

/** Регистрация организации (W-Auth-Signup), без входа: организация (название, БИН — 12 цифр, тип, регион из
 * справочника, код в ИС БГ), администратор (ФИО, рабочая почта, телефон +7), согласие. POST /public/org-applications
 * → { id, number, statusToken }; statusToken сохраняется в браузере, дальше — /signup/:id (подтверждение почты и статус).
 * Ошибки 422 показываются у полей. */
/** Типы — те же, что в справочнике организаций (admin/orgs). */
const ORG_TYPES = ['hospital', 'polyclinic', 'center', 'dispensary', 'maternity', 'other'] as const
const { t } = useI18n()
const router = useRouter()
const auth = useAuthStore()
const refdata = useRefdataStore()

const form = reactive({ orgName: '', bin: '', type: 'hospital', regionKato: null as string | null, moCode: '', adminName: '', email: '', phone: '', consent: false })
const touched = ref(false)
const sending = ref(false)
const error = ref<unknown>(null)
const regionsError = ref<unknown>(null)

const typeOptions = computed(() => ORG_TYPES.map((value) => ({ value, label: t(`signup.type.${value}`) })))
const regionOptions = computed(() => refdata.regions.map((r) => ({ value: r.regionKato, label: r.name })))
const server = (name: string) => (error.value instanceof ApiError ? error.value.field(name) : undefined)
const errors = computed(() => ({
  orgName: !form.orgName.trim() ? t('validation.required') : server('orgName'),
  bin: !isBin(form.bin) ? t('validation.bin') : server('bin'),
  type: server('type'),
  regionKato: !form.regionKato ? t('validation.required') : server('regionKato'),
  moCode: server('moCode'),
  adminName: !form.adminName.trim() ? t('validation.required') : server('adminName'),
  email: !isEmail(form.email) ? t('validation.email') : server('email'),
  phone: !isKzPhone(form.phone) ? t('validation.phone') : server('phone'),
  consent: !form.consent ? t('validation.consent') : server('consent'),
}))
const show = (name: keyof typeof errors.value) => (touched.value || (error.value instanceof ApiError && error.value.status === 422)) && errors.value[name]
const clientValid = computed(() => !Object.entries(errors.value).some(([name, message]) => message && !server(name)))

function onBin(value: string | undefined) {
  form.bin = (value ?? '').replace(/\D/g, '').slice(0, 12)
}

async function submit() {
  touched.value = true
  if (!clientValid.value) return
  sending.value = true
  error.value = null
  try {
    const created = await pub.apply({
      orgName: form.orgName.trim(), bin: form.bin, type: form.type, regionKato: form.regionKato!, moCode: form.moCode.trim() || null,
      adminName: form.adminName.trim(), email: form.email.trim(), phone: `+${phoneDigits(form.phone)}`, consent: form.consent,
    })
    saveApplication({
      id: created.id, number: created.number, statusToken: created.statusToken, email: form.email.trim(), orgName: form.orgName.trim(),
      emailSent: created.emailSent, resendAfterSeconds: created.resendAfterSeconds,
    })
    await router.push({ name: 'signup-status', params: { id: created.id } })
  } catch (e) {
    error.value = e
  } finally {
    sending.value = false
  }
}

onMounted(async () => {
  try {
    await refdata.load()
  } catch (e) {
    regionsError.value = e
  }
})
</script>

<template>
  <main class="public-page">
    <form class="card public-card" novalidate data-testid="signup-form" @submit.prevent="submit">
      <h1>{{ t('signup.title') }}</h1>
      <p class="lead">{{ t('signup.lead') }}</p>
      <div class="field"><label for="s-org">{{ t('signup.orgName') }}</label><InputText id="s-org" v-model="form.orgName" :invalid="!!show('orgName')" data-testid="signup-org" /><span v-if="show('orgName')" class="error">{{ errors.orgName }}</span></div>
      <div class="pair">
        <div class="field"><label for="s-bin">{{ t('signup.bin') }}</label><InputText id="s-bin" :model-value="form.bin" inputmode="numeric" maxlength="12" :invalid="!!show('bin')" data-testid="signup-bin" @update:model-value="onBin" /><span v-if="show('bin')" class="error">{{ errors.bin }}</span></div>
        <div class="field"><label for="s-type">{{ t('signup.typeLabel') }}</label><Select id="s-type" v-model="form.type" :options="typeOptions" option-label="label" option-value="value" /><span v-if="show('type')" class="error">{{ errors.type }}</span></div>
      </div>
      <div class="pair">
        <div class="field">
          <label for="s-region">{{ t('signup.region') }}</label>
          <Select id="s-region" v-model="form.regionKato" :options="regionOptions" option-label="label" option-value="value" filter :placeholder="t('signup.pickRegion')" :invalid="!!show('regionKato')" :loading="!refdata.loaded && !regionsError" data-testid="signup-region" />
          <span v-if="show('regionKato')" class="error">{{ errors.regionKato }}</span>
          <span v-if="regionsError" class="error">{{ t('signup.regionsUnavailable') }}</span>
        </div>
        <div class="field"><label for="s-mo">{{ t('signup.moCode') }}</label><InputText id="s-mo" v-model="form.moCode" :placeholder="t('signup.optional')" /><span v-if="show('moCode')" class="error">{{ errors.moCode }}</span></div>
      </div>
      <div class="divider"><span class="eyebrow">{{ t('signup.adminSection') }}</span></div>
      <div class="field"><label for="s-name">{{ t('signup.adminName') }}</label><InputText id="s-name" v-model="form.adminName" autocomplete="name" :invalid="!!show('adminName')" data-testid="signup-name" /><span v-if="show('adminName')" class="error">{{ errors.adminName }}</span></div>
      <div class="pair">
        <div class="field"><label for="s-email">{{ t('signup.email') }}</label><InputText id="s-email" v-model="form.email" type="email" autocomplete="email" :invalid="!!show('email')" data-testid="signup-email" /><span v-if="show('email')" class="error">{{ errors.email }}</span></div>
        <div class="field"><label for="s-phone">{{ t('signup.phone') }}</label><InputText id="s-phone" v-model="form.phone" type="tel" autocomplete="tel" placeholder="+7 7__ ___ __ __" :invalid="!!show('phone')" data-testid="signup-phone" @blur="form.phone = formatKzPhone(form.phone)" /><span v-if="show('phone')" class="error">{{ errors.phone }}</span></div>
      </div>
      <div class="field checkbox"><Checkbox v-model="form.consent" binary input-id="s-consent" :invalid="!!show('consent')" data-testid="signup-consent" /><label for="s-consent">{{ t('signup.consent') }}</label></div>
      <span v-if="show('consent')" class="error consent-error">{{ errors.consent }}</span>
      <ErrorBox v-if="!(error instanceof ApiError && error.status === 422)" :error="error" />
      <Button type="submit" :label="t('signup.submit')" :loading="sending" class="submit" data-testid="signup-submit" />
      <p class="center small">{{ t('signup.haveAccount') }} <button type="button" class="text-link" data-testid="signup-login" @click="auth.login()">{{ t('auth.login') }}</button></p>
      <p class="center caption">{{ t('signup.reviewNote') }}</p>
    </form>
  </main>
</template>

<style scoped>
.public-page { flex: 1; display: flex; justify-content: center; padding: 32px 16px 16px; }
.public-card { width: min(520px, 100%); display: flex; flex-direction: column; gap: 14px; padding: 32px; }
.public-card h1 { font-size: var(--dm-text-xl); margin: 0; }
.lead { margin: -6px 0 4px; color: var(--dm-muted); }
.pair { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }
.divider { display: flex; align-items: center; gap: 12px; margin-top: 4px; }
.divider::after { content: ''; flex: 1; height: 1px; background: var(--dm-hairline); }
.consent-error { margin-top: -8px; color: var(--dm-danger); font-size: 0.8rem; }
.submit { width: 100%; justify-content: center; }
.center { text-align: center; margin: 0; }
@media (max-width: 520px) { .pair { grid-template-columns: 1fr; } .public-card { padding: 20px; } }
</style>
