import { theme, type ThemeConfig } from 'antd'

import { tokens, type ThemeMode } from './tokens'

/** Ant Design ConfigProvider theme for a mode (light: defaultAlgorithm, dark: darkAlgorithm + overrides). */
export function getThemeConfig(mode: ThemeMode): ThemeConfig {
  const t = tokens[mode]
  return {
    algorithm: mode === 'dark' ? theme.darkAlgorithm : theme.defaultAlgorithm,
    token: {
      colorPrimary: t.primary,
      colorSuccess: t.success,
      colorWarning: t.warning,
      colorError: t.error,
      colorInfo: t.info,
      colorBgBase: t.surfaceBase,
      colorBgContainer: t.surfaceElevated,
      colorBorder: t.border,
      colorTextBase: t.text,
      colorTextSecondary: t.textSecondary,
      borderRadius: 4,
      fontFamily:
        "Inter, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif",
    },
    components: {
      Button: { colorPrimaryHover: t.primaryHover },
    },
  }
}
