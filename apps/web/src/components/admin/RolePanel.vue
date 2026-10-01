<script setup lang="ts">
import Button from 'primevue/button'
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import type { PermissionScope, RoleChange, RoleInfo } from '@/api/types'
import StatusTag from '@/components/ui/StatusTag.vue'
import { useLocaleFormat } from '@/composables/useLocaleFormat'
import { permissionHint, permissionTitle, type Titled } from '@/lib/labels'
import { supportsOwnScope } from '@/lib/permissions'

/** Содержимое панели роли (W-Admin-Roles, открывается справа по клику на название роли): описание для людей
 * (admin.roles.about.* у встроенных ролей, иначе описание из API), факты (сколько пользователей, встроенная или
 * созданная), «Что может эта роль» — разрешения с пояснением и scope словами (с учётом несохранённых изменений,
 * они помечены «изменено»), «Последние изменения» из истории. Кнопки: «Сохранить (n)», «Отменить изменения»,
 * «Дублировать роль». Роль admin не редактируется. */
const props = defineProps<{
  role: RoleInfo
  users: number | null
  history: RoleChange[]
  permissions: string[]
  scopeOf: (role: string, permission: string) => PermissionScope | null
  changed: (role: string, permission: string) => boolean
  pendingChanges: number
  saving: boolean
  roleCatalog: Record<string, Titled>
  permissionCatalog: Record<string, Titled>
}>()
const emit = defineEmits<{ save: []; duplicate: []; discard: [] }>()
const { t, te, locale } = useI18n()
const { date, num } = useLocaleFormat()

const description = computed(() => {
  const about = `admin.roles.about.${props.role.key}`
  if (props.role.builtin && te(about)) return t(about)
  return (locale.value === 'kk' ? props.role.descriptionKk || props.role.descriptionRu : props.role.descriptionRu) || t('admin.roles.noDescription')
})
/** Разрешения роли (с учётом черновика): только те, где есть доступ. */
const granted = computed(() => props.permissions.map((code) => ({ code, scope: props.scopeOf(props.role.key, code), changed: props.changed(props.role.key, code) })).filter((p) => p.scope !== null))
const recent = computed(() => props.history.slice(0, 5))
function describe(change: RoleChange): string {
  const name = permissionTitle(change.permission, props.permissionCatalog)
  if (change.oldScope === null && change.newScope) return t(change.newScope === 'own' ? 'admin.roles.changeAddedOwn' : 'admin.roles.changeAdded', { name })
  if (change.newScope === null) return t('admin.roles.changeRemoved', { name })
  return t('admin.roles.changeScope', { name, from: t(`admin.roles.scope.${change.oldScope}`), to: t(`admin.roles.scope.${change.newScope}`) })
}
</script>

<template>
  <div class="role-panel" data-testid="role-panel">
    <p class="desc">{{ description }}</p>
    <dl class="facts">
      <dt>{{ t('admin.roles.usersN') }}</dt><dd class="tabular">{{ users === null ? '—' : num(users) }}</dd>
      <dt>{{ t('admin.roles.roleLabel') }}</dt><dd>{{ role.builtin ? t('admin.roles.typeBuiltin') : t('admin.roles.typeCustom') }} <span class="mono caption">· {{ role.key }}</span></dd>
    </dl>
    <p v-if="role.key === 'admin'" class="caption note">{{ t('admin.roles.lockedHint') }}</p>
    <p v-else-if="supportsOwnScope(role.key) || !role.builtin" class="caption note">{{ t('admin.roles.orgNote') }}</p>

    <h3 class="panel-sub">{{ t('admin.roles.canTitle') }} <span class="caption">· {{ t('admin.roles.canCount', { n: granted.length, total: permissions.length }) }}</span></h3>
    <p v-if="granted.length === 0" class="muted small">{{ t('admin.roles.canNone') }}</p>
    <div v-else class="rows">
      <div v-for="p in granted" :key="p.code" class="row can-row" :class="{ changed: p.changed }">
        <span class="row-main">
          <span class="can-title">{{ permissionTitle(p.code, permissionCatalog) }}</span>
          <span v-if="permissionHint(p.code)" class="row-sub">{{ permissionHint(p.code) }}</span>
        </span>
        <span class="row-value">
          <span v-if="p.changed" class="caption changed-mark">{{ t('admin.roles.changedMark') }}</span>
          <StatusTag :value="t(`admin.roles.scope.${p.scope}`)" :tone="p.scope === 'own' ? 'warn' : 'ok'" />
        </span>
      </div>
    </div>

    <h3 class="panel-sub">{{ t('admin.roles.recentTitle') }}</h3>
    <div v-if="recent.length" class="rows">
      <div v-for="c in recent" :key="c.id" class="row change">
        <span class="row-main">{{ describe(c) }}<span class="row-sub">{{ date(c.at) }} · {{ c.actor }}<template v-if="c.comment"> · «{{ c.comment }}»</template></span></span>
      </div>
    </div>
    <p v-else class="muted small">{{ t('admin.roles.noChanges') }}</p>

    <div class="buttons">
      <Button v-if="role.key !== 'admin'" :label="pendingChanges ? t('admin.roles.saveN', { n: pendingChanges }) : t('common.save')" :disabled="!pendingChanges" :loading="saving" data-testid="role-save" @click="emit('save')" />
      <Button v-if="pendingChanges" :label="t('admin.roles.discard')" severity="secondary" @click="emit('discard')" />
      <Button :label="t('admin.roles.duplicate')" icon="pi pi-copy" severity="secondary" data-testid="role-duplicate" @click="emit('duplicate')" />
    </div>
  </div>
</template>

<style scoped>
.role-panel { display: flex; flex-direction: column; gap: 12px; }
.desc { margin: 0; line-height: 1.55; font-size: var(--dm-text-base); }
.note { margin: -4px 0 0; line-height: 1.45; }
.panel-sub { font-size: var(--dm-text-base); margin: 8px 0 0; display: flex; align-items: baseline; gap: 6px; flex-wrap: wrap; }
.can-row .row-main { display: flex; flex-direction: column; gap: 2px; }
.can-row.changed .can-title { font-weight: var(--fw-bold); }
.changed-mark { color: var(--dm-accent); }
.change .row-main { display: flex; flex-direction: column; gap: 2px; }
.buttons { display: flex; gap: 8px; flex-wrap: wrap; margin-top: 8px; padding-top: 16px; border-top: 1px solid var(--dm-hairline); }
</style>
