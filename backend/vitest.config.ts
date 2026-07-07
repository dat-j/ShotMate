import swc from 'unplugin-swc';
import { defineConfig } from 'vitest/config';

/**
 * `unplugin-swc` — Vite/Vitest transforms TS via esbuild by default, which
 * cannot emit `design:paramtypes` decorator metadata (esbuild is
 * transpile-only, no type info) — NestJS's DI container needs that metadata
 * to resolve constructor params. Without it, providers built via the real
 * `NestFactory` (not manually `new`'d, as most unit tests here do) fail with
 * `UndefinedDependencyException` / "Cannot read properties of undefined" for
 * every injected param. This is NestJS's own documented fix for Vitest.
 * Found via spec-sprint-4 D7 when the first Nest-container integration test
 * tried to boot the real app. Unit tests here never hit this because they
 * `new` services directly instead of going through Nest's container.
 */
export default defineConfig({
  plugins: [swc.vite()],
  test: {
    exclude: ['**/node_modules/**', '**/dist/**', '**/*.integration.spec.ts'],
  },
});
