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

/** The zoom the Handout's − and + buttons step through, 80% to 160% in steps of 10%. */
export const ZOOM_MIN = 0.8
export const ZOOM_MAX = 1.6
export const ZOOM_STEP = 0.1

/** The panel's narrowest width a drag can reach, before the window's own limit (viewport − margin). */
export const PANEL_MIN_WIDTH_PX = 480

/** Room kept between the panel and the window's sides: 16px on each. */
export const PANEL_VIEWPORT_MARGIN_PX = 32

/** How long a copy button says what happened before it reads コピー again. */
export const COPY_FEEDBACK_MS = 1_200

/** How much larger than its viewBox a diagram shows at natural size, as in the Explainer. */
export const DIAGRAM_NATURAL_SCALE = 1.25
