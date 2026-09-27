<script setup lang="ts">
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import InputText from 'primevue/inputtext'
import Select from 'primevue/select'
import { useToast } from 'primevue/usetoast'
import { computed, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { ApiError } from '@/api/client'
import { admin } from '@/api/endpoints'
import type { InviteResponse, OrganizationItem } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import InviteLink from './InviteLink.vue'
import SearchSelect from '@/components/ui/SearchSelect.vue'
import { assignableRoles } from '@/lib/admin'
import { shortOrgName } from '@/lib/format'
import { roleTitle } from '@/lib/labels'
import { supportsOwnScope, type Scope } from '@/lib/permissions'
import { isEmail } from '@/lib/validation'
import { useRefdataStore } from '@/stores/refdata'

/** «Пригласить пользователя»: ФИО, почта, роль, организация (у ролей с mo_code), регион. POST /admin/users/invite;
 * без SMTP API отвечает `emailSent: false` и `inviteUrl` — ссылка показывается с кнопкой «Скопировать» для ручной
 * передачи. При scope own — только врач/администратор своей организации. */
const props = defineProps<{ scope: Scope | null; ownMoCode: string | null; organizations: OrganizationItem[]; defaultRole?: string }>()
const visible = defineModel<boolean>('visible', { default: false })
const emit = defineEmits<{ invited: [] }>()
const { t } = useI18n()
const orgLabel = (o: OrganizationItem) => `${shortOrgName(o.name)} · ${o.moCode}`
const orgTitle = (o: OrganizationItem) => o.name
const toast = useToast()
const refdata = useRefdataStore()

const displayName = ref('')
const email = ref('')
const role = ref<string>('doctor')
const moCode = ref<string | null>(null)
const regionKato = ref<string | null>(null)
const touched = ref(false)
const sending = ref(false)
const error = ref<unknown>(null)
const result = ref<InviteResponse | null>(null)

watch(visible, (open) => {
  if (!open) return
  displayName.value = ''
  email.value = ''
  role.value = props.defaultRole ?? 'doctor'
  moCode.value = props.scope === 'own' ? props.ownMoCode : null
  regionKato.value = null
  touched.value = false
  error.value = null
  result.value = null
})

const roleOptions = computed(() => assignableRoles(props.scope).map((key) => ({ value: key, label: roleTitle(key) })))
const withOrganization = computed(() => supportsOwnScope(role.value))
const regionOptions = computed(() => refdata.regions.map((r) => ({ value: r.regionKato, label: r.name })))
const fieldError = (name: string) => (error.value instanceof ApiError ? error.value.field(name) : undefined)
const errors = computed(() => ({
  displayName: !displayName.value.trim() ? t('validation.required') : fieldError('displayName'),
  email: !isEmail(email.value) ? t('validation.email') : fieldError('email'),
  moCode: withOrganization.value && !moCode.value ? t('validation.required') : fieldError('moCode'),
}))
const valid = computed(() => !Object.values(errors.value).some(Boolean))

async function send() {
  touched.value = true
  if (!valid.value) return
  sending.value = true
  error.value = null
  try {
    result.value = await admin.invite({
      email: email.value.trim(), displayName: displayName.value.trim(), role: role.value,
      moCode: withOrganization.value ? moCode.value : null, regionKato: regionKato.value,
    })
    emit('invited')
    if (result.value.emailSent) toast.add({ severity: 'success', summary: t('admin.invite.sent', { email: email.value.trim() }), life: 4000 })
  } catch (e) {
    error.value = e
  } finally {
    sending.value = false
  }
}

</script>

<template>
  <Dialog v-model:visible="visible" modal :header="t('admin.invite.title')" :style="{ width: 'min(520px, 94vw)' }" data-testid="invite-dialog">
    <div v-if="result" class="result" data-testid="invite-result">
      <template v-if="result.emailSent"><p>{{ t('admin.invite.sent', { email }) }}</p></template>
      <template v-else>
        <p>{{ t('admin.invite.noEmail') }}</p>
        <InviteLink v-if="result.inviteUrl" :url="result.inviteUrl" />
      </template>
      <p class="caption">{{ t('admin.invite.validity') }}</p>
    </div>
    <form v-else class="form-col" novalidate @submit.prevent="send">
      <div class="field"><label for="i-name">{{ t('admin.invite.name') }}</label><InputText id="i-name" v-model="displayName" :invalid="touched && !!errors.displayName" data-testid="invite-name" /><span v-if="touched && errors.displayName" class="error">{{ errors.displayName }}</span></div>
      <div class="field"><label for="i-email">{{ t('admin.invite.email') }}</label><InputText id="i-email" v-model="email" type="email" autocomplete="off" :invalid="touched && !!errors.email" data-testid="invite-email" /><span v-if="touched && errors.email" class="error">{{ errors.email }}</span></div>
      <div class="field"><label for="i-role">{{ t('admin.users.colRole') }}</label><Select id="i-role" v-model="role" :options="roleOptions" option-label="label" option-value="value" data-testid="invite-role" /></div>
      <div v-if="withOrganization" class="field">
        <label for="i-org">{{ t('admin.users.colOrg') }}</label>
        <div v-if="scope === 'own'" class="fixed">{{ shortOrgName(refdata.organizationName(ownMoCode)) }} · {{ ownMoCode }}</div>
        <SearchSelect v-else v-model="moCode" :options="organizations" :option-label="orgLabel" option-value="moCode" :option-title="orgTitle" :placeholder="t('admin.users.pickOrg')" />
        <span v-if="touched && errors.moCode" class="error">{{ errors.moCode }}</span>
      </div>
      <div class="field"><label for="i-region">{{ t('admin.users.colRegion') }}</label><Select id="i-region" v-model="regionKato" :options="regionOptions" option-label="label" option-value="value" show-clear filter :placeholder="t('admin.notSet')" /></div>
      <ErrorBox v-if="!(error instanceof ApiError && error.status === 422)" :error="error" />
      <button type="submit" hidden />
    </form>
    <template #footer>
      <Button v-if="result" :label="t('common.close')" @click="visible = false" />
      <template v-else>
        <Button :label="t('common.cancel')" severity="secondary" @click="visible = false" />
        <Button :label="t('admin.invite.submit')" :loading="sending" data-testid="invite-submit" @click="send" />
      </template>
    </template>
  </Dialog>
</template>

<style scoped>
.result p { margin: 0 0 12px; }
.fixed { font-size: var(--dm-text-md); }
</style>
