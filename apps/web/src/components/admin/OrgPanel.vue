<script setup lang="ts">
import Button from 'primevue/button'
import { computed, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRouter } from 'vue-router'
import type { AdminOrg } from '@/api/types'
import StateError from '@/components/states/StateError.vue'
import Skeleton from '@/components/ui/Skeleton.vue'
import StatusTag from '@/components/ui/StatusTag.vue'
import { useLocaleFormat } from '@/composables/useLocaleFormat'
import { daysSince, FRESH_DAYS } from '@/lib/admin'
import { shortOrgName } from '@/lib/format'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'

/** Панель организации (W-Admin-Orgs): код, регион и тип, администраторы организации (из Keycloak), источники данных
 * со свежестью последней загруженной партии («в норме» / «задержка N дн.»), «Открыть кабинет →» (при org.cabinet). */
const props = defineProps<{ org: AdminOrg | null; loading: boolean; error: unknown }>()
const emit = defineEmits<{ retry: [] }>()
const { t, te } = useI18n()
const { dateTime, num } = useLocaleFormat()
const auth = useAuthStore()
const refdata = useRefdataStore()
const router = useRouter()

const datasetTitle = (dataset: string) => (te(`admin.orgs.dataset.${dataset}`) ? t(`admin.orgs.dataset.${dataset}`) : dataset)
/** Наборы очередей (bg_*) — первыми; по умолчанию видно пять. */
const VISIBLE = 5
const showAll = ref(false)
watch(() => props.org?.moCode, () => (showAll.value = false))
const sources = computed(() => [...(props.org?.freshness ?? [])].sort((a, b) => Number(!a.dataset.startsWith('bg_')) - Number(!b.dataset.startsWith('bg_'))))
const shownSources = computed(() => (showAll.value ? sources.value : sources.value.slice(0, VISIBLE)))
const typeLabel = (type: string | null) => (type && te(`admin.orgs.type.${type}`) ? t(`admin.orgs.type.${type}`) : type ?? '—')
</script>

<template>
  <section class="card org-panel" data-testid="org-panel">
    <StateError v-if="error" :error="error" compact @retry="emit('retry')" />
    <Skeleton v-else-if="loading || !org" :lines="6" />
    <template v-else>
      <h2 class="org-title" :title="org.name">{{ shortOrgName(org.name) }}</h2>
      <div class="meta"><StatusTag :value="org.moCode" /><span class="muted small">{{ [org.regionKato ? refdata.regionName(org.regionKato) : null, typeLabel(org.type)].filter(Boolean).join(' · ') }}</span></div>

      <span class="eyebrow">{{ t('admin.orgs.adminTitle') }}</span>
      <div v-for="a in org.admins ?? []" :key="a.id">
        <div class="admin-name">{{ a.displayName ?? a.email ?? '—' }}</div>
        <div class="caption">{{ [a.email, org.users !== null ? t('admin.orgs.usersInOrg', { n: num(org.users) }) : null].filter(Boolean).join(' · ') }}</div>
      </div>
      <p v-if="!org.admins?.length" class="muted small">{{ t('admin.orgs.noAdmin') }}</p>

      <span class="eyebrow">{{ t('admin.orgs.sources') }}</span>
      <div v-if="sources.length" class="rows">
        <div v-for="s in shownSources" :key="s.dataset" class="row">
          <span class="row-main">{{ datasetTitle(s.dataset) }}<div class="row-sub">{{ s.lastLoadedAt ? t('admin.orgs.loadedAt', { at: dateTime(s.lastLoadedAt) }) : t('admin.orgs.neverLoaded') }}</div></span>
          <span class="row-value">
            <StatusTag v-if="!s.lastLoadedAt" :value="t('admin.orgs.noData')" />
            <StatusTag v-else-if="(daysSince(s.lastLoadedAt) ?? 0) > FRESH_DAYS" :value="t('admin.orgs.delay', { n: daysSince(s.lastLoadedAt) })" tone="info" />
            <StatusTag v-else :value="t('admin.orgs.fresh')" tone="ok" />
          </span>
        </div>
      </div>
      <button v-if="sources.length > VISIBLE" type="button" class="text-link small toggle" @click="showAll = !showAll">{{ showAll ? t('admin.orgs.showLess') : t('admin.orgs.showAll', { n: sources.length }) }}</button>
      <p v-if="!sources.length" class="muted small">{{ t('admin.orgs.noSources') }}</p>
      <p class="caption">{{ t('admin.orgs.staleNote', { n: FRESH_DAYS }) }}</p>
      <Button v-if="auth.can('org.cabinet')" :label="t('admin.orgs.openCabinet')" icon="pi pi-arrow-right" icon-pos="right" data-testid="org-open-cabinet" @click="router.push(`/gov/organizations/${org.moCode}`)" />
    </template>
  </section>
</template>

<style scoped>
.org-panel { display: flex; flex-direction: column; gap: 10px; }
.org-title { margin: 0; font-size: var(--dm-text-lg); }
.meta { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
.admin-name { font-size: var(--dm-text-md); font-weight: 500; }
.eyebrow { margin-top: 6px; }
.toggle { align-self: flex-start; font-size: var(--dm-text-sm); }
</style>
