<script setup lang="ts">
import { Map as MapLibreMap, Marker, NavigationControl } from 'maplibre-gl'
import { onBeforeUnmount, onMounted, ref, watch } from 'vue'
import type { IndexItem, Region } from '@/api/types'
import { indexColor } from '@/lib/format'

const props = defineProps<{ regions: Region[]; index: IndexItem[] }>()
const emit = defineEmits<{ select: [kato: string] }>()

const container = ref<HTMLDivElement | null>(null)
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
    element.style.setProperty('--color', item ? indexColor(item.indexValue) : '#9aa5b1')
    element.title = `${region.name}: индекс ${item ? item.indexValue.toFixed(1) : '—'}${item ? `, место ${item.rank}` : ''}`
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
    style: import.meta.env.VITE_MAP_STYLE || 'https://tiles.openfreemap.org/styles/liberty',
    center: [67.5, 48.5],
    zoom: 3.6,
    attributionControl: { compact: true },
  })
  map.addControl(new NavigationControl({ showCompass: false }), 'top-right')
  render()
})

watch(() => [props.regions, props.index], render, { deep: true })
onBeforeUnmount(() => {
  for (const marker of markers) marker.remove()
  map?.remove()
})
</script>

<template>
  <div ref="container" class="map" />
</template>

<style>
.region-marker { background: none; border: 0; padding: 0; cursor: pointer; display: flex; flex-direction: column; align-items: center; gap: 2px; font: inherit; }
.region-marker .dot { width: var(--size); height: var(--size); border-radius: 50%; background: var(--color); color: #fff; font-weight: 700; font-size: 12px; display: grid; place-items: center; border: 2px solid #fff; box-shadow: 0 1px 4px rgba(0, 0, 0, 0.35); }
.region-marker .label { font-size: 11px; color: #1f2933; background: rgba(255, 255, 255, 0.85); padding: 1px 4px; border-radius: 4px; white-space: nowrap; }
.region-marker:hover .dot { transform: scale(1.1); }
</style>
