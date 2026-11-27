# TODOS

Work that was decided and deferred, with what it needs. Done items are deleted with the change that does them.

## HANDOUT_OVERFLOW does not see SVG text labels

- **What:** the overflow check (`packages/handout/src/builder/probes.ts` `measurePage`, `judge.ts`) compares a label's laid-out content with its own box. For a flowchart label (HTML inside `<foreignObject>`) that box is the one mermaid sized, so a label that grew is caught. For an SVG `<text>` label (sequence diagram actors and messages) the label and its box are the same rectangle, so an actor name pushed wider than its actor shape passes.
- **Why deferred:** found by the Codex structured review of the dw-handout branch (2026-11-28, P1). It is an extension of the judgement, not a fix: it needs the shape each text belongs to (the actor's `rect`, a note's box) and a rule for each diagram kind, which deserves its own design pass.
- **How to start:** in `measurePage`, for each `text` inside `.diagram svg`, find the nearest sibling or ancestor shape (`rect`, `polygon`, `path` of the same group) and report both boxes; in `judge.ts`, an overflow is the text's box wider than the shape's by more than `OVERFLOW_TOLERANCE_PX`. Capture a sequence-diagram fixture with a long actor name from the real page.html (as `fixtures/sequence.svg` was) and add a renderer case to `scripts/handout-check`.
