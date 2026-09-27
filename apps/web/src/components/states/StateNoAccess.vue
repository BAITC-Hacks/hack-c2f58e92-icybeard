<script setup lang="ts">
import { computed, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute } from 'vue-router'
import { ApiError } from '@/api/client'
import { shortOrgName } from '@/lib/format'
import { permissionTitle, roleTitle } from '@/lib/labels'
import { requiredPermissions } from '@/lib/permissions'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'
import StateBlock from './StateBlock.vue'

/** «Нет доступа к разделу» (W-Auth-Blocked, W-States): чья роль и какой раздел, кто выдаёт доступ, и «Запросить
 * доступ →» — POST /me/access-requests { permission, path } (запрос попадает в журнал аудита). Показывается и защитой
 * маршрутов, и на любой странице, где API ответил 403 (detail `other_organization` / `no_organization` — свой текст). */
const props = defineProps<{ permission?: string | null; path?: string | null; detail?: string | null; permissions?: string[] | null; compact?: boolean }>()
const { t } = useI18n()
const auth = useAuthStore()
const refdata = useRefdataStore()
const route = useRoute()

/** Раздел: разрешение, которого не хватило по ответу API (403 permission_required), иначе переданное или из meta маршрута. */
const code = computed(() => props.permissions?.[0] || props.permission || requiredPermissions(route.meta.permission)[0] || null)
const target = computed(() => props.path || route.fullPath)
/** Кто выдаёт доступ: сотруднику организации — её администратор, остальным (и самому администратору организации) —
 * администратор системы (матрица ролей). */
const who = computed(() =>
  auth.moCode && auth.role !== 'org_admin'
    ? t('access.whoOrg', { org: `${shortOrgName(refdata.organizationName(auth.moCode))} (${auth.moCode})` })
    : t('access.whoSystem'),
)
const text = computed(() => {
  if (props.detail === 'other_organization') return t('access.otherOrganization')
  if (props.detail === 'no_organization') return t('access.noOrganization')
  if (props.detail === 'role_not_assignable') return t('access.roleNotAssignable')
  const role = auth.role ? roleTitle(auth.role) : t('access.noRole')
  return code.value ? t('access.textSection', { role, section: permissionTitle(code.value), who: who.value }) : t('access.textGeneric', { role, who: who.value })
})

const state = ref<'idle' | 'sending' | 'sent' | 'failed'>('idle')
const failure = ref('')
async function request() {
  state.value = 'sending'
  try {
    await auth.requestAccess(code.value ?? 'unknown', target.value)
    state.value = 'sent'
  } catch (error) {
    failure.value = error instanceof ApiError ? `${error.status} ${error.title}` : String(error)
    state.value = 'failed'
  }
}
</script>

<template>
  <StateBlock icon="pi pi-lock" :title="t('access.title')" :text="text" :compact="compact" data-testid="state-no-access">
    <span v-if="state === 'sent'" class="sent" data-testid="access-requested"><i class="pi pi-check" aria-hidden="true" /> {{ t('access.sent') }}</span>
    <button v-else type="button" class="link-arrow" :disabled="state === 'sending'" data-testid="request-access" @click="request">{{ t('access.request') }}</button>
    <template #text>
      <p v-if="state === 'failed'" class="failed">{{ t('access.failed', { reason: failure }) }}</p>
      <p v-else-if="state !== 'sent'" class="caption note">{{ t('access.auditNote') }}</p>
    </template>
  </StateBlock>
</template>

<style scoped>
.sent { color: var(--dm-ok); font-weight: 500; font-size: var(--dm-text-md); }
.failed { margin: 0; color: var(--dm-danger); font-size: var(--dm-text-sm); }
.note { margin: 0; }
.link-arrow:disabled { opacity: 0.6; cursor: default; }
</style>
