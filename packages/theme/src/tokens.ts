// Colour tokens "Hải quân Định chế" from docs/foundation/design-system.md (light + dark).
export type ThemeMode = 'light' | 'dark'

export interface BankTokens {
  primary: string
  primaryHover: string
  surfaceBase: string
  surfaceElevated: string
  border: string
  text: string
  textSecondary: string
  success: string
  warning: string
  error: string
  info: string
  moneyIn: string
  moneyOut: string
}

export const tokens: Record<ThemeMode, BankTokens> = {
  light: {
    primary: '#1F3A68',
    primaryHover: '#2C4F8A',
    surfaceBase: '#F3F5F9',
    surfaceElevated: '#FFFFFF',
    border: '#D3DAE6',
    text: '#13203A',
    textSecondary: '#4A5772',
    success: '#1D7A4C',
    warning: '#8F5B00',
    error: '#B42318',
    info: '#1F5FAD',
    moneyIn: '#1D7A4C',
    moneyOut: '#A0392A',
  },
  dark: {
    primary: '#4170C0',
    // Darker than primary on purpose to keep AA contrast.
    primaryHover: '#3866B2',
    surfaceBase: '#0C1424',
    surfaceElevated: '#142038',
    border: '#283851',
    text: '#E6ECF5',
    textSecondary: '#A4B0C6',
    success: '#5FC290',
    warning: '#E5B045',
    error: '#F08A7E',
    info: '#7FB0EE',
    moneyIn: '#5FC290',
    moneyOut: '#F0A08E',
  },
}
