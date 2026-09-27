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
import { useRefdataStore } from '@/stores/refdata'

/** Панель пользователя (W-Admin-Users, справа): аватар, имя, «логин · eGov/логин · с даты»; роль (при scope own —
 * только врач и администратор организации), организация (у ролей с mo_code; при own — своя, без выбора), доступ по
 * разрешениям роли; «Сохранить» и «Заблокировать»/«Разблокировать». */
const props = defineProps<{ user: AdminUser; scope: Scope | null; ownMoCode: string | null; organizations: OrganizationItem[]; matrix?: MatrixCell[] | null; busy?: boolean }>()
const emit = defineEmits<{ save: [{ role: string; moCode: string | null; regionKato: string | null }]; block: []; unblock: [] }>()
const { t } = useI18n()
const orgLabel = (o: OrganizationItem) => `${shortOrgName(o.name)} · ${o.moCode}`
const orgTitle = (o: OrganizationItem) => o.name
const { date } = useLocaleFormat()
const refdata = useRefdataStore()

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
  <section class="card user-panel" data-testid="user-panel">
    <div class="head">
      <span class="avatar" aria-hidden="true">{{ initials(user.displayName ?? user.username) }}</span>
      <div class="head-main">
        <div class="name">{{ user.displayName ?? user.username }}</div>
        <div class="caption">{{ [user.username, user.via ? t(`admin.via.${user.via}`) : null, user.createdAt ? t('admin.users.since', { date: date(user.createdAt) }) : null].filter(Boolean).join(' · ') }}</div>
      </div>
    </div>

    <div class="field">
      <label for="u-role">{{ t('admin.users.colRole') }}</label>
      <Select id="u-role" v-model="role" :options="roleOptions" option-label="label" option-value="value" data-testid="user-role" />
    </div>
    <div v-if="withOrganization" class="field">
      <label for="u-org">{{ t('admin.users.colOrg') }}</label>
      <div v-if="orgFixed" class="fixed">{{ shortOrgName(refdata.organizationName(ownMoCode)) }} · {{ ownMoCode }}<div class="caption">{{ t('admin.users.ownOrgOnly') }}</div></div>
      <SearchSelect v-else v-model="moCode" :options="organizations" :option-label="orgLabel" option-value="moCode" :option-title="orgTitle" :placeholder="t('admin.users.pickOrg')" />
    </div>
    <div class="field">
      <label for="u-region">{{ t('admin.users.colRegion') }}</label>
      <Select id="u-region" v-model="regionKato" :options="regionOptions" option-label="label" option-value="value" show-clear filter :placeholder="t('admin.notSet')" />
    </div>

    <div class="eyebrow access-title">{{ t('admin.users.access') }}</div>
    <ul class="access" data-testid="user-access">
      <li v-for="p in access" :key="p.code"><i class="pi pi-check" aria-hidden="true" /><span>{{ permissionTitle(p.code) }}<span v-if="p.scope === 'own'" class="muted"> · {{ t('admin.ownOnly') }}</span></span></li>
      <li v-if="access.length === 0" class="muted">{{ t('admin.users.noAccess') }}</li>
    </ul>
    <p class="caption">{{ matrix ? t('admin.users.accessFromApi') : t('admin.users.accessFromMatrix') }}</p>

    <div class="buttons">
      <Button :label="t('common.save')" :disabled="!canSave" :loading="busy" data-testid="user-save" @click="save" />
      <Button v-if="user.status === 'blocked'" :label="t('admin.users.unblock')" severity="secondary" :disabled="busy" data-testid="user-unblock" @click="emit('unblock')" />
      <Button v-else :label="t('admin.users.block')" severity="danger" :disabled="busy" data-testid="user-block" @click="emit('block')" />
    </div>
    <StatusTag v-if="user.status !== 'active'" class="status" :value="t(`admin.users.status.${user.status}`)" :tone="user.status === 'invited' ? 'info' : 'neutral'" />
  </section>
</template>

<style scoped>
.user-panel { display: flex; flex-direction: column; gap: 14px; }
.head { display: flex; align-items: center; gap: 12px; }
.avatar { width: 48px; height: 48px; border-radius: 50%; background: var(--dm-neutral-soft); display: grid; place-items: center; font-weight: 500; flex: none; }
.head-main { min-width: 0; }
.name { font-size: var(--dm-text-lg); font-weight: 500; letter-spacing: -0.01em; }
.fixed { font-size: var(--dm-text-md); }
.access-title { margin-top: 4px; }
.access { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; }
.access li { display: flex; gap: 10px; align-items: flex-start; padding: 8px 0; border-bottom: 1px solid var(--dm-hairline); font-size: var(--dm-text-sm); }
.access li:last-child { border-bottom: 0; }
.access i { width: 20px; height: 20px; border-radius: 50%; background: var(--dm-ok-soft); color: var(--dm-ok); display: grid; place-items: center; font-size: 10px; flex: none; }
.buttons { display: flex; gap: 8px; flex-wrap: wrap; }
.status { align-self: flex-start; }
</style>
