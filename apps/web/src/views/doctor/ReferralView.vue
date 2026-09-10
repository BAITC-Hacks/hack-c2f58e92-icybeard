<script setup lang="ts">
import Button from 'primevue/button'
import InputText from 'primevue/inputtext'
import Select from 'primevue/select'
import Textarea from 'primevue/textarea'
import { useToast } from 'primevue/usetoast'
import { onMounted, reactive, ref, watch } from 'vue'
import { ApiError } from '@/api/client'
import { journal, queue } from '@/api/endpoints'
import type { AlternativesResponse, OrganizationItem, PredictResponse } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import ExplanationCard from '@/components/ExplanationCard.vue'
import { days, pct } from '@/lib/format'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'

const refdata = useRefdataStore()
const auth = useAuthStore()
const toast = useToast()

const form = reactive({
  regionKato: auth.region ?? '75',
  moCode: '028B',
  profileCode: '381',
  icd10: 'H25.1',
  referralPurpose: 'Оперативное лечение',
  territorialType: 'Город',
  financeSource: 'Активы Фонда на ОСМС',
  registrationDate: new Date().toISOString().slice(0, 10),
})
const organizations = ref<OrganizationItem[]>([])
const prediction = ref<PredictResponse | null>(null)
const alternatives = ref<AlternativesResponse | null>(null)
const error = ref<unknown>(null)
const fieldErrors = ref<Record<string, string>>({})
const busy = ref(false)
const reason = ref('')
const recorded = ref<string | null>(null)

const purposes = ['Оперативное лечение', 'Консервативное лечение', 'Диагностика', 'Реабилитация']
const territorial = ['Город', 'Село']

async function loadOrganizations() {
  organizations.value = await refdata.organizationsOf(form.regionKato, form.profileCode)
  if (!organizations.value.some((o) => o.moCode === form.moCode)) form.moCode = organizations.value[0]?.moCode ?? ''
}

async function predict() {
  busy.value = true
  error.value = null
  fieldErrors.value = {}
  recorded.value = null
  try {
    ;[prediction.value, alternatives.value] = await Promise.all([queue.predict(form), queue.alternatives({ ...form, limit: 5 })])
  } catch (e) {
    if (e instanceof ApiError && e.status === 422 && e.errors) {
      fieldErrors.value = Object.fromEntries(Object.entries(e.errors).map(([k, v]) => [k, v.join(', ')]))
    }
    error.value = e
    prediction.value = null
    alternatives.value = null
  } finally {
    busy.value = false
  }
}

async function record(chosen: string) {
  const recommended = alternatives.value?.items[0]?.mo.moCode ?? form.moCode
  try {
    const created = await journal.record(
      {
        subject: 'referral',
        subjectId: `${form.regionKato}.${form.moCode}.${form.profileCode}.${form.registrationDate}`,
        recommended: { moCode: recommended },
        chosen: { moCode: chosen },
        reason: reason.value,
      },
      crypto.randomUUID(),
    )
    recorded.value = created.decisionId
    toast.add({ severity: 'success', summary: 'Решение записано в журнал', detail: created.decisionId, life: 3000 })
  } catch (e) {
    error.value = e
  }
}

onMounted(async () => {
  await refdata.load()
  await loadOrganizations()
  await predict()
})
watch(() => [form.regionKato, form.profileCode], loadOrganizations)
</script>

