import { ref } from 'vue'
import type { RecordingFormat } from '@/lib/audio'

const BARS = 32

/** Запись с микрофона для скрайба: MediaRecorder + AnalyserNode для волны (уровни по полосам) и таймер. */
export function useRecorder(format: RecordingFormat | null, onStop: (blob: Blob, filename: string) => void) {
  const recording = ref(false)
  const elapsed = ref(0)
  const levels = ref<number[]>(Array.from({ length: BARS }, () => 0.06))
  const canRecord = format !== null
  let recorder: MediaRecorder | null = null
  let chunks: Blob[] = []
  let context: AudioContext | null = null
  let analyser: AnalyserNode | null = null
  let frame = 0
  let ticker = 0

  function draw() {
    if (!analyser) return
    const data = new Uint8Array(analyser.frequencyBinCount)
    analyser.getByteFrequencyData(data)
    const step = Math.max(1, Math.floor(data.length / BARS))
    levels.value = Array.from({ length: BARS }, (_, i) => {
      let sum = 0
      for (let j = 0; j < step; j += 1) sum += data[i * step + j] ?? 0
      return Math.min(1, sum / step / 255)
    })
    frame = requestAnimationFrame(draw)
  }

  async function start() {
    if (!format) return
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true })
    recorder = new MediaRecorder(stream, { mimeType: format.mimeType })
    chunks = []
    recorder.ondataavailable = (e) => chunks.push(e.data)
    recorder.onstop = () => {
      stream.getTracks().forEach((track) => track.stop())
      onStop(new Blob(chunks, { type: format.mimeType }), `consult.${format.extension}`)
    }
    try {
      context = new AudioContext()
      analyser = context.createAnalyser()
      analyser.fftSize = 128
      context.createMediaStreamSource(stream).connect(analyser)
      frame = requestAnimationFrame(draw)
    } catch {
      analyser = null // волна — вспомогательная: без Web Audio запись всё равно идёт
    }
    elapsed.value = 0
    ticker = window.setInterval(() => (elapsed.value += 1), 1000)
    recorder.start()
    recording.value = true
  }

  function stop() {
    recorder?.stop()
    recording.value = false
    window.clearInterval(ticker)
    cancelAnimationFrame(frame)
    void context?.close()
    context = null
    analyser = null
    levels.value = levels.value.map(() => 0.06)
  }

  function dispose() {
    if (recorder?.state === 'recording') stop()
  }

  return { recording, elapsed, levels, canRecord, start, stop, dispose }
}
