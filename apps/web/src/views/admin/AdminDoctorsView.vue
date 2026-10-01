<script setup lang="ts">
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import IconField from 'primevue/iconfield'
import InputIcon from 'primevue/inputicon'
import InputText from 'primevue/inputtext'
import Textarea from 'primevue/textarea'
import { useToast } from 'primevue/usetoast'
import { computed, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { admin } from '@/api/endpoints'
import type { AdminDoctor, OrganizationItem, PagedList } from '@/api/types'
import InviteDialog from '@/components/admin/InviteDialog.vue'
import ErrorBox from '@/components/ErrorBox.vue'
import AsyncState from '@/components/states/AsyncState.vue'
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

/** Врачи (W-Admin-Doctors): над таблицей фильтры (регион · организация · специальность · проверка), поиск и «Добавить
 * врача»; в таблице — направления за 90 дней и как часто выбор врача совпал с подсказкой ассистента. Проверку
 * квалификации (диплом, сертификат) проводит только администратор платформы — кнопки прямо в строке; главврач видит
 * статус, но не подтверждает своих сотрудников (сервер ответит 403). */
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
const search = ref('')
/** Поиск — по загруженной странице (имя, специальность, организация). */
const rows = computed(() => {
  const q = search.value.trim().toLowerCase()
  const items = list.data.value?.items ?? []
  return q ? items.filter((d) => [d.displayName, d.specialty, d.moName, d.moCode].join(' ').toLowerCase().includes(q)) : items
})
/** Подтверждать квалификацию может только администратор платформы (не руководитель своей больницы). */
const canVerify = computed(() => !own.value)
const matchTone = (rate: number) => (rate >= 0.7 ? 'good' : rate >= 0.4 ? 'mid' : 'low')

const filtered = computed(() => !!(regionKato.value || specialty.value || verification.value || search.value.trim() || (!own.value && moCode.value)))
const regionOptions = computed(() => refdata.regions.map((r) => ({ value: r.regionKato, label: r.name })))
const orgOptions = computed(() => organizations.value.filter((o) => !regionKato.value || o.regionKato === regionKato.value).map((o) => ({ value: o.moCode, label: `${shortOrgName(o.name)} · ${o.moCode}` })))
/** Специальности — из загруженных строк (справочника специальностей в API нет). */
const specialtyOptions = computed(() => [...new Set([...(list.data.value?.items ?? []).map((d) => d.specialty), specialty.value].filter((s): s is string => !!s))].map((s) => ({ value: s, label: s })))
const verificationOptions = computed(() => VERIFICATIONS.map((v) => ({ value: v, label: t(`admin.doctors.verification.${v}`) })))
const lead = computed(() => [list.data.value ? t('admin.doctors.lead', { n: num(list.data.value.total) }) : null, own.value ? t('admin.ownOrgLead', { org: shortOrgName(refdata.organizationName(auth.moCode)) }) : null, own.value ? t('admin.doctors.leadOwn') : null].filter(Boolean).join(' · '))

function resetFilters() {
  regionKato.value = null
  specialty.value = null
  verification.value = null
  search.value = ''
  if (!own.value) moCode.value = null
}

async function decide(doctor: AdminDoctor, status: 'verified' | 'rejected', comment?: string) {
  busyId.value = doctor.id
  actionError.value = null
  try {
    await admin.verifyDoctor(doctor.id, status, comment)
    toast.add({ severity: 'success', summary: t(status === 'verified' ? 'admin.doctors.verified' : 'admin.doctors.rejected'), life: 3000 })
    await list.run()
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
  await list.run()
  if (!own.value) organizations.value = await refdata.allOrganizations().catch(() => [])
})
</script>

<template>
  <PageShell :title="t('admin.doctors.title')" :lead="lead">
    <section class="card">
      <div class="toolbar list-toolbar">
        <Button :label="t('admin.doctors.add')" icon="pi pi-plus" size="small" @click="inviteOpen = true" />
        <span class="spacer" />
        <FilterPill v-if="!own" v-model="regionKato" :label="t('admin.users.colRegion')" :all-label="t('admin.all')" :options="regionOptions" searchable testid="filter-region" />
        <FilterPill v-if="own" :model-value="auth.moCode" :label="t('admin.users.colOrg')" :all-label="t('admin.all')" :options="[{ value: auth.moCode ?? '', label: shortOrgName(refdata.organizationName(auth.moCode)) }]" locked />
        <FilterPill v-else v-model="moCode" :label="t('admin.users.colOrg')" :all-label="t('admin.all')" :options="orgOptions" searchable testid="filter-org" />
        <FilterPill v-model="specialty" :label="t('admin.doctors.colSpecialty')" :all-label="t('admin.all')" :options="specialtyOptions" />
        <FilterPill v-model="verification" :label="t('admin.doctors.colVerification')" :all-label="t('admin.all')" :options="verificationOptions" testid="filter-verification" />
        <IconField class="search-field">
          <InputIcon class="pi pi-search" />
          <InputText v-model="search" :placeholder="t('admin.doctors.searchPlaceholder')" :aria-label="t('admin.search')" data-testid="doctors-search" />
        </IconField>
      </div>
      <AsyncState :loading="list.loading.value" :error="list.error.value" :empty="!rows.length" :filtered="filtered" :lines="8" :empty-title="t('admin.doctors.empty')" empty-icon="pi pi-id-card" @retry="list.run" @reset="resetFilters">
        <div class="table-wrap">
          <table class="dense-table" data-testid="doctors-table">
            <thead>
              <tr>
                <th>{{ t('admin.doctors.colDoctor') }}</th><th>{{ t('admin.doctors.colSpecialty') }}</th><th>{{ t('admin.doctors.colOrg') }}</th><th class="col-region">{{ t('admin.users.colRegion') }}</th>
                <th class="num nowrap" :title="t('admin.doctors.referralsHint')">{{ t('admin.doctors.colReferrals') }}</th>
                <th class="num nowrap" :title="t('admin.doctors.matchHint')">{{ t('admin.doctors.colMatch') }}</th>
                <th>{{ t('admin.doctors.colVerification') }}</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="d in rows" :key="d.id">
                <td class="strong nowrap">{{ d.displayName ?? '—' }}</td>
                <td class="muted">{{ d.specialty ?? '—' }}</td>
                <td class="clip" :title="d.moName ?? ''">{{ d.moName ? shortOrgName(d.moName) : '—' }}<div class="caption">{{ d.moCode }}</div></td>
                <td class="clip col-region">{{ d.regionKato ? refdata.regionName(d.regionKato) : '—' }}</td>
                <td class="num tabular">{{ num(d.referrals) }}</td>
                <td class="num tabular"><span v-if="d.matchRate !== null && (d.referrals ?? 0) > 0" class="match" :class="matchTone(d.matchRate)">{{ pct(d.matchRate) }}</span><span v-else class="muted" :title="t('admin.doctors.noReferrals')">—</span></td>
                <td>
                  <div class="verify-cell">
                    <StatusTag :value="t(`admin.doctors.verification.${d.verification}`)" :tone="VERIFICATION_TONE[d.verification]" />
                    <template v-if="canVerify && d.verification === 'pending'">
                      <Button :label="t('admin.doctors.verify')" size="small" :loading="busyId === d.id" :disabled="busyId !== null" @click="decide(d, 'verified')" />
                      <Button :label="t('admin.doctors.reject')" size="small" severity="secondary" text :disabled="busyId !== null" @click="startReject(d)" />
                    </template>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <Pager v-model:page="page" :total="list.data.value!.total" :size="PAGE_SIZE" />
      </AsyncState>
      <ErrorBox :error="actionError" />
    </section>

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
.list-toolbar { margin-bottom: var(--gap-cabinet, 16px); row-gap: 8px; }
.spacer { flex: 1; }
.search-field { flex: 0 1 420px; min-width: 280px; }
.search-field :deep(.p-inputtext) { width: 100%; }
.strong { font-weight: var(--fw-bold); }
.nowrap { white-space: nowrap; }
.clip { max-width: 240px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.match { font-weight: var(--fw-bold); }
.match.good { color: var(--success-text); }
.match.mid { color: var(--warning-text); }
.match.low { color: var(--text-secondary); }
.verify-cell { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
@media (max-width: 1100px) { .col-region { display: none; } }
@media (max-width: 900px) { .search-field { flex: 1 1 100%; } }
</style>
