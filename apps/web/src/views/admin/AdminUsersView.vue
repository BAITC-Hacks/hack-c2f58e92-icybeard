<script setup lang="ts">
import Button from 'primevue/button'
import InputText from 'primevue/inputtext'
import { useToast } from 'primevue/usetoast'
import { computed, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { admin } from '@/api/endpoints'
import type { AdminUser, AdminUsersResponse, MatrixCell, OrganizationItem } from '@/api/types'
import InviteDialog from '@/components/admin/InviteDialog.vue'
import UserPanel from '@/components/admin/UserPanel.vue'
import ErrorBox from '@/components/ErrorBox.vue'
import AsyncState from '@/components/states/AsyncState.vue'
import FilterPill from '@/components/ui/FilterPill.vue'
import KpiRow from '@/components/ui/KpiRow.vue'
import KpiTile from '@/components/ui/KpiTile.vue'
import PageShell from '@/components/ui/PageShell.vue'
import Pager from '@/components/ui/Pager.vue'
import StatusTag from '@/components/ui/StatusTag.vue'
import { useLocaleFormat } from '@/composables/useLocaleFormat'
import { USER_STATUS_TONE } from '@/lib/admin'
import { shortOrgName } from '@/lib/format'
import { roleShort } from '@/lib/labels'
import { ROLE_KEYS } from '@/lib/permissions'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'

/** Пользователи (W-Admin-Users): фильтры роль · организация · статус и поиск, KPI (активные, приглашения, заблокированные),
 * таблица с пагинацией, справа — панель выбранного пользователя; «Пригласить пользователя». Разрешение admin.users:
 * при scope own фильтр организации зафиксирован на своей, назначать можно только врача и администратора организации. */
const PAGE_SIZE = 20
const STATUSES = ['active', 'invited', 'blocked'] as const
const { t } = useI18n()
const toast = useToast()
const auth = useAuthStore()
const refdata = useRefdataStore()
const { num, dateTimeShort } = useLocaleFormat()

const scope = computed(() => auth.scopeOf('admin.users'))
const own = computed(() => scope.value === 'own')
const role = ref<string | null>(null)
const moCode = ref<string | null>(own.value ? auth.moCode : null)
const status = ref<string | null>(null)
const q = ref('')
const page = ref(1)
const response = ref<AdminUsersResponse | null>(null)
const loading = ref(false)
const error = ref<unknown>(null)
const selected = ref<AdminUser | null>(null)
const busy = ref(false)
const actionError = ref<unknown>(null)
const inviteOpen = ref(false)
const organizations = ref<OrganizationItem[]>([])
const matrix = ref<MatrixCell[] | null>(null)

const filtered = computed(() => !!(role.value || status.value || q.value.trim() || (!own.value && moCode.value)))
const roleOptions = computed(() => ROLE_KEYS.map((key) => ({ value: key, label: roleShort(key) })))
const orgOptions = computed(() => organizations.value.map((o) => ({ value: o.moCode, label: `${shortOrgName(o.name)} · ${o.moCode}` })))
const statusOptions = computed(() => STATUSES.map((s) => ({ value: s, label: t(`admin.users.statusFilter.${s}`) })))
const summary = computed(() => response.value?.summary ?? null)
const lead = computed(() => [response.value ? t('admin.users.lead', { n: num(response.value.total) }) : null, own.value ? t('admin.ownOrgLead', { org: shortOrgName(refdata.organizationName(auth.moCode)) }) : t('admin.users.leadVia')].filter(Boolean).join(' · '))

/** Номер последнего запроса списка: ответ на устаревший фильтр или страницу отбрасывается. */
let latestLoad = 0
async function load() {
  const request = ++latestLoad
  loading.value = true
  error.value = null
  try {
    const result = await admin.users({ role: role.value ?? undefined, moCode: (own.value ? auth.moCode : moCode.value) ?? undefined, status: status.value ?? undefined, q: q.value.trim() || undefined, page: page.value, size: PAGE_SIZE })
    if (request !== latestLoad) return
    response.value = result
    if (selected.value) {
      const fresh = result.items.find((u) => u.id === selected.value!.id)
      selected.value = fresh ? { ...fresh, createdAt: selected.value.createdAt ?? fresh.createdAt ?? null } : null
    }
  } catch (e) {
    if (request !== latestLoad) return
    error.value = e
    response.value = null
  } finally {
    if (request === latestLoad) loading.value = false
  }
}

/** Выбор строки: панель сразу, дата создания учётной записи — из карточки пользователя (GET /admin/users/{id}). */
async function select(user: AdminUser) {
  selected.value = user
  try {
    const detail = await admin.user(user.id)
    if (selected.value?.id === user.id) selected.value = { ...user, createdAt: detail.createdAt ?? null }
  } catch {
    // без карточки панель работает по строке списка
  }
}

function resetFilters() {
  role.value = null
  status.value = null
  q.value = ''
  if (!own.value) moCode.value = null
}

async function act(run: () => Promise<unknown>, done: string) {
  busy.value = true
  actionError.value = null
  try {
    await run()
    toast.add({ severity: 'success', summary: done, life: 3000 })
    await load()
  } catch (e) {
    actionError.value = e
  } finally {
    busy.value = false
  }
}

function save(change: { role: string; moCode: string | null; regionKato: string | null }) {
  const user = selected.value
  if (user) void act(() => admin.updateUser(user.id, change), t('admin.users.saved'))
}
function block() {
  const user = selected.value
  if (user) void act(() => admin.block(user.id), t('admin.users.blocked'))
}
function unblock() {
  const user = selected.value
  if (user) void act(() => admin.unblock(user.id), t('admin.users.unblocked'))
}

let searchTimer: number | undefined
watch([role, moCode, status], () => (page.value === 1 ? void load() : (page.value = 1)))
watch(q, () => {
  window.clearTimeout(searchTimer)
  searchTimer = window.setTimeout(() => (page.value === 1 ? void load() : (page.value = 1)), 350)
})
watch(page, load)

onMounted(async () => {
  await refdata.load().catch(() => undefined)
  if (auth.moCode) await refdata.resolveOrganizations([auth.moCode]).catch(() => undefined)
  await load()
  if (!own.value) organizations.value = await refdata.allOrganizations().catch(() => [])
  if (auth.can('admin.roles')) matrix.value = (await admin.roles().catch(() => null))?.matrix ?? null
})
</script>

<template>
  <PageShell :title="t('admin.users.title')" :lead="lead">
    <template #actions>
      <Button :label="t('admin.users.invite')" icon="pi pi-plus" data-testid="invite-open" @click="inviteOpen = true" />
    </template>
    <div class="toolbar">
      <FilterPill v-model="role" :label="t('admin.users.colRole')" :all-label="t('admin.all')" :options="roleOptions" testid="filter-role" />
      <FilterPill v-if="own" :model-value="auth.moCode" :label="t('admin.users.colOrg')" :all-label="t('admin.all')" :options="[{ value: auth.moCode ?? '', label: shortOrgName(refdata.organizationName(auth.moCode)) }]" locked testid="filter-org" />
      <FilterPill v-else v-model="moCode" :label="t('admin.users.colOrg')" :all-label="t('admin.all')" :options="orgOptions" searchable testid="filter-org" />
      <FilterPill v-model="status" :label="t('admin.users.colStatus')" :all-label="t('admin.all')" :options="statusOptions" testid="filter-status" />
      <span class="spacer" />
      <label class="search"><span class="caption">{{ t('admin.search') }}</span><InputText v-model="q" size="small" :placeholder="t('admin.users.searchPlaceholder')" data-testid="users-search" /></label>
    </div>

    <KpiRow v-if="summary">
      <KpiTile :value="num(summary.active)" :label="t('admin.users.kpiActive')" />
      <KpiTile :value="num(summary.invited ?? summary.invitedStale)" :label="summary.invited !== undefined ? t('admin.users.kpiInvited') : t('admin.users.kpiInvitedStale')" :chip="summary.invited !== undefined && summary.invitedStale ? t('admin.users.staleChip', { n: summary.invitedStale }) : undefined" chip-tone="info" />
      <KpiTile :value="num(summary.blocked)" :label="t('admin.users.kpiBlocked')" />
    </KpiRow>

    <div class="with-panel">
      <section class="card">
        <AsyncState :loading="loading" :error="error" :empty="!response?.items.length" :filtered="filtered" :lines="8" :empty-title="t('admin.users.empty')" :empty-text="t('admin.users.emptyText')" empty-icon="pi pi-users" @retry="load" @reset="resetFilters">
          <template #empty-actions><Button :label="t('admin.users.invite')" size="small" @click="inviteOpen = true" /></template>
          <div class="table-wrap">
            <table class="dense-table" data-testid="users-table">
              <thead><tr><th>{{ t('admin.users.colUser') }}</th><th>{{ t('admin.users.colRole') }}</th><th>{{ t('admin.users.colOrg') }}</th><th class="col-region">{{ t('admin.users.colRegion') }}</th><th>{{ t('admin.users.colLast') }}</th><th>{{ t('admin.users.colStatus') }}</th></tr></thead>
              <tbody>
                <tr v-for="user in response!.items" :key="user.id" class="clickable" :class="{ selected: selected?.id === user.id }" @click="select(user)">
                  <td class="user-cell"><span class="strong">{{ user.displayName ?? user.username }}</span><div class="caption">{{ user.username }}</div></td>
                  <td><span class="chips"><StatusTag v-for="r in user.roles" :key="r" :value="roleShort(r)" /></span></td>
                  <td class="clip" :title="user.moName ?? ''">{{ user.moName ? `${shortOrgName(user.moName)} · ${user.moCode}` : user.moCode ?? '—' }}</td>
                  <td class="clip region col-region">{{ user.regionKato ? refdata.regionName(user.regionKato) : '—' }}</td>
                  <td class="nowrap tabular">{{ user.lastActivity ? dateTimeShort(user.lastActivity) : t('admin.users.neverSigned') }}</td>
                  <td><StatusTag :value="t(`admin.users.status.${user.status}`)" :tone="USER_STATUS_TONE[user.status]" /></td>
                </tr>
              </tbody>
            </table>
          </div>
          <Pager v-model:page="page" :total="response!.total" :size="PAGE_SIZE" />
        </AsyncState>
      </section>
      <aside class="panel-col">
        <UserPanel v-if="selected" :user="selected" :scope="scope" :own-mo-code="auth.moCode" :organizations="organizations" :matrix="matrix" :busy="busy" @save="save" @block="block" @unblock="unblock" />
        <section v-else class="card hint"><i class="pi pi-user muted" aria-hidden="true" /><span class="muted small">{{ t('admin.users.pickHint') }}</span></section>
        <ErrorBox :error="actionError" />
      </aside>
    </div>

    <InviteDialog v-model:visible="inviteOpen" :scope="scope" :own-mo-code="auth.moCode" :organizations="organizations" @invited="load" />
  </PageShell>
</template>

<style scoped>
.spacer { flex: 1; }
.search { display: inline-flex; align-items: center; gap: 10px; }
.search .p-inputtext { background: var(--dm-surface-2); min-width: 260px; }
.with-panel { display: grid; grid-template-columns: minmax(0, 1fr) 320px; gap: 16px; align-items: start; }
.panel-col { display: flex; flex-direction: column; gap: 12px; position: sticky; top: 16px; }
.hint { display: flex; flex-direction: column; align-items: center; gap: 8px; text-align: center; padding: 32px 24px; }
.strong { font-weight: 500; }
.user-cell { white-space: nowrap; }
.clip.region { max-width: 110px; }
.clip { max-width: 160px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.nowrap { white-space: nowrap; }
/* на ноутбуке регион уходит, чтобы статус оставался в видимой части таблицы */
@media (max-width: 1500px) { .col-region { display: none; } }
@media (max-width: 1200px) { .with-panel { grid-template-columns: 1fr; } .panel-col { position: static; } }
</style>
