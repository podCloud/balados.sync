import { defineConfig } from 'vitest/config'
import { resolve } from 'path'

export default defineConfig({
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./js/__tests__/setup.ts'],
    include: ['js/__tests__/**/*.test.ts'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
      include: ['js/**/*.ts'],
      exclude: ['js/__tests__/**', 'js/types/**']
    }
  },
  resolve: {
    alias: {
      '@': resolve(__dirname, './js')
    }
  }
})
