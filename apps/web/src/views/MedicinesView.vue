<script setup lang="ts">
import Button from 'primevue/button'
import Select from 'primevue/select'
import Tag from 'primevue/tag'
import { onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { medicines } from '@/api/endpoints'
import type { CheckResponse, Mnn, Nosology } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import OriginTag from '@/components/OriginTag.vue'
import { days, num, pct } from '@/lib/format'
import { useRefdataStore } from '@/stores/refdata'

const { t } = useI18n()
const refdata = useRefdataStore()
const nosologies = ref<Nosology[]>([])
const mnns = ref<Mnn[]>([])
const nosologyId = ref<string | null>(null)
const mnnId = ref<string | null>(null)
const region = ref('75')
const result = ref<CheckResponse | null>(null)
const error = ref<unknown>(null)
const busy = ref(false)

async function loadMnn() {
  if (!nosologyId.value) return
  mnns.value = (await medicines.mnn(nosologyId.value)).items
  mnnId.value = mnns.value[0]?.mnnId ?? null
}

async function check() {
  busy.value = true
  error.value = null
  try {
    result.value = await medicines.check({ mnnId: mnnId.value, nosologyId: nosologyId.value, regionKato: region.value })
  } catch (e) {
    error.value = e
    result.value = null
  } finally {
    busy.value = false
  }
}

onMounted(async () => {
  await refdata.load()
  try {
    nosologies.value = (await medicines.nosologies()).items
    nosologyId.value = nosologies.value[0]?.nosologyId ?? null
    await loadMnn()
    await check()
  } catch (e) {
    error.value = e
  }
})
watch(nosologyId, loadMnn)
</script>

<template>
  <main class="page">
    <h1>{{ t('medicines.title') }}</h1>
    <p class="lead">{{ t('medicines.lead') }}</p>
    <div class="card">
      <div class="form-grid">
        <div class="field"><label>{{ t('medicines.nosology') }}</label><Select v-model="nosologyId" :options="nosologies" option-value="nosologyId" filter :option-label="(n: Nosology) => t('medicines.nosologyOption', { id: n.nosologyId, count: num(n.issued12m) })" /></div>
        <div class="field"><label>{{ t('medicines.mnn') }}</label><Select v-model="mnnId" :options="mnns" option-value="mnnId" filter :option-label="(m: Mnn) => t('medicines.mnnOption', { id: m.mnnId, count: num(m.issued12m) })" /></div>
        <div class="field"><label>{{ t('common.region') }}</label><Select v-model="region" :options="refdata.regions" option-label="name" option-value="regionKato" filter /></div>
      </div>
      <div class="actions"><Button :label="t('medicines.check')" icon="pi pi-check-circle" :loading="busy" @click="check" /></div>
      <ErrorBox :error="error" />
    </div>
    <div v-if="result" class="grid cols-2" style="margin-top: 16px">
      <div class="card">
        <h2>{{ t('medicines.coverage') }} <OriginTag kind="formula" :note="t('medicines.coverageNote')" /></h2>
        <p><Tag :value="result.covered ? t('medicines.covered') : t('medicines.notCovered')" :severity="result.covered ? 'success' : 'warn'" /> <span v-if="result.program">{{ result.program }}, {{ t('medicines.category') }} {{ result.category }}</span></p>
        <h2 style="margin-top: 16px">{{ t('medicines.fillTiming') }}</h2>
        <div class="kpi">
          <div class="item"><div class="value">{{ days(result.fillDaysP50) }}</div><div class="label">{{ t('medicines.median') }}, {{ t('common.days') }}</div></div>
          <div class="item"><div class="value">{{ days(result.fillDaysP90) }}</div><div class="label">p90, {{ t('common.days') }}</div></div>
          <div class="item"><div class="value">{{ pct(result.pFilled14d) }}</div><div class="label">{{ t('medicines.within14') }}</div></div>
        </div>
        <p class="muted">{{ result.basis }}</p>
      </div>
      <div class="card">
        <h2>{{ t('medicines.shortage') }}</h2>
        <p><Tag :value="result.shortage.flag ? t('medicines.shortageFlag') : t('medicines.noShortageFlag')" :severity="result.shortage.flag ? 'danger' : 'success'" /> {{ t('medicines.score') }} {{ result.shortage.score.toFixed(2) }}</p>
        <p class="muted">{{ result.shortage.basis }}</p>
        <h2 style="margin-top: 16px">{{ t('medicines.otherMnn') }}</h2>
        <p v-if="result.alternatives.length === 0" class="muted">{{ t('common.empty') }}</p>
        <div v-for="a in result.alternatives" :key="a.mnnId" class="factor"><span>{{ a.name }}</span><span class="contribution">{{ num(a.issued12m) }} / {{ t('medicines.perYear') }}</span></div>
        <p class="muted" style="margin-top: 8px">{{ t('medicines.pharmaciesHint') }} {{ result.model.name }} {{ result.model.version }}, {{ t('medicines.dataThrough') }} {{ result.model.trainedThrough }}.</p>
      </div>
    </div>
  </main>
</template>
