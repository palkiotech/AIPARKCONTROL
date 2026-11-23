import { defineConfig, loadEnv } from 'vite'
import vue from '@vitejs/plugin-vue'
import { VitePWA } from 'vite-plugin-pwa'
import path from 'path'

export default defineConfig(({ command, mode }) => {
  // Las claves de Supabase quedan dentro del código al compilar. Sin ellas la app
  // se publica apuntando a un servidor inexistente: mejor que el build falle.
  if (command === 'build') {
    const env = loadEnv(mode, process.cwd(), 'VITE_')
    const faltan = ['VITE_SUPABASE_URL', 'VITE_SUPABASE_ANON_KEY'].filter((k) => !env[k])
    if (faltan.length) {
      throw new Error(
        `Faltan ${faltan.join(' y ')} al compilar. En local van en .env; en Cloudflare, ` +
        'en Settings → Build → Variables and secrets (no en las variables de runtime).'
      )
    }
  }

  return {
  plugins: [
    vue(),
    VitePWA({
      registerType: 'autoUpdate',
      includeAssets: ['favicon.svg', 'icons/*.png'],
      manifest: {
        name: 'ParkControl',
        short_name: 'ParkControl',
        description: 'Gestión inteligente y ágil para parqueaderos',
        theme_color: '#1d4ed8',
        background_color: '#f5f6f8',
        display: 'standalone',
        orientation: 'any',
        start_url: '/',
        icons: [
          {
            src: '/icons/icon-192.png',
            sizes: '192x192',
            type: 'image/png'
          },
          {
            src: '/icons/icon-512.png',
            sizes: '512x512',
            type: 'image/png'
          },
          {
            src: '/icons/icon-maskable-512.png',
            sizes: '512x512',
            type: 'image/png',
            purpose: 'maskable'
          }
        ]
      },
      workbox: {
        globPatterns: ['**/*.{js,css,html,ico,png,svg,woff2}']
      }
    })
  ],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src')
    }
  }
  }
})
