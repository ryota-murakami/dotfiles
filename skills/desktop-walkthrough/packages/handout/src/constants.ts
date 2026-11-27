/** Version of input.json, the host's messages and its result; each side refuses one it does not know. */
export const HANDOUT_PROTOCOL_VERSION = 1

/** Longest wait for one page's render report before the run stops with HANDOUT_RENDERER (eng D3). */
export const PAGE_RENDER_LIMIT_MS = 30_000

/** Longest whole export, from the host's start to its result, before HANDOUT_RENDERER (eng D3). */
export const RUN_LIMIT_MS = 600_000

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

/**
 * What the bytes of each image type a Handout embeds start with: the format's signature, at its offset
 * (WebP and AVIF carry theirs inside a RIFF or ftyp box). A file named like an image whose bytes match
 * none of these is not embedded, whatever its name says.
 */
export const IMAGE_SIGNATURES = [
  { mime: 'image/png', parts: [{ offset: 0, bytes: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a] }] },
  { mime: 'image/jpeg', parts: [{ offset: 0, bytes: [0xff, 0xd8, 0xff] }] },
  { mime: 'image/gif', parts: [{ offset: 0, bytes: [0x47, 0x49, 0x46, 0x38] }] },
  {
    mime: 'image/webp',
    parts: [
      { offset: 0, bytes: [0x52, 0x49, 0x46, 0x46] },
      { offset: 8, bytes: [0x57, 0x45, 0x42, 0x50] },
    ],
  },
  { mime: 'image/avif', parts: [{ offset: 4, bytes: [0x66, 0x74, 0x79, 0x70, 0x61, 0x76, 0x69, 0x66] }] },
  { mime: 'image/avif', parts: [{ offset: 4, bytes: [0x66, 0x74, 0x79, 0x70, 0x61, 0x76, 0x69, 0x73] }] },
] as const

/** How far into a file an SVG's `<svg` element is looked for, after its XML declaration, comments and doctype. */
export const SVG_SNIFF_BYTES = 4_096

/**
 * The largest picture a Handout embeds (20 MB), whether read from a file or written into a page as
 * data: more fills memory once base64 adds its third. The same limit as `imageLimitBytes` in
 * handout/main.swift, which refuses a larger file before reading it.
 */
export const IMAGE_LIMIT_BYTES = 20 * 1024 * 1024

/**
 * The most picture bytes one Handout embeds in all (100 MB), a picture shown twice counted twice:
 * the finished file, and each copy the export makes of it, stay in memory until it is published.
 */
export const IMAGE_TOTAL_LIMIT_BYTES = 100 * 1024 * 1024

/** How long the verify probe waits for one embedded picture to decode before it counts as broken. */
export const VERIFY_IMAGE_DECODE_LIMIT_MS = 5_000
