# Phase 2: Tooling

Goal: one commit (`chore: add ESLint, Prettier, Fallow and coverage tooling`) after which `pnpm lint`, `pnpm format:check`, `pnpm typecheck`, `pnpm test:coverage`, `pnpm check:docs` pass. Includes the whole-repo Prettier/ESLint reformat, so later commits carry no formatting noise.

## Files

`scaffold.mjs --group tooling` writes: `eslint.config.mjs`, `.prettierrc.json` (`singleQuote`, `semi: false`), `.prettierignore`, `.fallowrc.json`, `vitest.config.mts`, `scripts/check-docs-links.mjs`.

Existing configs are kept. Merge by hand, or `--skip <path>` when the repo already has an equivalent (e.g. `vitest.config.ts`, a Jest setup → then wire coverage to emit `lcov` + `json`).

## Dependencies

```sh
pnpm add -D -E eslint eslint-config-ts-prefixer prettier fallow @vitest/coverage-v8 \
  "typescript-compiler@npm:typescript@7"
pnpm add -D "typescript@~6.0.3"
```

- `@vitest/coverage-v8` must match the installed `vitest` version.
- **TypeScript 7 + 6 side by side**: `eslint-config-ts-prefixer` (typescript-eslint) needs the TS JS API, which TS 7 does not ship. Keep `typescript` on `~6.0.x` for ESLint; run the TS 7 compiler through the `typescript-compiler` alias by path.

## pnpm-workspace.yaml

```yaml
allowBuilds:
  unrs-resolver: true # eslint-config-ts-prefixer's import resolver
minimumReleaseAge: 1440
```

`minimumReleaseAge: 1440` blocks versions younger than one day. If an install fails on a fresh release, pick the previous version; do not drop the setting.

## package.json scripts

```json
"build": "node ./node_modules/typescript-compiler/bin/tsc -p tsconfig.build.json",
"typecheck": "node ./node_modules/typescript-compiler/bin/tsc -p .",
"lint": "eslint . --concurrency=auto --max-warnings=0",
"lint:fix": "eslint . --fix --concurrency=auto --max-warnings=0",
"format": "prettier --write .",
"format:check": "prettier --check .",
"check:docs": "node scripts/check-docs-links.mjs",
"test": "vitest run",
"test:coverage": "vitest run --coverage",
"health": "fallow health --fail-on-issues",
"dupes": "fallow dupes --fail-on-issues",
"dead-code": "fallow dead-code --fail-on-issues",
"check": "pnpm format:check && pnpm check:docs && pnpm lint && pnpm typecheck && pnpm test:coverage && pnpm health && pnpm dupes && pnpm dead-code && pnpm build",
"verify": "pnpm check && pnpm audit --prod"
```

Keep the repo's existing `build` if it is not plain `tsc` (tsdown, vite, etc.). Every `tsc` call goes through `typescript-compiler`. Multi-project typecheck → a `scripts/typecheck.mjs` looping `tsconfig`s (see happy-dom-extended).

## tsconfig

- `tsconfig.json`: `noEmit: true`, strict, `allowJs: true`, `checkJs: false`; `include` source, tests, `*.mts`, `*.mjs`, `scripts/**/*.mjs` so typed ESLint parses configs and scripts.
- `tsconfig.build.json`: extends it, `noEmit: false`, `rootDir: src`, `outDir`, excludes tests.
- TS 7 dropped `node10` resolution: use `node16`/`nodenext` (or `bundler`).

## .fallowrc.json

- `entry`: real entry points (package `exports`, `main`, CLI bins, `src/extension.ts`), test globs, config files.
- `health.coverage`: `coverage/coverage-final.json` → `pnpm test:coverage` must run before `pnpm health`.
- `framework[repository-tools]`: `scripts/*.mjs` as support entry points.
- `ignoreDependencies: ["typescript-compiler"]` because package.json scripts run it by path. (If a script imports `typescript-compiler/package.json`, it is used and needs no ignore.)
- `usedClassMembers`: members a framework calls through an interface. `implements` must match the clause **exactly as written in source**, fully qualified:

```json
"usedClassMembers": [
  { "implements": "vscode.Disposable", "members": ["dispose"] },
  { "implements": "vscode.TreeDataProvider", "members": ["onDidChangeTreeData", "getTreeItem", "getChildren", "getParent"] }
]
```

`"implements": "Disposable"` silently matches nothing and dead-code keeps failing. Never add ignores without evidence.

## .gitignore

Add `coverage` and `.fallow`.

## After install

```sh
pnpm format && pnpm lint:fix
pnpm lint && pnpm typecheck && pnpm test:coverage
```

Fix remaining lint errors by hand (ts-prefixer is strict: `import type`, explicit returns, etc.). Behavior must not change in this commit; run existing tests to prove it.

## VS Code extension extras

- `build`/`watch` use `tsconfig.build.json` (tests excluded from `out/`).
- `"package": "pnpm exec vsce package --no-dependencies"`; append `&& pnpm package` to `check` instead of `pnpm build` (vsce runs `vscode:prepublish`).
- Add every new config/doc file to `.vscodeignore` (`.fallowrc.json`, `.coderabbit.yaml`, `codecov.yml`, `eslint.config.mjs`, `.prettier*`, `vitest.config.mts`, `.node-version`, `scripts/**`, `coverage/**`, `.fallow/**`, SECURITY/CONTRIBUTING/CODE_OF_CONDUCT/TESTING/ARCHITECTURE/TODOS.md). `pnpm package` then lists what ships.
- `.prettierignore`: add `*.vsix` and any vendored file copied verbatim from upstream.
- ESLint ignores: add `.vscode-test/**`.
