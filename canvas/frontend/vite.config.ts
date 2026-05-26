import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      '/ws': { target: 'ws://localhost:8765', ws: true },
      '/session': { target: 'http://localhost:8765' },
      '/media': { target: 'http://localhost:8765' },
      '/trace': { target: 'http://localhost:8765' },
    },
  },
  build: {
    outDir: 'dist',
    emptyOutDir: true,
  },
})
