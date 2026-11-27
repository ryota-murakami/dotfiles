# HUD golden

The regression contract of the HUD Explainer (eng review D5 of `dw handout`): a page without audience markers renders in the HUD exactly as it did before page.html gained its Handout mode and explain_build its marker filter.

| Path | Holds |
| --- | --- |
| `record/pages/` | a synthetic Record: a table, a link, a quote, a list, code with and without a language, a flowchart, a sequence diagram, a `<details>` block, `<kbd>` |
| `baseline/pages/NNN.html` | those pages built by `explain_build` and `explainer/page.html` as they were on 2026-11-28 (commit `1da3e912`), before the Handout work changed either |

`scripts/check` builds the same pages with today's `explain_build` for the HUD, renders both sets through the Handout renderer in HUD mode, and requires, page by page, the same `#content`, the same number of reading-mark blocks and the same render report.

Rebuild the baseline only when a change to the HUD's rendering is intended: `scripts/hud-golden capture`, then look at the difference in the built pages before committing it. The content is made up: never copy a real Record here.
