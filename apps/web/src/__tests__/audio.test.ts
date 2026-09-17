import { describe, expect, it } from 'vitest'
import { pickRecordingFormat } from '@/lib/audio'

describe('recording format', () => {
  it('prefers webm and falls back to mp4 for Safari', () => {
    expect(pickRecordingFormat(() => true)).toEqual({ mimeType: 'audio/webm;codecs=opus', extension: 'webm' })
    expect(pickRecordingFormat((type) => type === 'audio/mp4')).toEqual({ mimeType: 'audio/mp4', extension: 'm4a' })
    expect(pickRecordingFormat(() => false)).toBeNull()
  })
})
