<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import type { OverloadedOrganization } from '@/api/types'
import ArrowPager from '@/components/ui/ArrowPager.vue'
import { num, pct, shortOrgName } from '@/lib/format'
import { useRefdataStore } from '@/stores/refdata'

/** Перегруженные больницы: «Больница · регион и профиль | Приходит на 1 госпитализацию | В очереди | 9 из 10 ждут до |
 * Отказов» и значок симулятора в строке (подпись — во всплывающей подсказке и в пояснении над таблицей). Клик по
 * строке — кабинет больницы. Листание по `size` строк. */
const props = withDefaults(defineProps<{ items: OverloadedOrganization[]; size?: number }>(), { size: 5 })
const emit = defineEmits<{ organization: [moCode: string]; simulate: [item: OverloadedOrganization] }>()
const { t } = useI18n()
const refdata = useRefdataStore()
const page = ref(0)
const rows = computed(() => props.items.slice(page.value * props.size, (page.value + 1) * props.size))
watch(() => props.items, () => (page.value = 0))

/** Больше 1 — направлений приходит больше, чем больница успевает госпитализировать: очередь растёт; null —
 * госпитализаций нет вовсе при живом потоке, это тоже перегрузка, просто без коэффициента. */
function loadLabel(load: number | null): string {
  return load === null ? t('overloadedTable.noAdmissions') : t('overloadedTable.loadValue', { n: num(load, 1) })
}
</script>

<template>
  <p v-if="!items.length" class="muted">{{ t('overloadedTable.none') }}</p>
  <template v-else>
    <div class="table-wrap">
      <table class="dense-table overloaded">
        <thead>
          <tr>
            <th>{{ t('overloadedTable.hospital') }}</th>
            <th class="num" :title="t('overloadedTable.loadHint')">{{ t('overloadedTable.load') }}</th>
            <th class="num">{{ t('overloadedTable.queue') }}</th>
            <th class="num" :title="t('overloadedTable.p90Hint')">{{ t('overloadedTable.p90') }}</th>
            <th class="num">{{ t('overloadedTable.refusals') }}</th>
            <th class="act" aria-hidden="true"></th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="item in rows" :key="item.moCode + item.profileCode" class="clickable" @click="emit('organization', item.moCode)">
            <td class="org">
              <span class="org-name" :title="item.name">{{ shortOrgName(item.name) }}</span>
              <span class="caption">{{ refdata.regionName(item.regionKato) }} · {{ refdata.profileName(item.profileCode) }}</span>
            </td>
            <td class="num" :class="{ hot: item.load === null || item.load > 1 }">{{ loadLabel(item.load) }}</td>
            <td class="num tabular">{{ item.queueLen }}</td>
            <td class="num tabular" :class="{ hot: (item.queueAgeP90 ?? 0) > 60 }">{{ item.queueAgeP90 !== null ? t('overloadedTable.days', { n: item.queueAgeP90.toFixed(0) }) : '—' }}</td>
            <td class="num tabular">{{ pct(item.refusalRate4w) }}</td>
            <td class="act">
              <button type="button" class="sim-btn" :title="t('overloadedTable.simulateHint')" :aria-label="t('overloadedTable.simulateHint')" @click.stop="emit('simulate', item)">
                <i class="pi pi-sliders-h" aria-hidden="true" />
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <ArrowPager v-model:page="page" :total="items.length" :size="size" />
  </template>
</template>

<style scoped>
.overloaded td { height: 56px; }
.org { max-width: 420px; }
.org-name { display: block; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; font-weight: 600; }
.org .caption { display: block; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.hot { color: var(--danger-strong); }
.act { width: 48px; text-align: right; }
.sim-btn { width: 34px; height: 34px; border-radius: 50%; border: 1px solid var(--border-soft); background: var(--surface); color: var(--accent); display: inline-grid; place-items: center; cursor: pointer; }
.sim-btn:hover { background: var(--accent-soft); }
</style>
