<script setup lang="ts">
import { Map as MapLibreMap, Marker, NavigationControl } from 'maplibre-gl'
import { onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { i18n } from '@/i18n'
import type { IndexItem, Region } from '@/api/types'
import { useChartTheme } from '@/composables/useChartTheme'
import { indexColor } from '@/lib/format'

const props = defineProps<{ regions: Region[]; index: IndexItem[] }>()
const emit = defineEmits<{ select: [kato: string] }>()
const t = i18n.global.t

const container = ref<HTMLDivElement | null>(null)
const { isDark } = useChartTheme()
// тёмный стиль тайлов — только если задан явно; иначе светлый стиль затемняется CSS-фильтром на канвасе (маркеры — DOM, их не трогает)
const LIGHT_STYLE = import.meta.env.VITE_MAP_STYLE || 'https://tiles.openfreemap.org/styles/liberty'
const DARK_STYLE = import.meta.env.VITE_MAP_STYLE_DARK || ''
let map: MapLibreMap | null = null
let markers: Marker[] = []

/** DOM-маркеры в столицах регионов: цвет по индексу, размер по населению. Не зависят от загрузки тайлов
 * и воркеров; полигоны регионов появятся вместе с ГИС-справочником. */
function render() {
  if (!map) return
  for (const marker of markers) marker.remove()
  markers = []
  const byKato = new Map(props.index.map((i) => [i.regionKato, i]))
  for (const region of props.regions) {
    if (region.lat === null || region.lon === null) continue
    const item = byKato.get(region.regionKato)
    const size = Math.round(22 + Math.sqrt(region.populationThousands ?? 300) / 2)
    const element = document.createElement('button')
    element.type = 'button'
    element.className = 'region-marker'
    element.style.setProperty('--size', `${size}px`)
    element.style.setProperty('--color', item ? indexColor(item.indexValue, isDark.value) : 'var(--dm-faint)')
    element.title = t('regionMap.tooltip', { name: region.name, value: item ? item.indexValue.toFixed(1) : '—', rank: item ? t('regionMap.rank', { rank: item.rank }) : '' })
    element.setAttribute('aria-label', element.title)
    element.innerHTML = `<span class="dot">${item ? Math.round(item.indexValue) : '·'}</span><span class="label">${region.name}</span>`
    element.addEventListener('click', () => emit('select', region.regionKato))
    markers.push(new Marker({ element, anchor: 'center' }).setLngLat([region.lon, region.lat]).addTo(map))
  }
}

onMounted(() => {
  if (!container.value) return
  map = new MapLibreMap({
    container: container.value,
    style: isDark.value && DARK_STYLE ? DARK_STYLE : LIGHT_STYLE,
    center: [67.5, 48.5],
    zoom: 3.6,
    attributionControl: { compact: true },
  })
  map.addControl(new NavigationControl({ showCompass: false }), 'top-right')
  render()
})

watch(() => [props.regions, props.index], render, { deep: true })
watch(isDark, (dark) => {
  if (DARK_STYLE) map?.setStyle(dark ? DARK_STYLE : LIGHT_STYLE)
  render()
})
onBeforeUnmount(() => {
  for (const marker of markers) marker.remove()
  map?.remove()
})
</script>

<template>
  <div ref="container" class="map" :class="{ 'map--filtered-dark': isDark && !DARK_STYLE }" />
</template>

<style>
.region-marker { background: none; border: 0; padding: 0; cursor: pointer; display: flex; flex-direction: column; align-items: center; gap: 2px; font: inherit; }
.region-marker .dot { width: var(--size); height: var(--size); border-radius: 50%; background: var(--color); color: #fff; font-weight: 700; font-size: 12px; display: grid; place-items: center; border: 2px solid var(--dm-surface); box-shadow: var(--dm-shadow); }
.region-marker .label { font-size: 11px; color: var(--dm-ink); background: color-mix(in srgb, var(--dm-surface) 85%, transparent); padding: 1px 4px; border-radius: 4px; white-space: nowrap; }
.map--filtered-dark .maplibregl-canvas { filter: invert(0.92) hue-rotate(180deg) brightness(0.85) saturate(0.6); }
.region-marker:hover .dot { transform: scale(1.1); }
</style>
