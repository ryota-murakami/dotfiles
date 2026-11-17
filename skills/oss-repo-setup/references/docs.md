# Phase 5: Documentation

Goal: one commit (`docs: add community health files, architecture and testing guides, README badges`).

## Files (`scaffold.mjs --group docs`)

Auto-filled: `{{OWNER}}`, `{{REPO}}`, `{{PROJECT_NAME}}`, `{{NODE_VERSION}}`, `{{MAINTAINER}}`. The script prints the rest under "Fill manually":

| File                 | Fill with                                                                                                                                                                        |
| -------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `SECURITY.md`        | `{{DISTRIBUTION}}`: where users get it (npm, Marketplace + Open VSX, releases) with links. `{{RUNTIME_MODEL}}`: permissions, network access, untrusted input, what it never does |
| `CONTRIBUTING.md`    | `{{PROJECT_PURPOSE}}` (completes "Thank you for helping …"). Also: add project-specific steps/tooling, a Releases section if `docs/releasing.md` exists                          |
| `TESTING.md`         | `{{TEST_LAYERS}}`: table Layer / Location / What it proves. `{{MANUAL_VERIFICATION}}`: numbered checks unit tests cannot prove (or "None; the suite covers …")                   |
| `ARCHITECTURE.md`    | Overview sentence, numbered data flow, boundaries (no network, no runtime deps, …). Refer to symbols as `{@link Symbol}`                                                         |
| `CODE_OF_CONDUCT.md` | Nothing                                                                                                                                                                          |
| `TODOS.md`           | Keep the ruleset item; add real follow-ups found during setup (What / Why / Context / Effort / Priority / Depends on)                                                            |

Write every claim from the code, not from memory. Done when this prints nothing:

```sh
rg -n '\{\{[A-Z_]+\}\}' --glob '!node_modules' .
```

## README

Add a "Contribute and release" section: links to CONTRIBUTING/TESTING/ARCHITECTURE, `pnpm install --frozen-lockfile && pnpm check`, one line per workflow, Socket token note, SECURITY + Code of Conduct links, `## License` → `[MIT](LICENSE)`.

### Badges (top of README, before the H1)

```md
[![Test](https://github.com/OWNER/REPO/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/OWNER/REPO/actions/workflows/test.yml)
<!-- same shape for build, typecheck, lint, format, fallow, security, socket -->

[![Codecov](https://codecov.io/gh/OWNER/REPO/branch/main/graph/badge.svg)](https://codecov.io/gh/OWNER/REPO)
[![OpenSSF Scorecard](https://img.shields.io/ossf-scorecard/github.com/OWNER/REPO?label=openssf%20scorecard)](https://scorecard.dev/viewer/?uri=github.com/OWNER/REPO)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
```

npm package: add `https://img.shields.io/npm/v/<pkg>` → `https://www.npmjs.com/package/<pkg>`.

### VS Code extension README

The Marketplace renders the README and only allows badge images from its approved hosts (list: code.visualstudio.com/api/references/extension-manifest#approved-badges). Relevant: `github.com` (workflow badges only), `codecov.io`, `img.shields.io`. Not allowed: `api.scorecard.dev` → use the `img.shields.io/ossf-scorecard` form above. `vsce package` rejects disallowed SVG badges, so `pnpm package` catches mistakes.

Marketplace dynamic badges (version/installs/rating via `vsmarketplacebadges.dev` or shields' visual-studio-marketplace) are discontinued → static badge only:

```md
[![VS Code Marketplace](https://img.shields.io/badge/VS%20Code%20Marketplace-Install-007ACC?logo=visualstudiocode&logoColor=white)](https://marketplace.visualstudio.com/items?itemName=PUBLISHER.EXT)
[![Open VSX](https://img.shields.io/open-vsx/v/PUBLISHER/EXT?label=Open%20VSX)](https://open-vsx.org/extension/PUBLISHER/EXT)
```

Open VSX's dynamic badge still works.

## Link check

`pnpm check:docs` validates relative links and heading anchors in **git-tracked** Markdown only (`git ls-files '*.md'`). New docs are invisible until staged:

```sh
git add *.md docs && pnpm check:docs
```

It rejects headings containing HTML (it cannot slug them) and anchors whose case differs from GitHub's generated slug.
