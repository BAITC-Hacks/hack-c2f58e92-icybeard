<script setup lang="ts">
import Button from 'primevue/button'
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import type { RoleChange, RoleInfo } from '@/api/types'
import { useLocaleFormat } from '@/composables/useLocaleFormat'
import { daysSince } from '@/lib/admin'
import { permissionTitle, roleTitle, type Titled } from '@/lib/labels'

/** Панель выбранной роли (W-Admin-Roles): описание, число пользователей, «Изменения за месяц» (из истории),
 * «Сохранить» (есть несохранённые изменения матрицы), «Дублировать роль». Роль admin не редактируется. */
const props = defineProps<{
  role: RoleInfo
  users: number | null
  history: RoleChange[]
  pendingChanges: number
  saving: boolean
  roleCatalog: Record<string, Titled>
  permissionCatalog: Record<string, Titled>
}>()
const emit = defineEmits<{ save: []; duplicate: []; discard: [] }>()
const { t, locale } = useI18n()
const { date, num } = useLocaleFormat()

const description = computed(() => (locale.value === 'kk' ? props.role.descriptionKk || props.role.descriptionRu : props.role.descriptionRu) ?? '')
const recent = computed(() => props.history.filter((h) => (daysSince(h.at) ?? 99) <= 31).slice(0, 4))
function describe(change: RoleChange): string {
  const name = permissionTitle(change.permission, props.permissionCatalog)
  if (change.oldScope === null && change.newScope) return t(change.newScope === 'own' ? 'admin.roles.changeAddedOwn' : 'admin.roles.changeAdded', { name })
  if (change.newScope === null) return t('admin.roles.changeRemoved', { name })
  return t('admin.roles.changeScope', { name, from: t(`admin.roles.scope.${change.oldScope}`), to: t(`admin.roles.scope.${change.newScope}`) })
}
</script>

<template>
  <section class="card role-panel" data-testid="role-panel">
    <span class="eyebrow">{{ t('admin.roles.roleLabel') }}</span>
    <h2 class="role-title">{{ roleTitle(role.key, roleCatalog) }}</h2>
    <p v-if="description" class="muted small desc">{{ description }}</p>
    <div class="users"><span class="users-n tabular">{{ users === null ? '—' : num(users) }}</span><span class="muted">{{ t('admin.roles.users') }}</span></div>
    <span class="eyebrow">{{ t('admin.roles.monthChanges') }}</span>
    <div v-if="recent.length" class="changes">
      <div v-for="c in recent" :key="c.id" class="change">
        <span class="caption">{{ date(c.at) }} · {{ c.actor }}</span>
        <span class="small">{{ describe(c) }}</span>
      </div>
    </div>
    <p v-else class="muted small">{{ t('admin.roles.noChanges') }}</p>
    <p v-if="role.key === 'admin'" class="caption">{{ t('admin.roles.lockedHint') }}</p>
    <div class="buttons">
      <Button :label="pendingChanges ? t('admin.roles.saveN', { n: pendingChanges }) : t('common.save')" :disabled="!pendingChanges" :loading="saving" data-testid="role-save" @click="emit('save')" />
      <Button v-if="pendingChanges" :label="t('admin.roles.discard')" severity="secondary" text @click="emit('discard')" />
      <Button :label="t('admin.roles.duplicate')" severity="secondary" data-testid="role-duplicate" @click="emit('duplicate')" />
    </div>
  </section>
</template>

<style scoped>
.role-panel { display: flex; flex-direction: column; gap: 10px; }
.role-title { margin: 0; font-size: var(--dm-text-xl); }
.desc { margin: 0; line-height: 1.5; }
.users { display: flex; align-items: baseline; gap: 8px; margin: 4px 0 8px; }
.users-n { font-size: var(--dm-text-kpi); font-weight: 500; letter-spacing: -0.02em; line-height: 1; }
.changes { display: flex; flex-direction: column; }
.change { display: flex; flex-direction: column; gap: 2px; padding: 8px 0; border-bottom: 1px solid var(--dm-hairline); }
.change:last-child { border-bottom: 0; }
.buttons { display: flex; flex-direction: column; gap: 8px; margin-top: 8px; }
.buttons :deep(.p-button) { justify-content: center; }
</style>
