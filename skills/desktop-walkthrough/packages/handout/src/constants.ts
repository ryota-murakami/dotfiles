/** Version of input.json, the host's messages and its result; each side refuses one it does not know. */
export const HANDOUT_PROTOCOL_VERSION = 1

/** Longest wait for one page's render report before the run stops with HANDOUT_RENDERER (eng D3). */
export const PAGE_RENDER_LIMIT_MS = 30_000

/** Longest whole export, from the host's start to its result, before HANDOUT_RENDERER (eng D3). */
export const RUN_LIMIT_MS = 600_000

/** How far into a file the Handout marker is looked for: the builder writes it in the head, near the top. */
export const MARKER_SCAN_BYTES = 4096

/**
 * How much wider or taller than its box a diagram label may lay out before it counts as overflowing
 * (DX D9): sub-pixel rounding differs between the render and the measurement.
 */
export const OVERFLOW_TOLERANCE_PX = 2

/** How long the verify probe waits for the Handout's controller to take over the reopened file (eng D10). */
export const VERIFY_READY_LIMIT_MS = 3_000

/** How many characters of a label or an error a message quotes; the rest is cut with `…`. */
export const MESSAGE_EXCERPT_CHARS = 60

/** How often the verify probe looks for the controller's ready mark. */
export const VERIFY_POLL_MS = 50

/** How long the verify probe waits for the controller to answer `#2`. */
export const VERIFY_HASHCHANGE_LIMIT_MS = 1_000
