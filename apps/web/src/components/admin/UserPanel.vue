<script setup lang="ts">
import Button from 'primevue/button'
import Select from 'primevue/select'
import { computed, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import type { AdminUser, MatrixCell, OrganizationItem } from '@/api/types'
import SearchSelect from '@/components/ui/SearchSelect.vue'
import StatusTag from '@/components/ui/StatusTag.vue'
import { useLocaleFormat } from '@/composables/useLocaleFormat'
import { assignableRoles, mainRole, rolePermissions } from '@/lib/admin'
import { shortOrgName } from '@/lib/format'
import { initials, permissionTitle, roleTitle } from '@/lib/labels'
import { supportsOwnScope, type Scope } from '@/lib/permissions'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'
import { useServiceStatusStore } from '@/stores/serviceStatus'

/** Панель пользователя (W-Admin-Users, справа): аватар, имя, «логин · способ входа · с даты»; роль (при scope own —
 * только врач и администратор организации), организация (у ролей с mo_code; при own — своя, без выбора), доступ по
 * разрешениям роли; «Сохранить» и «Заблокировать»/«Разблокировать». Пока адрес сервиса eGov mobile не предоставлен
 * (GET /public/service-status), под именем сказано, что вход через eGov недоступен и пользователи входят по логину. */
/** bare — внутри боковой панели: без карточки и без шапки с именем (имя — в заголовке панели). */
const props = defineProps<{ bare?: boolean; user: AdminUser; scope: Scope | null; ownMoCode: string | null; organizations: OrganizationItem[]; matrix?: MatrixCell[] | null; busy?: boolean }>()
const emit = defineEmits<{ save: [{ role: string; moCode: string | null; regionKato: string | null }]; block: []; unblock: [] }>()
const { t } = useI18n()
const auth = useAuthStore()
const orgLabel = (o: OrganizationItem) => `${shortOrgName(o.name)} · ${o.moCode}`
const orgTitle = (o: OrganizationItem) => o.name
const { date } = useLocaleFormat()
const refdata = useRefdataStore()
const services = useServiceStatusStore()

const role = ref<string>('')
const moCode = ref<string | null>(null)
const regionKato = ref<string | null>(null)
function reset() {
  role.value = mainRole(props.user) ?? ''
  moCode.value = props.user.moCode
  regionKato.value = props.user.regionKato
}
// сброс правок — только при выборе другого пользователя: обновление строки после поиска или сохранения их не стирает
watch(() => props.user.id, reset, { immediate: true })

const roleOptions = computed(() => assignableRoles(props.scope).map((key) => ({ value: key, label: roleTitle(key) })))
const withOrganization = computed(() => supportsOwnScope(role.value))
const orgFixed = computed(() => props.scope === 'own')
const regionOptions = computed(() => refdata.regions.map((r) => ({ value: r.regionKato, label: r.name })))
const access = computed(() => rolePermissions(role.value, props.matrix))
const dirty = computed(() => role.value !== (mainRole(props.user) ?? '') || moCode.value !== props.user.moCode || regionKato.value !== props.user.regionKato)
const canSave = computed(() => !!role.value && dirty.value && (!withOrganization.value || !!(orgFixed.value ? props.ownMoCode : moCode.value)))

function save() {
  emit('save', { role: role.value, moCode: withOrganization.value ? (orgFixed.value ? props.ownMoCode : moCode.value) : null, regionKato: regionKato.value })
}
</script>

<template>
  <section class="user-panel" :class="{ card: !bare }" data-testid="user-panel">
    <div v-if="!bare" class="head">
      <span class="avatar" aria-hidden="true">{{ initials(user.displayName ?? user.username) }}</span>
      <div class="head-main">
        <div class="name">{{ user.displayName ?? user.username }}</div>
        <div class="caption">{{ [user.username, user.via ? t(`admin.via.${user.via}`) : null, user.createdAt ? t('admin.users.since', { date: date(user.createdAt) }) : null].filter(Boolean).join(' · ') }}</div>
      </div>
    </div>
    <div v-if="bare" class="facts">
      <StatusTag :value="t(`admin.users.status.${user.status}`)" :tone="user.status === 'active' ? 'ok' : user.status === 'invited' ? 'info' : 'neutral'" />
      <span class="caption">{{ [user.via ? t(`admin.via.${user.via}`) : null, user.createdAt ? t('admin.users.since', { date: date(user.createdAt) }) : null].filter(Boolean).join(' · ') }}</span>
    </div>
    <p v-if="!services.egovAvailable" class="caption egov-off" data-testid="user-egov-off">{{ t('admin.users.egovOff') }}</p>

    <div v-if="withOrganization" class="field">
      <label for="u-org">{{ t('admin.users.colOrg') }}</label>
      <div v-if="orgFixed" class="fixed">{{ shortOrgName(refdata.organizationName(ownMoCode)) }} · {{ ownMoCode }}<div class="caption">{{ t('admin.users.ownOrgOnly') }}</div></div>
      <SearchSelect v-else v-model="moCode" :options="organizations" :option-label="orgLabel" option-value="moCode" :option-title="orgTitle" :placeholder="t('admin.users.pickOrg')" />
    </div>
    <div class="field">
      <label for="u-role">{{ t('admin.users.colRole') }}</label>
      <Select id="u-role" v-model="role" :options="roleOptions" option-label="label" option-value="value" data-testid="user-role" />
      <span class="caption">{{ t('admin.users.roleHint') }}</span>
    </div>
    <div class="field">
      <label for="u-region">{{ t('admin.users.colRegion') }}</label>
      <Select id="u-region" v-model="regionKato" :options="regionOptions" option-label="label" option-value="value" show-clear filter :placeholder="t('admin.notSet')" />
      <span class="caption">{{ t('admin.users.regionHint') }}</span>
    </div>

    <div class="access-block">
      <div class="access-head">
        <span class="eyebrow">{{ t('admin.users.access') }}</span>
        <span class="caption">{{ t('admin.users.accessCount', { n: access.length }) }}</span>
      </div>
      <ul class="access" data-testid="user-access">
        <li v-for="p in access" :key="p.code" :class="{ own: p.scope === 'own' }"><i class="pi pi-check" aria-hidden="true" />{{ permissionTitle(p.code) }}<span v-if="p.scope === 'own'" class="own-tag">{{ t('admin.ownOnly') }}</span></li>
        <li v-if="access.length === 0" class="muted">{{ t('admin.users.noAccess') }}</li>
      </ul>
      <p class="caption access-note">{{ t('admin.users.accessByRole') }}
        <RouterLink v-if="auth.can('admin.roles')" class="link-arrow small" :to="{ name: 'admin-roles' }">{{ t('admin.users.accessEdit') }}</RouterLink>
      </p>
    </div>

    <div class="buttons">
      <Button :label="t('common.save')" :disabled="!canSave" :loading="busy" data-testid="user-save" @click="save" />
      <Button v-if="user.status === 'blocked'" :label="t('admin.users.unblock')" severity="secondary" :disabled="busy" data-testid="user-unblock" @click="emit('unblock')" />
      <Button v-else :label="t('admin.users.block')" severity="danger" :disabled="busy" data-testid="user-block" @click="emit('block')" />
    </div>
    <StatusTag v-if="!bare && user.status !== 'active'" class="status" :value="t(`admin.users.status.${user.status}`)" :tone="user.status === 'invited' ? 'info' : 'neutral'" />
  </section>
</template>

<style scoped>
.user-panel { display: flex; flex-direction: column; gap: 14px; }
.head { display: flex; align-items: center; gap: 12px; }
.egov-off { margin: -6px 0 0; padding: 10px 12px; border-radius: 10px; background: var(--surface-muted); line-height: 1.45; }
.facts { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
.field .caption { line-height: 1.4; }
.avatar { width: 48px; height: 48px; border-radius: 50%; background: var(--dm-neutral-soft); display: grid; place-items: center; font-weight: 500; flex: none; }
.head-main { min-width: 0; }
.name { font-size: var(--dm-text-lg); font-weight: 500; letter-spacing: -0.01em; }
.fixed { font-size: var(--dm-text-md); }
.access-block { display: flex; flex-direction: column; gap: 10px; padding: 14px 16px; border-radius: 14px; background: var(--surface-muted); }
.access-head { display: flex; justify-content: space-between; align-items: baseline; }
.access { list-style: none; margin: 0; padding: 0; display: flex; flex-wrap: wrap; gap: 6px; }
.access li { display: inline-flex; gap: 6px; align-items: center; padding: 5px 10px; border-radius: 999px; background: var(--surface); font-size: var(--dm-text-sm); line-height: 1.3; }
.access i { color: var(--dm-ok); font-size: 11px; }
.own-tag { font-size: 11px; color: var(--text-muted); }
.access-note { margin: 0; line-height: 1.45; }
.buttons { display: flex; gap: 8px; flex-wrap: wrap; }
.status { align-self: flex-start; }
</style>
