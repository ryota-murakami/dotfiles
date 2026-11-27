import type { HostReply, HostRequest, RenderReport } from '../contract'
import { hostReplySchema } from '../contract'

/** How the builder reaches the renderer host: one request, one reply (contract {@link HostRequest}). */
export type HostPort = (request: HostRequest) => Promise<HostReply>

/**
 * The host as the builder view sees it: the `host` message channel, whose `postMessage` resolves
 * with the host's reply. Every reply is parsed against the contract before the builder trusts it.
 *
 * @param request - What the builder asks for.
 * @returns The parsed reply.
 * @throws When the channel is missing (the builder runs outside the host) or the reply breaks the contract.
 *
 * @example
 * await webkitHost({ type: 'read', path: '/r/pages/shot.png' }) // { type: 'file', base64: 'iVBORw0…' }
 */
export const webkitHost: HostPort = async (request) => {
  const channel = window.webkit?.messageHandlers.host
  if (!channel) throw new Error('the renderer host channel is missing: the builder runs only inside the host')
  return hostReplySchema.parse(await channel.postMessage(request))
}

/**
 * Ask the host to render a page and run a probe in it.
 *
 * @param host - The host.
 * @param page - The page number; the host loads `pages/NNN.html` of the explain folder.
 * @param probe - Probe source from {@link probeBody}.
 * @returns The page's render report and the probe's raw result.
 * @throws When the host answers with another kind of reply (a broken host, not a broken page).
 *
 * @example
 * await renderPage(host, 2, probeBody(measurePage, { contentId: 'content' })) // { report: { type: 'rendered', page: 2, … }, probe: { html: '…', diagrams: [] } }
 */
export async function renderPage(
  host: HostPort,
  page: number,
  probe: string,
): Promise<{ report: RenderReport; probe: unknown }> {
  const reply = await host({ type: 'render', page, probe })
  if (reply.type !== 'rendered') throw new Error(`the host answered a render request with "${reply.type}"`)
  if (reply.report.page !== page)
    throw new Error(`the host returned the report of page ${reply.report.page} for page ${page}`)
  return { report: reply.report, probe: reply.probe }
}

/**
 * Ask the host for a local file's bytes.
 *
 * @param host - The host.
 * @param path - Absolute path.
 * @returns
 * - `{ ok: true, base64 }`: the file's bytes
 * - `{ ok: false, message }`: missing or unreadable, as the host words it
 * @throws When the host answers with another kind of reply.
 *
 * @example
 * await readFile(host, '/r/pages/missing.png') // { ok: false, message: 'no such file' }
 */
export async function readFile(
  host: HostPort,
  path: string,
): Promise<{ ok: true; base64: string } | { ok: false; message: string }> {
  const reply = await host({ type: 'read', path })
  if (reply.type === 'file') return { ok: true, base64: reply.base64 }
  if (reply.type === 'unreadable') return { ok: false, message: reply.message }
  throw new Error(`the host answered a read request with "${reply.type}"`)
}

/**
 * Ask the host to open the finished Handout under its own CSP and run a probe in it (eng D10).
 *
 * @param host - The host.
 * @param html - The whole Handout.
 * @param probe - Probe source from {@link probeBody}.
 * @returns The probe's raw result.
 * @throws When the host answers with another kind of reply.
 *
 * @example
 * await verifyInHost(host, '<!doctype html>…', probeBody(checkHandout, args)) // { ready: true, pages: 3, … }
 */
export async function verifyInHost(host: HostPort, html: string, probe: string): Promise<unknown> {
  const reply = await host({ type: 'verify', html, probe })
  if (reply.type !== 'verified') throw new Error(`the host answered a verify request with "${reply.type}"`)
  return reply.probe
}
