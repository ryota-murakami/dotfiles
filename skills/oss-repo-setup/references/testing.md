# Phase 3: Test reinforcement

Goal: one commit (`test: ...`) after which `pnpm test:coverage && pnpm health && pnpm dupes && pnpm dead-code` all pass. CI's Fallow job runs the same, so CI must not land before this.

## Loop

```sh
pnpm test:coverage   # writes coverage/coverage-final.json
pnpm health          # reads it; flags complex functions with low coverage
```

Repeat until green:

1. Read each flagged function. Decide: untested behavior, or genuinely over-complex?
2. Untested → add tests for the observable behavior (success and failure paths).
3. Over-complex even with tests → split into small named functions (behavior-preserving; existing tests prove it). The reference repo split its docs-link checker this way.
4. Do not raise thresholds or add `health.ignore` entries to get green.

`dupes`: extract the shared logic, or restructure. Test files are already ignored.
`dead-code`: delete truly unused exports/files; for framework-called members use `usedClassMembers` (see tooling.md).

## Test style (user rules)

- `test`, not `it`. Names state observable behavior / what regresses.
- Arrange / Act / Assert comments. DAMP over DRY. Hard-coded expected values.
- Assert user-visible effects (messages, files, return payloads), not private fields.

## Host APIs you cannot import (VS Code, Electron, etc.)

Write an in-memory fake of the module and mock it:

```ts
vi.mock('vscode', async () => import('./support/fakeVscode.js'))
```

- The fake records effects (shown messages, opened editors, registered commands, context keys, breakpoints, clipboard) so tests assert on them.
- Implement only the API surface the code actually uses.
- Fallow cannot follow `vi.mock` → first lines of the fake:

```ts
// Source files reach these exports through `vi.mock('vscode')`, which static analysis cannot follow.
// fallow-ignore-file unused-export unused-type unused-class-member
```

- Cover the activation/controller wiring (`extension.test.ts`): each command's resulting messages and editor effects.
- Things a fake cannot prove (rendering, real keybinding dispatch) go to TESTING.md's manual verification list and a TODOS.md item.

## Coverage config

`vitest.config.mts` template: `include` source tests only, coverage `include: src/**/*.ts`, exclude tests, reporters `json` (Fallow), `lcov` (Codecov), `text-summary`.
