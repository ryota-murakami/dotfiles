/**
 * A duration the way the terminal words it: whole seconds under a minute (`7s`), then `1m 6s`,
 * `1h 2m 3s` and `1d 2h 3m`.
 *
 * Why it exists: the turn-duration line and, later, the spinner line and tool rows show times in this
 * format. Called by {@link TurnDurationRow}.
 *
 * @param durationMs - Milliseconds.
 * @returns The wording; `0s` for zero or less.
 */
export function formatDuration(durationMs: number): string {
  const totalSeconds = Math.max(0, Math.floor(durationMs / 1000))
  const days = Math.floor(totalSeconds / 86_400)
  const hours = Math.floor((totalSeconds % 86_400) / 3600)
  const minutes = Math.floor((totalSeconds % 3600) / 60)
  const seconds = totalSeconds % 60
  if (days > 0) return `${days}d ${hours}h ${minutes}m`
  if (hours > 0) return `${hours}h ${minutes}m ${seconds}s`
  if (minutes > 0) return `${minutes}m ${seconds}s`
  return `${seconds}s`
}

/**
 * A moment as the clock time the turn-duration line shows (`3:04 PM`).
 *
 * @param epochMs - Milliseconds since 1970.
 * @param timeZone - An IANA zone; the reader's own when omitted.
 * @returns Hours and minutes in the reader's locale.
 */
export function formatClockTime(epochMs: number, timeZone?: string): string {
  return new Date(epochMs).toLocaleTimeString(undefined, {
    hour: 'numeric',
    minute: '2-digit',
    ...(timeZone ? { timeZone } : {}),
  })
}
