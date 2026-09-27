import { defineStore } from 'pinia'
import { computed, ref } from 'vue'
import { refdata } from '@/api/endpoints'
import type { OrganizationItem, Profile, Region } from '@/api/types'

/** Справочники загружаются один раз и кэшируются на сессию. */
export const useRefdataStore = defineStore('refdata', () => {
  const regions = ref<Region[]>([])
  const profiles = ref<Profile[]>([])
  /** Всего направлений по всем профилям справочника (включая дневные стационары) — факт о данных на главной. */
  const referralsTotal = ref(0)
  const organizations = ref<Record<string, OrganizationItem[]>>({})
  /** Названия организаций по коду: наполняется из списков регионов и точечных запросов. */
  const organizationNames = ref<Record<string, string>>({})
  const loaded = ref(false)
  const regionsCount = computed(() => regions.value.length)

  async function load() {
    if (loaded.value) return
    const [r, p] = await Promise.all([refdata.regions(), refdata.profiles()])
    regions.value = r.items
    profiles.value = p.items.filter((x) => !x.isDayHospital)
    referralsTotal.value = p.items.reduce((sum, x) => sum + x.referrals, 0)
    loaded.value = true
  }

  function remember(items: OrganizationItem[]) {
    for (const item of items) organizationNames.value[item.moCode] = item.name
  }

  /** Организации региона; с профилем только те, у кого есть очередь по этому профилю, сначала самые загруженные. */
  async function organizationsOf(regionKato: string, profileCode?: string): Promise<OrganizationItem[]> {
    const key = profileCode ? `${regionKato}:${profileCode}` : regionKato
    if (!organizations.value[key]) {
      organizations.value[key] = (await refdata.organizations(regionKato, undefined, profileCode)).items
      remember(organizations.value[key])
    }
    return organizations.value[key]
  }

  /** Весь справочник организаций (до 1000) — фильтры администрирования; загружается один раз. */
  const allOrganizationsList = ref<OrganizationItem[] | null>(null)
  async function allOrganizations(): Promise<OrganizationItem[]> {
    if (!allOrganizationsList.value) {
      allOrganizationsList.value = (await refdata.organizations(undefined, undefined, undefined, 1000)).items
      remember(allOrganizationsList.value)
    }
    return allOrganizationsList.value
  }

  /** Подгружает названия организаций, которых ещё нет в кэше (поиск реестра принимает точный код). */
  async function resolveOrganizations(moCodes: Iterable<string>): Promise<void> {
    const missing = [...new Set(moCodes)].filter((code) => code && !(code in organizationNames.value))
    const found = await Promise.all(
      missing.map((code) => refdata.organizations(undefined, code, undefined, 5).then((r) => r.items.filter((o) => o.moCode === code))),
    )
    remember(found.flat())
  }

  function regionName(kato: string | null | undefined): string {
    return regions.value.find((r) => r.regionKato === kato)?.name ?? kato ?? '—'
  }

  function profileName(code: string | null | undefined): string {
    return profiles.value.find((p) => p.profileCode === code)?.name ?? code ?? '—'
  }

  /** Профиль с наибольшим числом направлений — дефолт страниц региона и организации вместо зашитого кода. */
  function topProfileCode(): string {
    return [...profiles.value].sort((a, b) => b.referrals - a.referrals)[0]?.profileCode ?? ''
  }

  function organizationName(moCode: string | null | undefined): string {
    if (!moCode) return '—'
    return organizationNames.value[moCode] ?? moCode
  }

  return {
    regions, profiles, referralsTotal, regionsCount, loaded, load, organizationsOf, allOrganizations, resolveOrganizations, regionName, profileName, organizationName, topProfileCode,
  }
})
