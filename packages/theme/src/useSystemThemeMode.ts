import { useSyncExternalStore } from 'react'

import type { ThemeMode } from './tokens'

const query = '(prefers-color-scheme: dark)'

function subscribe(onChange: () => void): () => void {
  if (typeof window === 'undefined' || typeof window.matchMedia !== 'function') return () => {}
  const mql = window.matchMedia(query)
  mql.addEventListener('change', onChange)
  return () => mql.removeEventListener('change', onChange)
}

function getSnapshot(): ThemeMode {
  if (typeof window === 'undefined' || typeof window.matchMedia !== 'function') return 'light'
  return window.matchMedia(query).matches ? 'dark' : 'light'
}

/** Follows the OS light/dark preference (design-system: "Sáng/tối theo OS"). */
export function useSystemThemeMode(): ThemeMode {
  return useSyncExternalStore(subscribe, getSnapshot, () => 'light')
}
