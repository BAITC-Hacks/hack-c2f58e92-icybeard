import { defineStore } from 'pinia'
import { ref } from 'vue'
import { refdata } from '@/api/endpoints'
import type { OrganizationItem, Profile, Region } from '@/api/types'

/** Справочники загружаются один раз и кэшируются на сессию. */
export const useRefdataStore = defineStore('refdata', () => {
  const regions = ref<Region[]>([])
  const profiles = ref<Profile[]>([])
  const organizations = ref<Record<string, OrganizationItem[]>>({})
  const loaded = ref(false)

  async function load() {
    if (loaded.value) return
    const [r, p] = await Promise.all([refdata.regions(), refdata.profiles()])
    regions.value = r.items
    profiles.value = p.items.filter((x) => !x.isDayHospital)
    loaded.value = true
  }

  /** Организации региона; с профилем только те, у кого есть очередь по этому профилю, сначала самые загруженные. */
  async function organizationsOf(regionKato: string, profileCode?: string): Promise<OrganizationItem[]> {
    const key = profileCode ? `${regionKato}:${profileCode}` : regionKato
    if (!organizations.value[key]) {
      organizations.value[key] = (await refdata.organizations(regionKato, undefined, profileCode)).items
    }
    return organizations.value[key]
  }

  function regionName(kato: string | null | undefined): string {
    return regions.value.find((r) => r.regionKato === kato)?.name ?? kato ?? '—'
  }

  function profileName(code: string | null | undefined): string {
    return profiles.value.find((p) => p.profileCode === code)?.name ?? code ?? '—'
  }

  return { regions, profiles, loaded, load, organizationsOf, regionName, profileName }
})