<template>
  <main class="page">
    <h1>Ассистент направления</h1>
    <p class="lead">Ожидание и риск отказа для направления в выбранную организацию, альтернативы в том же регионе и профиле, запись решения в журнал.</p>
    <div class="grid cols-2">
      <div class="card">
        <h2>Направление</h2>
        <div class="form-grid">
          <div class="field"><label>Регион</label><Select v-model="form.regionKato" :options="refdata.regions" option-label="name" option-value="regionKato" filter /><span class="error">{{ fieldErrors.regionKato }}</span></div>
          <div class="field"><label>Организация</label><Select v-model="form.moCode" :options="organizations" option-label="name" option-value="moCode" filter /></div>
          <div class="field"><label>Профиль койки</label><Select v-model="form.profileCode" :options="refdata.profiles" option-label="name" option-value="profileCode" filter /><span class="error">{{ fieldErrors.profileCode }}</span></div>
          <div class="field"><label>МКБ-10</label><InputText v-model="form.icd10" placeholder="H25.1" /></div>
          <div class="field"><label>Цель</label><Select v-model="form.referralPurpose" :options="purposes" /></div>
          <div class="field"><label>Город или село</label><Select v-model="form.territorialType" :options="territorial" /></div>
          <div class="field"><label>Дата постановки в очередь</label><InputText v-model="form.registrationDate" placeholder="YYYY-MM-DD" /><span class="error">{{ fieldErrors.registrationDate }}</span></div>
        </div>
        <div class="actions"><Button label="Рассчитать" icon="pi pi-calculator" :loading="busy" @click="predict" /></div>
        <ErrorBox :error="error" />
      </div>
      <div v-if="prediction">
        <div class="card">
          <h2>Прогноз для {{ organizations.find((o) => o.moCode === form.moCode)?.name ?? form.moCode }}</h2>
          <div class="kpi">
            <div class="item"><div class="value">{{ days(prediction.p50Days) }}</div><div class="label">медианное ожидание, дн.</div></div>
            <div class="item"><div class="value">{{ days(prediction.p90Days) }}</div><div class="label">p90, дн.</div></div>
            <div class="item"><div class="value">{{ pct(prediction.pWithin30Days) }}</div><div class="label">госпитализация за 30 дней</div></div>
            <div class="item"><div class="value">{{ pct(prediction.pRefusal) }}</div><div class="label">риск отказа</div></div>
          </div>
          <p v-if="prediction.queue" class="muted" style="margin-top: 8px">
            В очереди {{ prediction.queue.len }} направлений, медианный возраст {{ days(prediction.queue.ageP50) }} дн., {{ prediction.queue.throughputPerDay.toFixed(1) }} госпитализаций в день.
          </p>
        </div>
        <ExplanationCard :explanation="prediction.explanation" :model="prediction.model" unit="дн." style="margin-top: 16px" />
      </div>
    </div>
    <div v-if="alternatives" class="card" style="margin-top: 16px">
      <h2>Альтернативы в регионе</h2>
      <p v-if="alternatives.items.length === 0" class="muted">Других организаций с этим профилем в регионе нет.</p>
      <table v-else style="width: 100%; border-collapse: collapse">
        <thead><tr class="muted" style="text-align: left"><th>Организация</th><th>p50, дн.</th><th>p90, дн.</th><th>отказ</th><th>расстояние</th><th></th></tr></thead>
        <tbody>
          <tr v-for="a in alternatives.items" :key="a.mo.moCode" style="border-top: 1px solid var(--darumen-border)">
            <td style="padding: 8px 4px">{{ a.mo.name }} <span class="muted">({{ a.mo.moCode }})</span></td>
            <td>{{ days(a.p50Days) }}</td>
            <td>{{ days(a.p90Days) }}</td>
            <td>{{ pct(a.pRefusal) }}</td>
            <td class="muted">{{ a.distanceKm > 0 ? `${a.distanceKm.toFixed(0)} км` : 'нет координат' }}</td>
            <td><Button label="Направить сюда" size="small" severity="secondary" @click="record(a.mo.moCode)" /></td>
          </tr>
        </tbody>
      </table>
      <div class="field" style="margin-top: 12px"><label>Причина выбора (попадает в журнал)</label><Textarea v-model="reason" rows="2" auto-resize /></div>
      <div class="actions">
        <Button label="Оставить в выбранной организации" icon="pi pi-check" @click="record(form.moCode)" />
        <span v-if="recorded" class="muted">записано: {{ recorded }}</span>
      </div>
    </div>
  </main>
</template>
