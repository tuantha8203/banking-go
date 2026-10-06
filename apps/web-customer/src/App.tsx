import { getThemeConfig, useSystemThemeMode } from '@banking-go/theme'
import { App as AntApp, ConfigProvider, Layout, Typography } from 'antd'
import { I18nextProvider, useTranslation } from 'react-i18next'

import { i18n } from './i18n'

function Home() {
  const { t } = useTranslation()
  return (
    <Layout style={{ minHeight: '100vh', padding: 24 }}>
      <Typography.Title level={1}>{t('app.title')}</Typography.Title>
    </Layout>
  )
}

export function App() {
  const mode = useSystemThemeMode()
  return (
    <I18nextProvider i18n={i18n}>
      <ConfigProvider theme={getThemeConfig(mode)}>
        <AntApp>
          <Home />
        </AntApp>
      </ConfigProvider>
    </I18nextProvider>
  )
}
