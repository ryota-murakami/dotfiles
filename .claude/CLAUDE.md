# Dev Server Launch Rules

When Claude Code autonomously starts development servers outside of custom commands, it must use tmux sessions to avoid blocking the main process.

### Target Servers
- Next.js (`npm run dev`, `yarn dev`, `pnpm dev`)
- Vite (`npm run dev`, `yarn dev`, `pnpm dev`)
- Storybook (`npm run storybook`, `yarn storybook`, `pnpm storybook`)

### Execution Steps
1. **Create tmux session**: Create a background session with a dedicated session name
2. **Send command**: Send the dev server command to the session
3. **Background execution**: The server runs in the background and the main terminal is not blocked

### Templates

#### Next.js
```fish
tmux new -s next-dev-server -d
tmux send-keys -t next-dev-server "cd (pwd) && pnpm dev" Enter
```

#### Vite
```fish
tmux new -s vite-dev-server -d
tmux send-keys -t vite-dev-server "cd (pwd) && pnpm dev" Enter
```

#### Storybook
```fish
tmux new -s storybook-dev-server -d
tmux send-keys -t storybook-dev-server "cd (pwd) && pnpm storybook" Enter
```

### Session Management
- Check sessions: `tmux list-sessions`
- Attach to session: `tmux attach -t <session-name>`
- Kill session: `tmux kill-session -t <session-name>`

### Notes
- This restriction does not apply when executing as custom commands
- If port 3000 is in use, check if an existing instance is already running
- Use Fish shell


# Web Application Development Rules

### MANDATORY Browser Verification and Testing

**CRITICAL REQUIREMENT**: After ANY changes, modifications, or new feature implementations, you MUST:

1. **Verify functionality in browser using Playwright MCP** - NO EXCEPTIONS
   - Launch the application in browser via Playwright MCP
   - Thoroughly test all affected functionality and user interactions
   - Ensure proper display and operation across all modified components

2. **Generate comprehensive Playwright e2e tests** - REQUIRED FOR ALL CHANGES
   - Base test scenarios on the exact verification actions performed in Playwright MCP
   - Create complete test coverage for all modified functionality
   - Tests MUST replicate the verification process step-by-step

### MANDATORY Visual Design Compliance

**ABSOLUTE REQUIREMENT**: For UI visual design changes, you MUST achieve 100% accuracy:

1. **Iterative visual matching process** - NO COMPROMISES ALLOWED
   - Make incremental changes toward the target design
   - Take screenshots using Playwright MCP after each change
   - Compare screenshots against provided reference images
   - Identify and document ANY discrepancies, no matter how minor

2. **Continue iteration until PERFECT match**
   - Repeat the change → screenshot → compare → adjust cycle
   - DO NOT STOP until visual output is 100% identical to reference
   - Every pixel, color, spacing, and layout element MUST match exactly

### NON-NEGOTIABLE Standards

- **ZERO TOLERANCE** for untested changes
- **ZERO TOLERANCE** for visual inconsistencies
- **MANDATORY** Playwright MCP verification for every modification
- **MANDATORY** screenshot comparison for all UI changes

# General Rules

## CRITICAL Task Completion Requirements

**ABSOLUTE MANDATORY**: Before considering ANY task complete, you MUST verify that ALL of the following checks PASS without exception:

### Required Validation Steps - NO FAILURES ALLOWED

1. **Lint Check** - MUST PASS
   - All code MUST conform to project linting standards
   - ZERO linting errors or warnings permitted

2. **Type Check** - MUST PASS
   - All TypeScript types MUST be correct and valid
   - ZERO type errors allowed

3. **Unit/Integration Tests** - MUST PASS
   - All existing tests MUST continue to pass
   - New functionality MUST have corresponding tests that pass

4. **Build Process** - MUST PASS
   - Application MUST build successfully without errors
   - ZERO build failures tolerated

5. **E2E Tests (Playwright)** - MUST PASS
   - All end-to-end tests MUST execute successfully
   - ZERO E2E test failures permitted

### NON-NEGOTIABLE Completion Standard

- **TASK IS NOT COMPLETE** until ALL checks pass
- **NO EXCEPTIONS** - failing any check means task is incomplete
- **MANDATORY VERIFICATION** - run all checks before declaring task finished
- **ZERO TOLERANCE** for incomplete or failing validation

