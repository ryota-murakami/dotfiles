/**
 * The builder page's script: exposes `window.dwHandout.build`, which the renderer host calls with
 * input.json and whose result it publishes. The controller's source and hash are inlined at build
 * time (vite.config.ts), so the builder needs nothing from disk but what the host reads for it.
 */
import { handoutInputSchema } from '../contract'
import handoutCss from '../controller/handout.css?raw'
import { buildHandout } from './build'
import { webkitHost } from './host'

window.dwHandout = {
  async build(input) {
    return buildHandout(handoutInputSchema.parse(input), {
      host: webkitHost,
      handoutCss,
      controller: { source: HANDOUT_CONTROLLER_SOURCE, sha256: HANDOUT_CONTROLLER_SHA256 },
    })
  },
}
