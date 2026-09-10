<script setup lang="ts">
import Button from 'primevue/button'
import Select from 'primevue/select'
import Tag from 'primevue/tag'
import { onMounted, ref, watch } from 'vue'
import { medicines } from '@/api/endpoints'
import type { CheckResponse, Mnn, Nosology } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import { days, num, pct } from '@/lib/format'
import { useRefdataStore } from '@/stores/refdata'

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
    <h1>Проверка рецепта</h1>
    <p class="lead">Покрыт ли препарат программой, за сколько дней его обычно получают и нет ли признаков дефицита. По открытым данным о выписанных и обеспеченных рецептах с 2018 года; названия МНН и аптек появятся со справочниками.</p>
    <div class="card">
      <div class="form-grid">
        <div class="field"><label>Нозология (по объёму рецептов)</label><Select v-model="nosologyId" :options="nosologies" option-value="nosologyId" filter :option-label="(n: Nosology) => `Нозология ${n.nosologyId} · ${num(n.issued12m)} рецептов/год`" /></div>
        <div class="field"><label>МНН</label><Select v-model="mnnId" :options="mnns" option-value="mnnId" filter :option-label="(m: Mnn) => `МНН ${m.mnnId} · ${num(m.issued12m)} рецептов/год`" /></div>
        <div class="field"><label>Регион</label><Select v-model="region" :options="refdata.regions" option-label="name" option-value="regionKato" filter /></div>
      </div>
      <div class="actions"><Button label="Проверить" icon="pi pi-check-circle" :loading="busy" @click="check" /></div>
      <ErrorBox :error="error" />
    </div>
    <div v-if="result" class="grid cols-2" style="margin-top: 16px">
      <div class="card">
        <h2>Покрытие</h2>
        <p><Tag :value="result.covered ? 'покрыт программой' : 'активных спецификаций нет'" :severity="result.covered ? 'success' : 'warn'" /> <span v-if="result.program">{{ result.program }}, категория {{ result.category }}</span></p>
        <h2 style="margin-top: 16px">Сроки обеспечения</h2>
        <div class="kpi">
          <div class="item"><div class="value">{{ days(result.fillDaysP50) }}</div><div class="label">медиана, дн.</div></div>
          <div class="item"><div class="value">{{ days(result.fillDaysP90) }}</div><div class="label">p90, дн.</div></div>
          <div class="item"><div class="value">{{ pct(result.pFilled14d) }}</div><div class="label">получают за 14 дней</div></div>
        </div>
        <p class="muted">{{ result.basis }}</p>
      </div>
      <div class="card">
        <h2>Дефицит</h2>
        <p><Tag :value="result.shortage.flag ? 'признаки дефицита' : 'без признаков дефицита'" :severity="result.shortage.flag ? 'danger' : 'success'" /> балл {{ result.shortage.score.toFixed(2) }}</p>
        <p class="muted">{{ result.shortage.basis }}</p>
        <h2 style="margin-top: 16px">Другие МНН при этой нозологии</h2>
        <p v-if="result.alternatives.length === 0" class="muted">нет</p>
        <div v-for="a in result.alternatives" :key="a.mnnId" class="factor"><span>{{ a.name }}</span><span class="contribution">{{ num(a.issued12m) }} / год</span></div>
        <p class="muted" style="margin-top: 8px">Аптеки рядом появятся после справочника аптек с координатами. {{ result.model.name }} {{ result.model.version }}, данные по {{ result.model.trainedThrough }}.</p>
      </div>
    </div>
  </main>
</template>
