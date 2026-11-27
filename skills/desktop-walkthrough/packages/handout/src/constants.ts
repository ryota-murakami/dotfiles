/** Version of input.json, the host's messages and its result; each side refuses one it does not know. */
export const HANDOUT_PROTOCOL_VERSION = 1

/** Longest wait for one page's render report before the run stops with HANDOUT_RENDERER (eng D3). */
export const PAGE_RENDER_LIMIT_MS = 30_000

/** Longest whole export, from the host's start to its result, before HANDOUT_RENDERER (eng D3). */
export const RUN_LIMIT_MS = 600_000

/** How far into a file the Handout marker is looked for: the builder writes it in the head, near the top. */
export const MARKER_SCAN_BYTES = 4096
