import { describe, expect, it } from 'vitest'

import { createI18n, resources } from './index'

describe('createI18n', () => {
  it('translates app.title in vi and en', () => {
    expect(createI18n('customer', 'vi').t('app.title')).toBe('Ngân hàng số banking-go')
    expect(createI18n('admin', 'en').t('app.title')).toBe('banking-go Back Office')
  })

  it('has the same keys in every language', () => {
    expect(Object.keys(resources.en)).toEqual(Object.keys(resources.vi))
  })
})
