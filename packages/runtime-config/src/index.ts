/** Runtime configuration of a SPA, injected by /config.js (ConfigMap on Kubernetes, public/config.js in dev). */
export interface RuntimeConfig {
  apiBaseUrl: string
  env: string
  release: string
}

declare global {
  interface Window {
    __BG_CONFIG__?: Partial<RuntimeConfig>
  }
}

const defaults: RuntimeConfig = { apiBaseUrl: '', env: 'local', release: 'dev' }

/** Merges window.__BG_CONFIG__ (or an explicit source) over local defaults; never bakes URLs into the bundle. */
export function getRuntimeConfig(
  source: Partial<RuntimeConfig> = globalThis.window?.__BG_CONFIG__ ?? {},
): RuntimeConfig {
  const config = { ...defaults, ...source }
  if (typeof config.apiBaseUrl !== 'string') {
    throw new Error('runtime config: apiBaseUrl must be a string')
  }
  return config
}
