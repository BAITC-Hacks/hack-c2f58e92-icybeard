<script setup lang="ts">
import Button from 'primevue/button'
import InputText from 'primevue/inputtext'
import Select from 'primevue/select'
import Textarea from 'primevue/textarea'
import { useToast } from 'primevue/usetoast'
import { onMounted, reactive, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { ApiError } from '@/api/client'
import { analytics, journal, queue } from '@/api/endpoints'
import type { AlternativesResponse, OrganizationItem, PredictResponse, QualitySplit } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import ExplanationCard from '@/components/ExplanationCard.vue'
import { referralSubjectId, SUBJECT_REFERRAL } from '@/lib/decision'
import { days, pct, refusalWords } from '@/lib/format'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'

const refdata = useRefdataStore()
const auth = useAuthStore()
const toast = useToast()
const route = useRoute()

// переход «открыть направление» из рабочего списка переносит организацию и профиль пациента
const form = reactive({
  regionKato: auth.region ?? '75',
  moCode: typeof route.query.moCode === 'string' && route.query.moCode ? route.query.moCode : '028B',
  profileCode: typeof route.query.profileCode === 'string' && route.query.profileCode ? route.query.profileCode : '381',
  icd10: 'H25.1',
  referralPurpose: 'Оперативное лечение',
  territorialType: 'Город',
  financeSource: 'Активы Фонда на ОСМС',
  // пусто — сервис моделей берёт день после последних данных очереди: модель обучена на I квартале 2025,
  // сегодняшняя дата вывела бы признаки календаря за пределы обучения
  registrationDate: '',
  // необязательно: если направление внутри своей же организации, модель получает признак same_mo
  referringMoCode: '',
})
const organizations = ref<OrganizationItem[]>([])
// список для «направляющей организации» — все организации региона, не только те, что лечат по этому профилю
const referringOrganizations = ref<OrganizationItem[]>([])
const prediction = ref<PredictResponse | null>(null)
const alternatives = ref<AlternativesResponse | null>(null)
const error = ref<unknown>(null)
const fieldErrors = ref<Record<string, string>>({})
const busy = ref(false)
const reason = ref('')
const recorded = ref<string | null>(null)
const recording = ref(false)
// один ключ идемпотентности на расчёт: повторный клик по тому же прогнозу не создаёт вторую запись
let decisionKey = ''
// метрики модели против baseline из отчёта обучения — та же цифра, что на странице качества (§7.4)
const waitQuality = ref<QualitySplit | null>(null)

const purposes = ['Оперативное лечение', 'Консервативное лечение', 'Диагностика', 'Реабилитация']
const territorial = ['Город', 'Село']

async function loadOrganizations() {
  organizations.value = await refdata.organizationsOf(form.regionKato, form.profileCode)
  if (!organizations.value.some((o) => o.moCode === form.moCode)) form.moCode = organizations.value[0]?.moCode ?? ''
}

async function loadReferringOrganizations() {
  referringOrganizations.value = await refdata.organizationsOf(form.regionKato)
  if (form.referringMoCode && !referringOrganizations.value.some((o) => o.moCode === form.referringMoCode)) {
    form.referringMoCode = ''
  }
}

async function predict() {
  busy.value = true
  error.value = null
  fieldErrors.value = {}
  recorded.value = null
  decisionKey = ''
  try {
    ;[prediction.value, alternatives.value] = await Promise.all([queue.predict(form), queue.alternatives({ ...form, limit: 5 })])
    decisionKey = crypto.randomUUID()
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

/** Рекомендация системы: самая быстрая по медиане организация среди выбранной и альтернатив. */
function recommendedMo(): string {
  const fastest = alternatives.value?.items[0]
  return fastest && prediction.value && fastest.p50Days < prediction.value.p50Days ? fastest.mo.moCode : form.moCode
}

async function record(chosen: string) {
  if (recorded.value || recording.value || !decisionKey) return
  recording.value = true
  try {
    const created = await journal.record(
      {
        subject: SUBJECT_REFERRAL,
        subjectId: referralSubjectId(form.regionKato, form.moCode, form.profileCode, form.registrationDate || new Date().toISOString().slice(0, 10)),
        recommended: { moCode: recommendedMo() },
        chosen: { moCode: chosen },
        reason: reason.value,
      },
      decisionKey,
    )
    recorded.value = created.decisionId
    toast.add({ severity: 'success', summary: 'Решение записано в журнал', detail: created.decisionId, life: 3000 })
  } catch (e) {
    error.value = e
  } finally {
    recording.value = false
  }
}

onMounted(async () => {
  await refdata.load()
  await Promise.all([loadOrganizations(), loadReferringOrganizations()])
  await predict()
  try {
    waitQuality.value = (await analytics.quality()).wait?.test_time ?? null
  } catch {
    waitQuality.value = null // страница работает и без отчёта качества
  }
})
watch(() => [form.regionKato, form.profileCode], loadOrganizations)
watch(() => form.regionKato, loadReferringOrganizations)
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
          <div class="field">
            <label>Направляющая организация</label>
            <Select v-model="form.referringMoCode" :options="referringOrganizations" option-label="name" option-value="moCode" filter show-clear placeholder="не указана" />
          </div>
          <div class="field"><label>Цель</label><Select v-model="form.referralPurpose" :options="purposes" /></div>
          <div class="field"><label>Город или село</label><Select v-model="form.territorialType" :options="territorial" /></div>
          <div class="field"><label>Дата постановки в очередь</label><InputText v-model="form.registrationDate" placeholder="пусто — по последним данным (I кв. 2025)" /><span class="error">{{ fieldErrors.registrationDate }}</span></div>
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
            <div class="item">
              <div class="value">{{ prediction.refusalOrgInTraining === false ? refusalWords(prediction.pRefusal) : pct(prediction.pRefusal) }}</div>
              <div class="label">риск отказа</div>
            </div>
          </div>
          <p v-if="prediction.refusalOrgInTraining === false" class="muted" style="margin-top: 8px">
            Организации не было в обучении, поэтому риск отказа показан словами: на незнакомых организациях модель переоценивает проценты.
          </p>
          <p v-if="prediction.queue" class="muted" style="margin-top: 8px">
            В очереди {{ prediction.queue.len }} направлений, медианный возраст {{ days(prediction.queue.ageP50) }} дн., {{ prediction.queue.throughputPerDay.toFixed(1) }} госпитализаций в день.
          </p>
        </div>
        <ExplanationCard :explanation="prediction.explanation" :model="prediction.model" unit="дн." style="margin-top: 16px" />
        <p v-if="waitQuality" class="muted" style="margin-top: 8px">
          Качество на отложенном марте 2025: пинбол p50 {{ waitQuality.pinball_p50.toFixed(2) }} против {{ waitQuality.pinball_p50_baseline.toFixed(2) }} у простого правила
          ({{ ((1 - waitQuality.pinball_p50 / waitQuality.pinball_p50_baseline) * 100).toFixed(0) }} % точнее), AUC отказа {{ waitQuality.auc_refusal.toFixed(2) }} против {{ waitQuality.auc_refusal_baseline.toFixed(2) }}.
        </p>
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
            <td><Button label="Направить сюда" size="small" severity="secondary" :disabled="!!recorded" :loading="recording" @click="record(a.mo.moCode)" /></td>
          </tr>
        </tbody>
      </table>
      <div class="field" style="margin-top: 12px"><label>Причина выбора (попадает в журнал)</label><Textarea v-model="reason" rows="2" auto-resize /></div>
      <div class="actions">
        <Button label="Оставить в выбранной организации" icon="pi pi-check" :disabled="!!recorded" :loading="recording" @click="record(form.moCode)" />
        <span v-if="recorded" class="muted">записано: {{ recorded }}</span>
      </div>
    </div>
  </main>
</template>
