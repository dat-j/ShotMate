import swc from 'unplugin-swc';
import { defineConfig } from 'vitest/config';

// See vitest.config.ts for why unplugin-swc is required (esbuild can't emit
// decorator metadata that NestJS's DI container needs).
export default defineConfig({
  plugins: [swc.vite()],
  test: {
    include: ['**/*.integration.spec.ts'],
    exclude: ['**/node_modules/**', '**/dist/**'],
    testTimeout: 20000,
  },
});
