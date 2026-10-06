// Shared i18n (VI + EN from day one; no hard-coded UI strings). One namespace per SPA.
import i18next, { type i18n } from 'i18next'
import { initReactI18next } from 'react-i18next'

import en from './locales/en.json'
import vi from './locales/vi.json'

export type AppNamespace = 'customer' | 'admin'
export type Language = 'vi' | 'en'

export const languages: readonly Language[] = ['vi', 'en']

export const resources = { vi, en } as const

/** Creates an initialised i18next instance for one SPA; Vietnamese first, English fallback. */
export function createI18n(ns: AppNamespace, lng: Language = 'vi'): i18n {
  const instance = i18next.createInstance()
  void instance.use(initReactI18next).init({
    resources,
    lng,
    fallbackLng: 'en',
    ns: [ns],
    defaultNS: ns,
    interpolation: { escapeValue: false },
    initAsync: false,
  })
  return instance
}
