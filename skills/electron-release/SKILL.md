---
name: electron-release
description: Electron release ship
---

# Electron Release Guide

## Codex Compatibility
When running this skill in Codex, translate Claude Code-only primitives before acting: `AskUserQuestion` -> chat/request_user_input, `TodoWrite` -> `update_plan`, `Task`/`TaskCreate`/`TeamCreate`/`SendMessage` -> `spawn_agent`/`send_input`/`wait_agent` when available and allowed, and `EnterPlanMode`/`ExitPlanMode` -> a concise chat plan plus explicit approval.
Resolve `Read`/`Write`/`Edit`/`Bash`/`WebSearch`/`WebFetch` to Codex file/shell/web tools, and map `~/.claude/...` paths to `~/.agents/...` or `~/.codex/...` unless the task explicitly targets Claude Code.

## Cursor Compatibility
When running this skill in Cursor Agent, translate Claude Code-only primitives before acting: `AskUserQuestion` -> `AskQuestion`; `TodoWrite` -> Cursor `TodoWrite` or an equivalent checklist; `Task`/`TaskCreate`/`TeamCreate`/`SendMessage`/multi-agent flows -> Cursor `Task` (subagents), parallel Tasks, or `run_in_background` when allowed (`TeamCreate`/`SendMessage` may have no exact match); `EnterPlanMode`/`ExitPlanMode` -> Plan mode (`SwitchMode` / `CreatePlan`) plus explicit user approval.
Resolve `Read`/`Write`/`Edit`/`StrReplace`/`Bash`/web/search/MCP via Cursor Composer or Agent equivalents. MCP names written as `mcp__server__tool` typically map to `call_mcp_tool` with configured server identifiers. Map `~/.claude/...` to `~/.cursor/skills/`, `.cursor/skills/`, and `.cursor/rules/` unless the task explicitly targets Claude Code.


Complete release workflow for Electron applications with auto-update support.

## Auto-Update Verification Scope

Standard releases stop after verifying the published assets and `latest-mac.yml` metadata. Do not install or launch an older app, trigger its updater, download an update, restart into it, or exercise ShipIt as part of this skill. Perform end-to-end auto-update QA only when the user explicitly requests it or asks to investigate a reported update failure.

## Supported Configurations

| Stack | Platform | Build Type | Status |
|-------|----------|------------|--------|
| Vite + electron-builder | macOS | Local | ✅ Documented |
| Other configurations | - | - | 📝 To be added |

## Quick Start (macOS + Vite + electron-builder)

```bash
# 1. Build with notarization
APPLE_KEYCHAIN_PROFILE=your-profile pnpm build:mac

# 2. Rename ZIPs (GitHub converts spaces to dots)
cp "dist/App Name-X.Y.Z-arm64-mac.zip" "dist/App-Name-X.Y.Z-arm64-mac.zip"
cp "dist/App Name-X.Y.Z-mac.zip" "dist/App-Name-X.Y.Z-mac.zip"

# 3. Create release with ALL files
gh release create vX.Y.Z \
  dist/latest-mac.yml \
  "dist/App-Name-X.Y.Z-arm64-mac.zip" \
  "dist/App-Name-X.Y.Z-mac.zip" \
  dist/app-name-X.Y.Z-arm64.dmg \
  dist/app-name-X.Y.Z-x64.dmg \
  --title "vX.Y.Z" --notes "Release notes..."
```

## Complete Workflow

### Phase 1: Pre-Release

1. **Update version** in `package.json`
2. **Commit version bump**:
   ```bash
   git add package.json
   git commit -m "chore(release): bump version to X.Y.Z"
   git push origin main
   ```

### Phase 2: Build

