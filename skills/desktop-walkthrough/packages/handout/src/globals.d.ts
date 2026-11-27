import type { BuildOutcome } from './contract'

declare global {
  /** The controller's built source, inlined by vite.config.ts from dist/controller.js. */
  const HANDOUT_CONTROLLER_SOURCE: string
  /** Base64 SHA-256 of {@link HANDOUT_CONTROLLER_SOURCE}, for the Handout's CSP. */
  const HANDOUT_CONTROLLER_SHA256: string

  interface Window {
    /** The renderer host's channel; present only in the host's builder view. */
    webkit?: {
      messageHandlers: Record<string, { postMessage(message: unknown): Promise<unknown> } | undefined>
    }
    /** The builder's entry, called by the host with input.json. */
    dwHandout?: { build(input: unknown): Promise<BuildOutcome> }
  }
}
