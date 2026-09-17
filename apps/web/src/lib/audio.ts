/** Форматы записи в порядке предпочтения: Chrome и Firefox пишут WebM/Ogg, Safari — только MP4. */
const RECORDING_FORMATS: { mimeType: string; extension: string }[] = [
  { mimeType: 'audio/webm;codecs=opus', extension: 'webm' },
  { mimeType: 'audio/webm', extension: 'webm' },
  { mimeType: 'audio/mp4', extension: 'm4a' },
  { mimeType: 'audio/ogg;codecs=opus', extension: 'ogg' },
]

export interface RecordingFormat { mimeType: string; extension: string }

/**
 * Первый формат, который умеет записывать браузер; null — MediaRecorder недоступен.
 * `isSupported` передаётся параметром, чтобы функцию можно было проверить без браузера.
 */
export function pickRecordingFormat(isSupported: (mimeType: string) => boolean): RecordingFormat | null {
  return RECORDING_FORMATS.find((f) => isSupported(f.mimeType)) ?? null
}