3. **Build with notarization**:
   ```bash
   APPLE_KEYCHAIN_PROFILE=your-profile pnpm build:mac
   ```

   | Env Var | Purpose |
   |---------|---------|
   | `APPLE_KEYCHAIN_PROFILE` | Keychain profile for notarization |
   | Alternative: `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, `APPLE_TEAM_ID` | Direct credentials |

4. **Verify build output**:
   ```bash
   ls -la dist/*.dmg dist/*.zip dist/*.yml
   ```

   Expected files:
   - `latest-mac.yml` - Auto-update metadata
   - `App Name-X.Y.Z-arm64-mac.zip` - ARM64 update payload
   - `App Name-X.Y.Z-mac.zip` - x64 update payload
   - `app-name-X.Y.Z-arm64.dmg` - ARM64 installer
   - `app-name-X.Y.Z-x64.dmg` - x64 installer

### Phase 3: Prepare Release Assets

5. **Rename ZIP files** (critical for auto-update):
   ```bash
   # GitHub converts spaces to dots, but latest-mac.yml expects hyphens
   cp "dist/App Name-X.Y.Z-arm64-mac.zip" "dist/App-Name-X.Y.Z-arm64-mac.zip"
   cp "dist/App Name-X.Y.Z-mac.zip" "dist/App-Name-X.Y.Z-mac.zip"
   ```

6. **Verify `latest-mac.yml` URLs match renamed files**:
   ```bash
   cat dist/latest-mac.yml
   # Check that 'url:' entries match your renamed ZIP filenames
   ```

### Phase 4: GitHub Release

7. **Create release with all required files**:
   ```bash
   gh release create vX.Y.Z \
     dist/latest-mac.yml \
     "dist/App-Name-X.Y.Z-arm64-mac.zip" \
     "dist/App-Name-X.Y.Z-mac.zip" \
     dist/app-name-X.Y.Z-arm64.dmg \
     dist/app-name-X.Y.Z-x64.dmg \
     --title "vX.Y.Z" \
     --notes "$(cat <<'EOF'
   ## What's Changed
   - Feature 1
   - Bug fix 2
   EOF
   )"
   ```

8. **Verify release assets**:
   ```bash
   gh release view vX.Y.Z --json assets --jq '.assets[].name'
   ```

## Required Files for Auto-Update

| File | Purpose | Missing = |
|------|---------|-----------|
| `latest-mac.yml` | Version + SHA512 hashes | "No updates available" |
| `*-arm64-mac.zip` | ARM64 update payload | Download fails on M1/M2/M3 |
| `*-mac.zip` | x64 update payload | Download fails on Intel |
| `*.dmg` | Manual download | No manual install option |

## Common Mistakes

| Mistake | Symptom | Fix |
|---------|---------|-----|
| DMG only, no ZIP | Auto-update silently fails | Upload all ZIP files |
| Missing `latest-mac.yml` | "No updates available" | Upload `latest-mac.yml` |
| Wrong ZIP filename | Download error | Rename to match `latest-mac.yml` URLs |
| No notarization env var | Gatekeeper blocks app | Set `APPLE_KEYCHAIN_PROFILE` |
| Spaces in filename | 404 on download | Rename: spaces → hyphens |

## Troubleshooting

### "Download error" on auto-update
```bash
# Check if filenames match
cat dist/latest-mac.yml | grep url:
gh release view vX.Y.Z --json assets --jq '.assets[].name'
# URLs in yml must exactly match asset names
```

### "No updates available"
```bash
# Verify latest-mac.yml is uploaded
gh release view vX.Y.Z --json assets --jq '.assets[].name' | grep yml
```

### Gatekeeper blocks app
```bash
# Rebuild with notarization
APPLE_KEYCHAIN_PROFILE=your-profile pnpm build:mac
# Check build log for "notarization successful"
```

## electron-builder.yml Reference

```yaml
mac:
  target:
    - target: dmg
      arch: [arm64, x64]
    - target: zip
      arch: [arm64, x64]
  notarize: true
  hardenedRuntime: true

publish:
  provider: github
  owner: your-org
  repo: your-repo
```

## Success Criteria

- [ ] Build completes with "notarization successful"
- [ ] All 5 files uploaded to GitHub Release
- [ ] ZIP filenames match `latest-mac.yml` URLs exactly
