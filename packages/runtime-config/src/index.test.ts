import { describe, expect, it } from 'vitest'

import { getRuntimeConfig } from './index'

describe('getRuntimeConfig', () => {
  it('returns local defaults when /config.js did not run', () => {
    expect(getRuntimeConfig({})).toEqual({ apiBaseUrl: '', env: 'local', release: 'dev' })
  })

  it('overrides defaults with the values injected by /config.js', () => {
    expect(getRuntimeConfig({ apiBaseUrl: 'https://api.kind.localhost', env: 'kind' })).toEqual({
      apiBaseUrl: 'https://api.kind.localhost',
      env: 'kind',
      release: 'dev',
    })
  })

  it('rejects a non-string apiBaseUrl', () => {
    expect(() => getRuntimeConfig({ apiBaseUrl: 42 as unknown as string })).toThrow(/apiBaseUrl/)
  })
})
