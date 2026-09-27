<script setup lang="ts">
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import Textarea from 'primevue/textarea'
import { useToast } from 'primevue/usetoast'
import { computed, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { admin } from '@/api/endpoints'
import type { AdminDoctor, OrganizationItem, PagedList } from '@/api/types'
import DoctorVerification from '@/components/admin/DoctorVerification.vue'
import InviteDialog from '@/components/admin/InviteDialog.vue'
import ErrorBox from '@/components/ErrorBox.vue'
import AsyncState from '@/components/states/AsyncState.vue'
import AppCard from '@/components/ui/AppCard.vue'
import BarList from '@/components/ui/BarList.vue'
import FilterPill from '@/components/ui/FilterPill.vue'
import PageShell from '@/components/ui/PageShell.vue'
import Pager from '@/components/ui/Pager.vue'
import StatusTag from '@/components/ui/StatusTag.vue'
import { useAsync } from '@/composables/useAsync'
import { useLocaleFormat } from '@/composables/useLocaleFormat'
import { VERIFICATION_TONE } from '@/lib/admin'
import { pct, shortOrgName } from '@/lib/format'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'

/** Врачи (W-Admin-Doctors): фильтры регион · организация · специальность · верификация, таблица (направления и
 * совпадение с рекомендацией ассистента — из журнала решений за квартал, расчёт по формуле), карточка «Верификация»
 * с «Подтвердить»/«Отклонить» и «Нагрузка направлений» барами. При scope own — только своя организация. */
const PAGE_SIZE = 20
const VERIFICATIONS = ['pending', 'verified', 'rejected'] as const
const { t } = useI18n()
const toast = useToast()
const auth = useAuthStore()
const refdata = useRefdataStore()
const { num } = useLocaleFormat()

const scope = computed(() => auth.scopeOf('admin.users'))
const own = computed(() => scope.value === 'own')
const regionKato = ref<string | null>(null)
const moCode = ref<string | null>(null)
const specialty = ref<string | null>(null)
const verification = ref<string | null>(null)
const page = ref(1)
const organizations = ref<OrganizationItem[]>([])
const inviteOpen = ref(false)
const busyId = ref<string | null>(null)
const actionError = ref<unknown>(null)
const rejecting = ref<AdminDoctor | null>(null)
const rejectComment = ref('')

const orgFilter = () => (own.value ? auth.moCode : moCode.value) ?? undefined
const list = useAsync<PagedList<AdminDoctor>>(() =>
  admin.doctors({ regionKato: regionKato.value ?? undefined, moCode: orgFilter(), specialty: specialty.value ?? undefined, verification: verification.value ?? undefined, page: page.value, size: PAGE_SIZE }),
)
const pending = useAsync<PagedList<AdminDoctor>>(() => admin.doctors({ moCode: own.value ? auth.moCode ?? undefined : undefined, verification: 'pending', page: 1, size: 5 }))

const filtered = computed(() => !!(regionKato.value || specialty.value || verification.value || (!own.value && moCode.value)))
const regionOptions = computed(() => refdata.regions.map((r) => ({ value: r.regionKato, label: r.name })))
const orgOptions = computed(() => organizations.value.filter((o) => !regionKato.value || o.regionKato === regionKato.value).map((o) => ({ value: o.moCode, label: `${shortOrgName(o.name)} · ${o.moCode}` })))
/** Специальности — из загруженных строк (справочника специальностей в API нет). */
const specialtyOptions = computed(() => [...new Set([...(list.data.value?.items ?? []).map((d) => d.specialty), specialty.value].filter((s): s is string => !!s))].map((s) => ({ value: s, label: s })))
const verificationOptions = computed(() => VERIFICATIONS.map((v) => ({ value: v, label: t(`admin.doctors.verification.${v}`) })))
const topLoad = computed(() =>
  [...(list.data.value?.items ?? [])].filter((d) => d.referrals !== null).sort((a, b) => (b.referrals ?? 0) - (a.referrals ?? 0)).slice(0, 3)
    .map((d) => ({ key: d.id, label: d.displayName ?? '—', value: d.referrals ?? 0, display: num(d.referrals) })),
)
const lead = computed(() => [list.data.value ? t('admin.doctors.lead', { n: num(list.data.value.total) }) : null, own.value ? t('admin.ownOrgLead', { org: shortOrgName(refdata.organizationName(auth.moCode)) }) : null, t('admin.doctors.period')].filter(Boolean).join(' · '))

function resetFilters() {
  regionKato.value = null
  specialty.value = null
  verification.value = null
  if (!own.value) moCode.value = null
}

async function decide(doctor: AdminDoctor, status: 'verified' | 'rejected', comment?: string) {
  busyId.value = doctor.id
  actionError.value = null
  try {
    await admin.verifyDoctor(doctor.id, status, comment)
    toast.add({ severity: 'success', summary: t(status === 'verified' ? 'admin.doctors.verified' : 'admin.doctors.rejected'), life: 3000 })
    await Promise.all([list.run(), pending.run()])
  } catch (e) {
    actionError.value = e
  } finally {
    busyId.value = null
    rejecting.value = null
  }
}

function startReject(doctor: AdminDoctor) {
  rejecting.value = doctor
  rejectComment.value = ''
}

watch([regionKato, moCode, specialty, verification], () => (page.value === 1 ? void list.run() : (page.value = 1)))
watch(page, () => void list.run())

onMounted(async () => {
  await refdata.load().catch(() => undefined)
  if (auth.moCode) await refdata.resolveOrganizations([auth.moCode]).catch(() => undefined)
  await Promise.all([list.run(), pending.run()])
  if (!own.value) organizations.value = await refdata.allOrganizations().catch(() => [])
})
</script>

<template>
  <PageShell :title="t('admin.doctors.title')" :lead="lead">
    <template #actions><Button :label="t('admin.doctors.add')" icon="pi pi-plus" @click="inviteOpen = true" /></template>
    <div class="toolbar">
      <FilterPill v-if="!own" v-model="regionKato" :label="t('admin.users.colRegion')" :all-label="t('admin.all')" :options="regionOptions" searchable testid="filter-region" />
      <FilterPill v-if="own" :model-value="auth.moCode" :label="t('admin.users.colOrg')" :all-label="t('admin.all')" :options="[{ value: auth.moCode ?? '', label: shortOrgName(refdata.organizationName(auth.moCode)) }]" locked />
      <FilterPill v-else v-model="moCode" :label="t('admin.users.colOrg')" :all-label="t('admin.all')" :options="orgOptions" searchable testid="filter-org" />
      <FilterPill v-model="specialty" :label="t('admin.doctors.colSpecialty')" :all-label="t('admin.all')" :options="specialtyOptions" />
      <FilterPill v-model="verification" :label="t('admin.doctors.colVerification')" :all-label="t('admin.all')" :options="verificationOptions" testid="filter-verification" />
    </div>

    <div class="with-panel">
      <section class="card">
        <AsyncState :loading="list.loading.value" :error="list.error.value" :empty="!list.data.value?.items.length" :filtered="filtered" :lines="8" :empty-title="t('admin.doctors.empty')" empty-icon="pi pi-id-card" @retry="list.run" @reset="resetFilters">
          <div class="table-wrap">
            <table class="dense-table" data-testid="doctors-table">
              <thead><tr><th>{{ t('admin.doctors.colDoctor') }}</th><th>{{ t('admin.doctors.colSpecialty') }}</th><th>{{ t('admin.doctors.colOrg') }}</th><th>{{ t('admin.users.colRegion') }}</th><th class="num">{{ t('admin.doctors.colReferrals') }}</th><th>{{ t('admin.doctors.colMatch') }}</th><th>{{ t('admin.doctors.colVerification') }}</th></tr></thead>
              <tbody>
                <tr v-for="d in list.data.value!.items" :key="d.id">
                  <td class="strong nowrap">{{ d.displayName ?? '—' }}</td>
                  <td class="muted">{{ d.specialty ?? '—' }}</td>
                  <td class="clip" :title="d.moName ?? ''">{{ d.moName ? shortOrgName(d.moName) : '—' }}<div class="caption">{{ d.moCode }}</div></td>
                  <td class="clip">{{ d.regionKato ? refdata.regionName(d.regionKato) : '—' }}</td>
                  <td class="num">{{ num(d.referrals) }}</td>
                  <td><span v-if="d.matchRate !== null" class="match"><span class="track"><span class="fill" :style="{ width: `${Math.round(d.matchRate * 100)}%` }" /></span><span class="tabular">{{ pct(d.matchRate) }}</span></span><span v-else class="muted">—</span></td>
                  <td><StatusTag :value="t(`admin.doctors.verification.${d.verification}`)" :tone="VERIFICATION_TONE[d.verification]" /></td>
                </tr>
              </tbody>
            </table>
          </div>
          <Pager v-model:page="page" :total="list.data.value!.total" :size="PAGE_SIZE" :note="t('admin.doctors.matchNote')" />
        </AsyncState>
      </section>
      <aside class="panel-col">
        <DoctorVerification :items="pending.data.value?.items ?? []" :total="pending.data.value?.total ?? 0" :loading="pending.loading.value" :error="pending.error.value" :busy-id="busyId" @verify="(d) => decide(d, 'verified')" @reject="startReject" @retry="pending.run" />
        <AppCard :title="t('admin.doctors.loadTitle')">
          <template #header><span class="caption">{{ t('admin.doctors.loadPeriod') }}</span></template>
          <BarList v-if="topLoad.length" :items="topLoad" :label-width="120" />
          <p v-else class="muted small">{{ t('admin.noData') }}</p>
          <p v-if="topLoad.length && list.data.value" class="caption">{{ t('admin.doctors.topOf', { n: topLoad.length, total: num(list.data.value.total) }) }}</p>
        </AppCard>
        <ErrorBox :error="actionError" />
      </aside>
    </div>

    <InviteDialog v-model:visible="inviteOpen" :scope="scope" :own-mo-code="auth.moCode" :organizations="organizations" default-role="doctor" @invited="list.run" />
    <Dialog :visible="rejecting !== null" modal :header="t('admin.doctors.rejectTitle')" :style="{ width: 'min(460px, 92vw)' }" @update:visible="(v: boolean) => !v && (rejecting = null)">
      <div class="field"><label for="reject-comment">{{ t('common.comment') }}</label><Textarea id="reject-comment" v-model="rejectComment" rows="3" auto-resize /></div>
      <template #footer>
        <Button :label="t('common.cancel')" severity="secondary" @click="rejecting = null" />
        <Button :label="t('admin.doctors.reject')" severity="danger" :loading="busyId !== null" @click="rejecting && decide(rejecting, 'rejected', rejectComment.trim() || undefined)" />
      </template>
    </Dialog>
  </PageShell>
</template>

<style scoped>
.with-panel { display: grid; grid-template-columns: minmax(0, 1fr) 320px; gap: 16px; align-items: start; }
.panel-col { display: flex; flex-direction: column; gap: 16px; }
.strong { font-weight: 500; }
.nowrap { white-space: nowrap; }
.clip { max-width: 200px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.match { display: inline-flex; align-items: center; gap: 8px; white-space: nowrap; }
.track { width: 60px; height: 4px; border-radius: 2px; background: var(--dm-neutral-soft); overflow: hidden; }
.fill { display: block; height: 100%; background: var(--dm-primary); }
@media (max-width: 1200px) { .with-panel { grid-template-columns: 1fr; } }
</style>
