// @ts-check
import eslint from '@eslint/js';
import globals from 'globals';
import tseslint from 'typescript-eslint';

/**
 * ESLint 9 flat config (NestJS). Type-aware rules qua projectService.
 * Trước Sprint 3 repo chưa có eslint cài — thêm ở đây để `npm run lint`
 * chạy được (quality gate CLAUDE.md).
 */
export default tseslint.config(
  {
    ignores: ['dist/**', 'node_modules/**', 'prisma/**', 'eslint.config.mjs'],
  },
  eslint.configs.recommended,
  ...tseslint.configs.recommended,
  {
    languageOptions: {
      globals: { ...globals.node },
      parserOptions: {
        // tsconfig.json exclude *.spec.ts (không emit test); dùng tsconfig
        // riêng cho eslint để type-aware lint phủ cả test file.
        project: './tsconfig.eslint.json',
        tsconfigRootDir: import.meta.dirname,
      },
    },
    rules: {
      // Decorator metadata + Nest patterns: nới vài rule quá gắt cho DI.
      '@typescript-eslint/no-explicit-any': 'warn',
      '@typescript-eslint/no-unused-vars': [
        'error',
        { argsIgnorePattern: '^_', varsIgnorePattern: '^_' },
      ],
    },
  },
  {
    // Test files: cho phép cast/mocks tự do.
    files: ['**/*.spec.ts'],
    rules: {
      '@typescript-eslint/no-unsafe-assignment': 'off',
      '@typescript-eslint/no-unsafe-member-access': 'off',
      '@typescript-eslint/no-unsafe-argument': 'off',
      '@typescript-eslint/unbound-method': 'off',
    },
  },
);
