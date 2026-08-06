import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  // Root path for custom domain deployment (pinnacle-tech.in)
  base: '/',
})
