import { describe, expect, it } from 'vitest'

describe('web shell', () => {
  it('has a product name', () => {
    expect('Darumen Health').toContain('Darumen')
  })
})
