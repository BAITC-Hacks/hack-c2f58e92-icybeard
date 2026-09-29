<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import type { PermissionScope, RoleInfo } from '@/api/types'
import { permissionTitle, roleTitle, type Titled } from '@/lib/labels'

/** Матрица «разрешение × роль» (W-Admin-Roles): ✓ — разрешено, ✓ + «своя орг.» — только своя организация, точка —
 * нет доступа. Колонка выбранной роли подсвечена; клик по ячейке выбранной роли переключает scope, по ячейке
 * другой роли — выбирает роль. Колонка admin (и роли с editable: false) и строки с editable: false заблокированы. */
const props = defineProps<{
  roles: RoleInfo[]
  permissions: string[]
  selected: string | null
  scopeOf: (role: string, permission: string) => PermissionScope | null
  changed: (role: string, permission: string) => boolean
  roleCatalog: Record<string, Titled>
  permissionCatalog: Record<string, Titled>
  /** разрешения, которые API запрещает менять (editable: false) */
  lockedPermissions?: string[]
}>()
const emit = defineEmits<{ select: [string]; toggle: [string, string] }>()
const { t } = useI18n()
const LOCKED = 'admin'
const lockedRole = (key: string) => key === LOCKED || props.roles.find((r) => r.key === key)?.editable === false
const locked = (key: string, permission: string) => lockedRole(key) || (props.lockedPermissions ?? []).includes(permission)

function click(role: string, permission: string) {
  if (role !== props.selected) emit('select', role)
  else if (!locked(role, permission)) emit('toggle', role, permission)
}
function cellLabel(role: string, permission: string): string {
  const scope = props.scopeOf(role, permission)
  const state = scope === 'all' ? t('admin.roles.allowed') : scope === 'own' ? t('admin.roles.partial') : t('admin.roles.none')
  return `${roleTitle(role, props.roleCatalog)} · ${permissionTitle(permission, props.permissionCatalog)}: ${state}`
}
</script>

<template>
  <div class="table-wrap">
    <table class="matrix" data-testid="roles-matrix">
      <thead>
        <tr>
          <th class="perm-col">{{ t('admin.roles.permission') }}</th>
          <th v-for="r in roles" :key="r.key" class="role-col" :class="{ selected: r.key === selected }">
            <button type="button" class="role-head" :aria-pressed="r.key === selected" :data-testid="`role-col-${r.key}`" @click="emit('select', r.key)">{{ roleTitle(r.key, roleCatalog) }}</button>
          </th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="p in permissions" :key="p">
          <th class="perm" scope="row">{{ permissionTitle(p, permissionCatalog) }}</th>
          <td v-for="r in roles" :key="r.key" class="cell" :class="{ selected: r.key === selected, locked: locked(r.key, p), changed: changed(r.key, p) }">
            <button type="button" class="cell-btn" :disabled="r.key === selected && locked(r.key, p)" :title="lockedRole(r.key) ? t('admin.roles.lockedHint') : cellLabel(r.key, p)" :aria-label="cellLabel(r.key, p)" :data-testid="`cell-${r.key}-${p}`" @click="click(r.key, p)">
              <span v-if="scopeOf(r.key, p) === 'all'" class="mark all"><i class="pi pi-check" aria-hidden="true" /></span>
              <span v-else-if="scopeOf(r.key, p) === 'own'" class="own"><span class="mark part"><i class="pi pi-check" aria-hidden="true" /></span><span class="own-label">{{ t('admin.roles.ownShort') }}</span></span>
              <span v-else class="dot" aria-hidden="true" />
            </button>
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>

<style scoped>
.matrix { width: 100%; border-collapse: collapse; font-size: var(--dm-text-sm); }
.matrix th, .matrix td { border-bottom: 1px solid var(--dm-hairline); }
.perm-col { text-align: left; vertical-align: bottom; font-size: 10.5px; font-weight: var(--fw-bold); text-transform: uppercase; letter-spacing: 0.06em; color: var(--dm-muted); padding: 8px 12px 10px 0; }
.role-col { vertical-align: bottom; padding: 8px 4px 10px; min-width: 76px; }
.role-col.selected, .cell.selected { background: var(--dm-neutral-soft); }
.role-col.selected { border-radius: var(--dm-radius-sm) var(--dm-radius-sm) 0 0; }
.role-head { border: 0; background: none; font: inherit; font-size: 10.5px; font-weight: var(--fw-bold); text-transform: uppercase; letter-spacing: 0.04em; color: var(--dm-muted); cursor: pointer; text-align: center; width: 100%; hyphens: auto; }
.role-col.selected .role-head { color: var(--dm-ink); }
.perm { text-align: left; font-weight: 400; padding: 8px 12px 8px 0; min-width: 180px; }
.cell { text-align: center; padding: 0; height: 40px; }
.cell-btn { border: 0; background: none; width: 100%; height: 100%; min-height: 40px; cursor: pointer; display: grid; place-items: center; padding: 4px; }
.cell.locked .cell-btn { cursor: not-allowed; }
.cell.changed .cell-btn { box-shadow: inset 0 0 0 2px var(--dm-accent); border-radius: var(--dm-radius-sm); }
.mark { width: 20px; height: 20px; border-radius: 6px; display: grid; place-items: center; font-size: 10px; }
.mark.all { background: var(--success-bg); color: var(--success-text); }
.mark.part { background: var(--warning-bg); color: var(--warning-text); }
.own { display: flex; flex-direction: column; align-items: center; gap: 2px; }
.own-label { font-size: 11px; color: var(--dm-muted); white-space: nowrap; }
.dot { width: 6px; height: 6px; border-radius: 50%; background: var(--dm-dot-idle); }
</style>
