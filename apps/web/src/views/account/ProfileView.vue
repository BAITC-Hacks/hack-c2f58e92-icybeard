<script setup lang="ts">
import Button from 'primevue/button'
import InputText from 'primevue/inputtext'
import Select from 'primevue/select'
import { useToast } from 'primevue/usetoast'
import { computed, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { account } from '@/api/endpoints'
import type { ProfileResponse } from '@/api/types'
import AccountTabs from '@/components/account/AccountTabs.vue'
import ErrorBox from '@/components/ErrorBox.vue'
import StateError from '@/components/states/StateError.vue'
import AppCard from '@/components/ui/AppCard.vue'
import PageShell from '@/components/ui/PageShell.vue'
import Skeleton from '@/components/ui/Skeleton.vue'
import StatusTag from '@/components/ui/StatusTag.vue'
import { useAsync } from '@/composables/useAsync'
import { setLocale } from '@/i18n'
import { shortOrgName } from '@/lib/format'
import { initials, roleTitle } from '@/lib/labels'
import { isKzPhone, phoneDigits, TIME_ZONES, timeZoneLabel } from '@/lib/validation'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'
import { useServiceStatusStore } from '@/stores/serviceStatus'

/** Профиль (W-Account-Profile): карточка «кто я», личные данные (ФИО, должность, специальность — только чтение,
 * «меняет администратор»; телефон — редактируется), рабочая почта со статусом подтверждения, язык и часовой пояс.
 * Сохранение — PUT /me/profile { phone, language, timeZone }. ИИН — только маской из /me. Подтверждение через eGov
 * (чип «подтверждён через eGov») недоступно, пока адрес сервиса eGov mobile не предоставлен (GET /public/service-status) —
 * об этом строка в карточке «кто я». */
const { t } = useI18n()
const toast = useToast()
const auth = useAuthStore()
const refdata = useRefdataStore()
const services = useServiceStatusStore()
const { data: profile, loading, error, run } = useAsync<ProfileResponse>(() => account.profile())

const phone = ref('')
const language = ref<'ru' | 'kk'>('ru')
const timeZone = ref('Asia/Almaty')
const saving = ref(false)
const saveError = ref<unknown>(null)

function reset() {
  phone.value = profile.value?.phone ?? ''
  language.value = profile.value?.language ?? 'ru'
  timeZone.value = profile.value?.timeZone ?? 'Asia/Almaty'
}
watch(profile, reset)

const name = computed(() => profile.value?.displayName ?? auth.displayName ?? auth.actor ?? '')
/** Организация — коротким именем, без организационно-правовой формы (полное — в реестре). */
const moName = computed(() => {
  const full = profile.value?.moName ?? auth.me?.moName ?? (auth.moCode ? refdata.organizationName(auth.moCode) : null)
  return full ? shortOrgName(full) : null
})
const moCode = computed(() => profile.value?.moCode ?? auth.moCode)
const regionKato = computed(() => profile.value?.regionKato ?? auth.region)
const subtitle = computed(() => [name.value, moName.value && moCode.value ? `${moName.value} · ${moCode.value}` : null, regionKato.value ? refdata.regionName(regionKato.value) : null].filter(Boolean).join(' · '))
/** Должность и специальность — у сотрудников организаций; у гражданина их нет. */
const hasJob = computed(() => !!(profile.value?.position || profile.value?.specialty || moCode.value))
const emailVerified = computed(() => profile.value?.emailVerified ?? auth.me?.emailVerified ?? null)
const iinMasked = computed(() => profile.value?.iinMasked ?? auth.me?.iinMasked ?? null)
const languages = computed(() => [{ value: 'ru', label: 'Русский' }, { value: 'kk', label: 'Қазақша' }])
const zones = computed(() => TIME_ZONES.map((zone) => ({ value: zone, label: timeZoneLabel(zone) })))
const phoneValid = computed(() => !phone.value.trim() || isKzPhone(phone.value))
const dirty = computed(() => !!profile.value && (phone.value !== (profile.value.phone ?? '') || language.value !== profile.value.language || timeZone.value !== profile.value.timeZone))

async function save() {
  if (!phoneValid.value) return
  saving.value = true
  saveError.value = null
  try {
    profile.value = await account.saveProfile({ phone: phone.value.trim() ? `+${phoneDigits(phone.value)}` : null, language: language.value, timeZone: timeZone.value })
    setLocale(language.value)
    toast.add({ severity: 'success', summary: t('account.saved'), life: 3000 })
  } catch (e) {
    saveError.value = e
  } finally {
    saving.value = false
  }
}

onMounted(async () => {
  await refdata.load().catch(() => undefined)
  await run()
})
</script>

<template>
  <PageShell :title="t('account.profile.title')" :lead="subtitle">
    <AccountTabs />
    <div class="account-col">
      <section class="card who" data-testid="profile-who">
        <span class="avatar" aria-hidden="true">{{ initials(name) }}</span>
        <div class="who-main">
          <div class="who-name">{{ name }}<StatusTag v-if="profile?.via === 'egov'" :value="t('account.profile.viaEgov')" tone="ok" /></div>
          <div class="muted small">{{ auth.role ? roleTitle(auth.role) : '—' }}<template v-if="moName"> · {{ moName }}<template v-if="moCode"> · {{ moCode }}</template></template></div>
          <div v-if="iinMasked" class="muted small tabular">{{ t('account.profile.iin') }}: {{ iinMasked }}</div>
          <div v-if="profile?.via !== 'egov' && !services.egovAvailable" class="egov-off" data-testid="profile-egov-off">{{ t('account.profile.egovOff') }}</div>
        </div>
      </section>

      <StateError v-if="error" :error="error" class="card" @retry="run" />
      <template v-else>
        <AppCard :title="t('account.profile.personal')" label>
          <Skeleton v-if="loading && !profile" :lines="4" />
          <div v-else class="form-grid two">
            <div class="field"><label for="p-name">{{ t('account.profile.fullName') }}</label><InputText id="p-name" :model-value="profile?.displayName ?? name" disabled /></div>
            <div v-if="hasJob" class="field"><label for="p-position">{{ t('account.profile.position') }}</label><InputText id="p-position" :model-value="profile?.position ?? '—'" disabled /></div>
            <div v-if="hasJob" class="field"><label for="p-specialty">{{ t('account.profile.specialty') }}</label><InputText id="p-specialty" :model-value="profile?.specialty ?? '—'" disabled /></div>
            <div class="field">
              <label for="p-phone">{{ t('account.profile.phone') }}</label>
              <InputText id="p-phone" v-model="phone" :invalid="!phoneValid" inputmode="tel" autocomplete="tel" placeholder="+7 7__ ___ __ __" data-testid="profile-phone" />
              <span v-if="!phoneValid" class="error">{{ t('validation.phone') }}</span>
            </div>
          </div>
          <p v-if="hasJob" class="caption by-admin">{{ t('account.profile.byAdminJob') }}</p>
        </AppCard>
        <div class="grid cols-2">
          <AppCard :title="t('account.profile.email')" label>
            <template #header><StatusTag v-if="emailVerified !== null" :value="emailVerified ? t('account.profile.emailVerified') : t('account.profile.emailNotVerified')" :tone="emailVerified ? 'ok' : 'warn'" /></template>
            <div class="email-row">{{ profile?.email ?? auth.email ?? '—' }}</div>
            <p class="caption email-note">{{ t('account.profile.emailByAdmin') }}</p>
          </AppCard>
          <AppCard :title="t('account.profile.languageRegion')" label>
            <div class="form-grid two">
              <div class="field"><label for="p-lang">{{ t('account.profile.language') }}</label><Select id="p-lang" v-model="language" :options="languages" option-label="label" option-value="value" :disabled="!profile" /></div>
              <div class="field"><label for="p-tz">{{ t('account.profile.timeZone') }}</label><Select id="p-tz" v-model="timeZone" :options="zones" option-label="label" option-value="value" :disabled="!profile" /></div>
            </div>
          </AppCard>
        </div>
        <ErrorBox :error="saveError" />
        <div class="form-actions">
          <Button :label="t('common.cancel')" severity="secondary" :disabled="!dirty || saving" @click="reset" />
          <Button :label="t('account.saveChanges')" :loading="saving" :disabled="!dirty || !phoneValid" data-testid="profile-save" @click="save" />
        </div>
      </template>
    </div>
  </PageShell>
</template>

<style scoped>
/* аккаунт (account-profile-new): колонка 880 по центру, карточки padding 24 */
.page { max-width: 1120px; }
.card { padding: 24px; }
.account-col { display: flex; flex-direction: column; gap: 16px; }
.who { display: flex; align-items: center; gap: 18px; }
.avatar { width: 60px; height: 60px; border-radius: 50%; background: var(--accent-soft); color: var(--accent-strong); display: grid; place-items: center; font-size: 19px; font-weight: var(--fw-extrabold); flex: none; }
.who-main { display: flex; flex-direction: column; gap: 4px; min-width: 0; }
.who-name { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; font-size: 17px; font-weight: var(--fw-extrabold); letter-spacing: -0.01em; }
.egov-off { font-size: var(--fs-sm); color: var(--warning-text); margin-top: 2px; }
.form-grid.two { grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 16px 20px; }
@media (max-width: 600px) { .form-grid.two { grid-template-columns: 1fr; } }
.form-grid.two :deep(.p-inputtext), .form-grid.two :deep(.p-select) { min-height: 44px; border-radius: var(--radius-lg); }
.by-admin { margin: 12px 0 0; color: var(--text-faint); }
.email-row { font-size: var(--fs-md); font-weight: var(--fw-bold); }
.email-note { margin: 8px 0 0; color: var(--text-faint); }
.form-actions { display: flex; justify-content: flex-end; gap: 10px; }
</style>
