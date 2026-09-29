<script setup lang="ts">
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import { useToast } from 'primevue/usetoast'
import { computed, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { admin } from '@/api/endpoints'
import type { AdminOrg, AdminOrgDetailResponse, ApplicationDecision, OrgApplication, PagedList } from '@/api/types'
import InviteLink from '@/components/admin/InviteLink.vue'
import OrgApplications from '@/components/admin/OrgApplications.vue'
import OrgPanel from '@/components/admin/OrgPanel.vue'
import ErrorBox from '@/components/ErrorBox.vue'
import AsyncState from '@/components/states/AsyncState.vue'
import StateEmailOff from '@/components/states/StateEmailOff.vue'
import FilterPill from '@/components/ui/FilterPill.vue'
import PageShell from '@/components/ui/PageShell.vue'
import Pager from '@/components/ui/Pager.vue'
import StatusTag from '@/components/ui/StatusTag.vue'
import { useAsync } from '@/composables/useAsync'
import { useLocaleFormat } from '@/composables/useLocaleFormat'
import { lastLoad, ORG_STATUS_TONE } from '@/lib/admin'
import { shortOrgName } from '@/lib/format'
import { useRefdataStore } from '@/stores/refdata'

/** Организации (W-Admin-Orgs, admin.orgs): фильтры регион · тип · статус подключения, таблица (профили, пользователи,
 * статус по данным очередей, последняя загрузка), панель выбранной организации и «Заявки на регистрацию». Одобрение
 * отправляет администратору организации письмо-приглашение: если письмо не ушло, ссылка показывается для ручной передачи,
 * а пока почтовый сервер недоступен (GET /public/service-status), это сказано над заявками заранее. */
const PAGE_SIZE = 20
const STATUSES = ['connected', 'setup', 'no_data'] as const
/** Типы справочника организаций (API admin/orgs). */
const ORG_TYPES = ['hospital', 'polyclinic', 'republican', 'center', 'dispensary', 'maternity', 'other'] as const
const { t, te } = useI18n()
const toast = useToast()
const refdata = useRefdataStore()
const { num, dateTimeShort } = useLocaleFormat()

const regionKato = ref<string | null>(null)
const type = ref<string | null>(null)
const status = ref<string | null>(null)
const page = ref(1)
const selectedCode = ref<string | null>(null)
const busyId = ref<string | null>(null)
const actionError = ref<unknown>(null)
/** Одобренная заявка, письмо по которой не ушло: ссылку-приглашение нужно передать вручную. */
const decision = ref<ApplicationDecision | null>(null)

const list = useAsync<PagedList<AdminOrg>>(() => admin.orgs({ regionKato: regionKato.value ?? undefined, type: type.value ?? undefined, status: status.value ?? undefined, page: page.value, size: PAGE_SIZE }))
const detail = useAsync<AdminOrgDetailResponse>(() => admin.org(selectedCode.value!))
const applications = useAsync<{ items: OrgApplication[] }>(() => admin.applications('pending_review'))

const filtered = computed(() => !!(regionKato.value || type.value || status.value))
const regionOptions = computed(() => refdata.regions.map((r) => ({ value: r.regionKato, label: r.name })))
const typeLabel = (value: string | null) => (value && te(`admin.orgs.type.${value}`) ? t(`admin.orgs.type.${value}`) : value ?? '—')
/** Типы справочника плюс незнакомые клиенту, если встретились в строках. */
const typeOptions = computed(() => [...new Set<string>([...ORG_TYPES, ...(list.data.value?.items ?? []).map((o) => o.type ?? '')].filter(Boolean))].map((v) => ({ value: v, label: typeLabel(v) })))
const statusOptions = computed(() => STATUSES.map((s) => ({ value: s, label: t(`admin.orgs.status.${s}`) })))
/** Колонка «Профили» — только если API отдаёт число профилей. */
const hasProfiles = computed(() => (list.data.value?.items ?? []).some((o) => o.profiles !== undefined && o.profiles !== null))
const lead = computed(() => [list.data.value ? t('admin.orgs.lead', { n: num(list.data.value.total) }) : null, t('admin.orgs.leadStatus')].filter(Boolean).join(' · '))

function select(org: AdminOrg) {
  selectedCode.value = org.moCode
  void detail.run()
}

function resetFilters() {
  regionKato.value = null
  type.value = null
  status.value = null
}

async function decide(run: () => Promise<unknown>, id: string, done: string) {
  busyId.value = id
  actionError.value = null
  try {
    const result = await run()
    const approved = result as ApplicationDecision | null
    if (approved && approved.emailSent === false && approved.inviteUrl) decision.value = approved
    toast.add({ severity: 'success', summary: done, life: 3000 })
    await Promise.all([applications.run(), list.run()])
  } catch (e) {
    actionError.value = e
  } finally {
    busyId.value = null
  }
}

watch([regionKato, type, status], () => (page.value === 1 ? void list.run() : (page.value = 1)))
watch(page, () => void list.run())
onMounted(async () => {
  await refdata.load().catch(() => undefined)
  await Promise.all([list.run(), applications.run()])
})
</script>

<template>
  <PageShell :title="t('admin.orgs.title')" :lead="lead">
    <div class="toolbar">
      <FilterPill v-model="regionKato" :label="t('admin.users.colRegion')" :all-label="t('admin.all')" :options="regionOptions" searchable testid="filter-region" />
      <FilterPill v-model="type" :label="t('admin.orgs.colType')" :all-label="t('admin.all')" :options="typeOptions" />
      <FilterPill v-model="status" :label="t('admin.orgs.colStatusFull')" :all-label="t('admin.all')" :options="statusOptions" testid="filter-status" />
    </div>
    <div class="with-panel">
      <section class="card">
        <AsyncState :loading="list.loading.value" :error="list.error.value" :empty="!list.data.value?.items.length" :filtered="filtered" :lines="8" :empty-title="t('admin.orgs.empty')" empty-icon="pi pi-building" @retry="list.run" @reset="resetFilters">
          <div class="table-wrap">
            <table class="dense-table" data-testid="orgs-table">
              <thead><tr><th>{{ t('admin.orgs.colOrg') }}</th><th>{{ t('admin.users.colRegion') }}</th><th class="col-type">{{ t('admin.orgs.colType') }}</th><th v-if="hasProfiles" class="num">{{ t('admin.orgs.colProfiles') }}</th><th class="num">{{ t('admin.orgs.colUsers') }}</th><th>{{ t('admin.orgs.colStatus') }}</th><th>{{ t('admin.orgs.colLoad') }}</th></tr></thead>
              <tbody>
                <tr v-for="o in list.data.value!.items" :key="o.moCode" class="clickable" :class="{ selected: selectedCode === o.moCode }" @click="select(o)">
                  <td class="clip" :title="o.name"><span class="strong">{{ shortOrgName(o.name) }}</span><div class="caption">{{ o.moCode }}</div></td>
                  <td class="clip">{{ o.regionKato ? refdata.regionName(o.regionKato) : '—' }}</td>
                  <td class="muted col-type">{{ typeLabel(o.type) }}</td>
                  <td v-if="hasProfiles" class="num">{{ num(o.profiles) }}</td>
                  <td class="num">{{ num(o.users) }}</td>
                  <td><StatusTag :value="t(`admin.orgs.status.${o.status}`)" :tone="ORG_STATUS_TONE[o.status]" /></td>
                  <td class="nowrap tabular">{{ lastLoad(o) ? dateTimeShort(lastLoad(o)) : t('admin.orgs.neverLoaded') }}</td>
                </tr>
              </tbody>
            </table>
          </div>
          <Pager v-model:page="page" :total="list.data.value!.total" :size="PAGE_SIZE" :note="hasProfiles ? t('admin.orgs.profilesNote') : undefined" />
        </AsyncState>
      </section>
      <aside class="panel-col">
        <OrgPanel v-if="selectedCode" :org="detail.data.value?.organization ?? null" :loading="detail.loading.value" :error="detail.error.value" @retry="detail.run" />
        <section v-else class="card hint"><i class="pi pi-building muted" aria-hidden="true" /><span class="muted small">{{ t('admin.orgs.pickHint') }}</span></section>
        <StateEmailOff :text="t('serviceStatus.notes.applications')" />
        <OrgApplications :items="applications.data.value?.items ?? []" :loading="applications.loading.value" :error="applications.error.value" :busy-id="busyId" @retry="applications.run"
          @approve="(a) => decide(() => admin.approveApplication(a.id), a.id, t('admin.orgs.approved'))"
          @reject="(a, reason) => decide(() => admin.rejectApplication(a.id, reason), a.id, t('admin.orgs.rejected'))" />
        <ErrorBox :error="actionError" />
      </aside>
    </div>
    <Dialog :visible="decision !== null" modal :header="t('admin.orgs.approvedTitle')" :style="{ width: 'min(520px, 94vw)' }" @update:visible="(v: boolean) => !v && (decision = null)">
      <InviteLink v-if="decision?.inviteUrl" :url="decision.inviteUrl" />
      <template #footer><Button :label="t('common.close')" @click="decision = null" /></template>
    </Dialog>
  </PageShell>
</template>

<style scoped>
.with-panel { display: grid; grid-template-columns: minmax(0, 1fr) 340px; gap: 16px; align-items: start; }
.panel-col { display: flex; flex-direction: column; gap: 16px; }
.hint { display: flex; flex-direction: column; align-items: center; gap: 8px; text-align: center; padding: 32px 24px; }
.strong { font-weight: var(--fw-bold); }
.clip { max-width: 240px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.nowrap { white-space: nowrap; }
@media (max-width: 1500px) { .col-type { display: none; } }
@media (max-width: 1200px) { .with-panel { grid-template-columns: 1fr; } }
</style>
