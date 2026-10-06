import { theme } from 'antd'
import { describe, expect, it } from 'vitest'

import { getThemeConfig, tokens } from './index'

describe('getThemeConfig', () => {
  it('maps light tokens with the default algorithm', () => {
    const cfg = getThemeConfig('light')
    expect(cfg.algorithm).toBe(theme.defaultAlgorithm)
    expect(cfg.token?.colorPrimary).toBe('#1F3A68')
    expect(cfg.token?.borderRadius).toBe(4)
  })

  it('maps dark tokens with the dark algorithm', () => {
    const cfg = getThemeConfig('dark')
    expect(cfg.algorithm).toBe(theme.darkAlgorithm)
    expect(cfg.token?.colorBgBase).toBe(tokens.dark.surfaceBase)
  })
})
