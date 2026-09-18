<script setup lang="ts">
import Button from 'primevue/button'
import Column from 'primevue/column'
import DataTable from 'primevue/datatable'
import { onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { journal } from '@/api/endpoints'
import type { Decision } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import { describeChoice, describeSubject, organizationOf, roleLabel, subjectLabel, type DecisionNames } from '@/lib/decision'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'

const { t, locale } = useI18n()
const auth = useAuthStore()
const refdata = useRefdataStore()
const items = ref<Decision[]>([])
const total = ref(0)
const error = ref<unknown>(null)
const loading = ref(false)

const names: DecisionNames = {
  region: (kato) => refdata.regionName(kato),
  profile: (code) => refdata.profileName(code),
  organization: (moCode) => refdata.organizationName(moCode),
}

async function load() {
  loading.value = true
  error.value = null
  try {
    const page = await journal.decisions({ actor: auth.hasRole('regulator') ? undefined : 'me', size: 100 })
    const codes = page.items.flatMap((d) => [organizationOf(d.recommended), organizationOf(d.chosen)]).filter((c): c is string => c !== null)
    await refdata.resolveOrganizations(codes)
    items.value = page.items
    total.value = page.total
  } catch (e) {
    error.value = e
  } finally {
    loading.value = false
  }
}

onMounted(async () => {
  await refdata.load()
  await load()
})
</script>

<template>
  <main class="page">
    <h1>{{ t('doctor.decisions.title') }}</h1>
    <p class="lead">{{ auth.hasRole('regulator') ? t('doctor.decisions.leadRegulator') : t('doctor.decisions.leadSelf') }} {{ t('doctor.decisions.total') }} {{ total }}.</p>
    <div class="actions" style="margin: 0 0 12px">
      <Button :label="t('doctor.decisions.refresh')" icon="pi pi-refresh" size="small" severity="secondary" :loading="loading" @click="load" />
    </div>
    <ErrorBox :error="error" />
    <DataTable :value="items" size="small" paginator :rows="25">
      <Column field="recordedAt" :header="t('doctor.decisions.when')"><template #body="{ data }">{{ new Date(data.recordedAt).toLocaleString(locale === 'kk' ? 'kk-KZ' : 'ru-RU') }}</template></Column>
      <Column field="actor" :header="t('doctor.decisions.who')" />
      <Column :header="t('doctor.decisions.role')"><template #body="{ data }">{{ roleLabel(data.role) }}</template></Column>
      <Column :header="t('doctor.decisions.subject')"><template #body="{ data }">{{ subjectLabel(data.subject) }}</template></Column>
      <Column :header="t('doctor.decisions.object')"><template #body="{ data }">{{ describeSubject(data.subject, data.subjectId, names) }}</template></Column>
      <Column :header="t('doctor.decisions.recommended')"><template #body="{ data }">{{ describeChoice(data.recommended, names) }}</template></Column>
      <Column :header="t('doctor.decisions.chosen')"><template #body="{ data }">{{ describeChoice(data.chosen, names) }}</template></Column>
      <Column field="reason" :header="t('doctor.decisions.reason')" />
    </DataTable>
  </main>
</template>
