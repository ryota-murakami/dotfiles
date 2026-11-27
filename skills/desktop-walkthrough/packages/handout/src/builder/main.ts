/**
 * The builder page's script: exposes `window.dwHandout.build`, which the renderer host calls with
 * input.json and whose result it publishes. The controller's source and hash are inlined at build
 * time (vite.config.ts), so the builder needs nothing from disk but what the host reads for it.
 */
import { maskSecrets } from '../../../../hooks/secrets'
import { handoutInputSchema } from '../contract'
import handoutCss from '../controller/handout.css?raw'
import { buildHandout } from './build'
import { webkitHost } from './host'

window.dwHandout = {
  async build(input) {
    try {
      return await buildHandout(handoutInputSchema.parse(input), {
        host: webkitHost,
        handoutCss,
        controller: { source: HANDOUT_CONTROLLER_SOURCE, sha256: HANDOUT_CONTROLLER_SHA256 },
      })
    } catch (error) {
      // The host prints an exception's text to dw and its log (HANDOUT_RENDERER): text from a page in
      // it (a probe's error, a host's reply) is masked like every message the export prints. No cause:
      // it would carry the unmasked text along
      // oxlint-disable-next-line preserve-caught-error
      throw new Error(maskSecrets(error instanceof Error ? error.message : String(error)))
    }
  },
}
