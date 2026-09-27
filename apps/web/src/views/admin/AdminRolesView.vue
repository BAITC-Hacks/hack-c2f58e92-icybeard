<script setup lang="ts">
import Button from 'primevue/button'
import { useToast } from 'primevue/usetoast'
import { computed, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { admin } from '@/api/endpoints'
import type { PermissionScope, RoleChange, RolesResponse } from '@/api/types'
import CreateRoleDialog from '@/components/admin/CreateRoleDialog.vue'
import RoleMatrix from '@/components/admin/RoleMatrix.vue'
import RolePanel from '@/components/admin/RolePanel.vue'
import ErrorBox from '@/components/ErrorBox.vue'
import AsyncState from '@/components/states/AsyncState.vue'
import PageShell from '@/components/ui/PageShell.vue'
import SidePanel from '@/components/ui/SidePanel.vue'
import { useAsync } from '@/composables/useAsync'
import { useLocaleFormat } from '@/composables/useLocaleFormat'
import { permissionTitle, roleTitle, type Titled } from '@/lib/labels'
import { MATRIX_PERMISSIONS, nextScope, ROLE_KEYS, supportsOwnScope } from '@/lib/permissions'

/** Роли и доступ (W-Admin-Roles, admin.roles): матрица 14 разрешений × роли, выбранная роль подсвечена, клик по её
 * ячейке переключает нет → своя орг. → разрешено (у ролей без mo_code — нет ⇄ разрешено); строка admin не
 * редактируется. Справа — панель роли, «Сохранить» (PUT /admin/roles/{key}/permissions), «Дублировать роль»;
 * сверху — «История изменений» и «Создать роль». */
const DEFAULT_ROLE = 'org_admin'
const { t } = useI18n()
const toast = useToast()
const { date } = useLocaleFormat()
const data = useAsync<RolesResponse>(() => admin.roles())
const history = useAsync<{ items: RoleChange[] }>(() => admin.roleHistory())
const selected = ref<string | null>(null)
/** Несохранённые изменения выбранной роли: разрешение → новый scope (null — снять). */
const draft = ref<Record<string, PermissionScope | null>>({})
const saving = ref(false)
const saveError = ref<unknown>(null)
const historyOpen = ref(false)
const createOpen = ref(false)
const copyFrom = ref<string | null>(null)

const roleCatalog = computed<Record<string, Titled>>(() => Object.fromEntries((data.data.value?.roles ?? []).map((r) => [r.key, r])))
const permissionCatalog = computed<Record<string, Titled>>(() => Object.fromEntries((data.data.value?.permissions ?? []).map((p) => [p.code, p])))
/** Строки матрицы: 14 разрешений в порядке доски, затем неизвестные клиенту (без системных). */
const permissions = computed(() => {
  const catalog = (data.data.value?.permissions ?? []).filter((p) => !p.system).map((p) => p.code)
  const known = MATRIX_PERMISSIONS.filter((code) => catalog.length === 0 || catalog.includes(code))
  return [...known, ...catalog.filter((code) => !(MATRIX_PERMISSIONS as readonly string[]).includes(code))]
})
/** Колонки в порядке доски: встроенные роли по матрице docs/rbac.md, созданные — перед администратором системы. */
const orderedRoles = computed(() => {
  const rank = (key: string) => (key === 'admin' ? 1000 : (ROLE_KEYS as readonly string[]).includes(key) ? (ROLE_KEYS as readonly string[]).indexOf(key) : 500)
  return [...(data.data.value?.roles ?? [])].sort((a, b) => rank(a.key) - rank(b.key) || a.key.localeCompare(b.key))
})
const role = computed(() => data.data.value?.roles.find((r) => r.key === selected.value) ?? null)
const lockedPermissions = computed(() => (data.data.value?.permissions ?? []).filter((p) => p.editable === false).map((p) => p.code))
const pendingChanges = computed(() => Object.keys(draft.value).length)
const lead = computed(() => (data.data.value ? t('admin.roles.lead', { roles: data.data.value.roles.length, permissions: permissions.value.length }) : t('admin.roles.leadShort')))

function savedScope(roleKey: string, permission: string): PermissionScope | null {
  return data.data.value?.matrix.find((c) => c.role === roleKey && c.permission === permission)?.scope ?? null
}
function scopeOf(roleKey: string, permission: string): PermissionScope | null {
  if (roleKey === selected.value && permission in draft.value) return draft.value[permission] ?? null
  return savedScope(roleKey, permission)
}
const changed = (roleKey: string, permission: string) => roleKey === selected.value && permission in draft.value

function toggle(roleKey: string, permission: string) {
  const role = data.data.value?.roles.find((r) => r.key === roleKey)
  const withOwn = role ? !role.builtin || supportsOwnScope(roleKey) : false
  const next = nextScope(scopeOf(roleKey, permission), withOwn)
  const copy = { ...draft.value }
  if (next === savedScope(roleKey, permission)) delete copy[permission]
  else copy[permission] = next
  draft.value = copy
}

function select(roleKey: string) {
  if (roleKey === selected.value) return
  if (pendingChanges.value && !window.confirm(t('admin.roles.discardConfirm'))) return
  draft.value = {}
  selected.value = roleKey
}

async function save() {
  if (!selected.value || !pendingChanges.value) return
  saving.value = true
  saveError.value = null
  try {
    await admin.saveRole(selected.value, { changes: Object.entries(draft.value).map(([permission, scope]) => ({ permission, scope })) })
    draft.value = {}
    toast.add({ severity: 'success', summary: t('admin.roles.saved'), life: 3000 })
    await Promise.all([data.run(), history.run()])
  } catch (e) {
    saveError.value = e
  } finally {
    saving.value = false
  }
}

function openCreate(from: string | null) {
  copyFrom.value = from
  createOpen.value = true
}

async function created(key: string) {
  toast.add({ severity: 'success', summary: t('admin.roles.created'), life: 3000 })
  await Promise.all([data.run(), history.run()])
  draft.value = {}
  selected.value = key
}

watch(() => data.data.value, (value) => {
  if (value && (!selected.value || !value.roles.some((r) => r.key === selected.value))) selected.value = value.roles.some((r) => r.key === DEFAULT_ROLE) ? DEFAULT_ROLE : value.roles[0]?.key ?? null
})
onMounted(() => Promise.all([data.run(), history.run()]))
</script>

<template>
  <PageShell :title="t('admin.roles.title')" :lead="lead">
    <template #actions>
      <Button :label="t('admin.roles.history')" icon="pi pi-clock" severity="secondary" data-testid="roles-history" @click="historyOpen = true" />
      <Button :label="t('admin.roles.create')" icon="pi pi-plus" data-testid="roles-create" @click="openCreate(null)" />
    </template>
    <div class="legend">
      <span class="legend-item"><span class="mark all"><i class="pi pi-check" /></span>{{ t('admin.roles.allowed') }}</span>
      <span class="legend-item"><span class="mark part"><i class="pi pi-check" /></span>{{ t('admin.roles.partial') }}</span>
      <span class="legend-item"><span class="dot" />{{ t('admin.roles.none') }}</span>
      <span class="spacer" />
      <span v-if="role" class="caption">{{ t('admin.roles.selected', { role: roleTitle(role.key, roleCatalog) }) }}</span>
    </div>
    <div class="with-panel">
      <section class="card">
        <AsyncState :loading="data.loading.value" :error="data.error.value" :empty="!data.data.value?.roles.length" :lines="14" :empty-title="t('admin.roles.empty')" empty-icon="pi pi-shield" @retry="data.run">
          <RoleMatrix :roles="orderedRoles" :permissions="permissions" :selected="selected" :scope-of="scopeOf" :changed="changed" :role-catalog="roleCatalog" :permission-catalog="permissionCatalog" :locked-permissions="lockedPermissions" @select="select" @toggle="toggle" />
        </AsyncState>
      </section>
      <aside class="panel-col">
        <RolePanel v-if="role" :role="role" :users="data.data.value?.usersByRole[role.key] ?? null" :history="(history.data.value?.items ?? []).filter((h) => h.role === role!.key)" :pending-changes="pendingChanges" :saving="saving" :role-catalog="roleCatalog" :permission-catalog="permissionCatalog" @save="save" @discard="draft = {}" @duplicate="openCreate(role.key)" />
        <ErrorBox :error="saveError" />
      </aside>
    </div>

    <SidePanel v-model:visible="historyOpen" :title="t('admin.roles.history')" :subtitle="t('admin.roles.historyNote')">
      <AsyncState :loading="history.loading.value" :error="history.error.value" :empty="!history.data.value?.items.length" skeleton="lines" :empty-title="t('admin.roles.noChanges')" empty-icon="pi pi-clock" @retry="history.run">
        <div class="rows">
          <div v-for="c in history.data.value!.items" :key="c.id" class="row">
            <span class="row-main">{{ roleTitle(c.role, roleCatalog) }} · {{ permissionTitle(c.permission, permissionCatalog) }}<div class="row-sub">{{ date(c.at) }} · {{ c.actor }}<template v-if="c.comment"> · «{{ c.comment }}»</template></div></span>
            <span class="row-value small">{{ c.oldScope ? t(`admin.roles.scope.${c.oldScope}`) : t('admin.roles.none') }} → {{ c.newScope ? t(`admin.roles.scope.${c.newScope}`) : t('admin.roles.none') }}</span>
          </div>
        </div>
      </AsyncState>
    </SidePanel>
    <CreateRoleDialog v-model:visible="createOpen" :roles="data.data.value?.roles ?? []" :copy-from="copyFrom" :role-catalog="roleCatalog" @created="created" />
  </PageShell>
</template>

<style scoped>
.legend { display: flex; align-items: center; gap: 20px; flex-wrap: wrap; font-size: var(--dm-text-sm); color: var(--dm-muted); }
.legend-item { display: inline-flex; align-items: center; gap: 8px; }
.spacer { flex: 1; }
.mark { width: 20px; height: 20px; border-radius: 50%; display: grid; place-items: center; font-size: 10px; }
.mark.all { background: var(--dm-ok-soft); color: var(--dm-ok); }
.mark.part { background: var(--dm-info-soft); color: var(--dm-info); }
.dot { width: 6px; height: 6px; border-radius: 50%; background: var(--dm-dot-idle); }
.with-panel { display: grid; grid-template-columns: minmax(0, 1fr) 300px; gap: 16px; align-items: start; }
.panel-col { display: flex; flex-direction: column; gap: 12px; position: sticky; top: 16px; }
@media (max-width: 1200px) { .with-panel { grid-template-columns: 1fr; } .panel-col { position: static; } }
</style>
