/**
 * The prompts sent from this page, walked with Up and Down in the Input box.
 *
 * Why it exists: the terminal's input recalls earlier prompts with the arrow keys; the Mirror keeps
 * the ones sent from its own box in memory (they are lost when the page reloads) so that the same
 * keys work. Held by {@link InputBox}.
 */
export class PromptHistory {
  private entries: string[] = []
  /** Which entry is shown; `entries.length` means none: the user's own text is in the box. */
  private cursor = 0
  /** What was in the box when the walk began, brought back by walking past the newest entry. */
  private draft = ''

  /**
   * Remember a sent prompt and stop walking. A prompt equal to the newest one is not kept twice.
   *
   * @param text - The prompt as sent.
   */
  push(text: string): void {
    if (text !== '' && this.entries[this.entries.length - 1] !== text) this.entries.push(text)
    this.reset()
  }

  /** Whether a recalled prompt is in the box. */
  get isWalking(): boolean {
    return this.cursor < this.entries.length
  }

  /** Stop walking: the user typed, so the box holds their own text again. */
  reset(): void {
    this.cursor = this.entries.length
  }

  /**
   * Step to the previous prompt.
   *
   * @param current - What the box holds now; kept as the draft when the walk begins.
   * @returns The prompt to show, or undefined when there is no older one.
   */
  older(current: string): string | undefined {
    if (this.cursor === 0) return undefined
    if (this.cursor === this.entries.length) this.draft = current
    this.cursor -= 1
    return this.entries[this.cursor]
  }

  /**
   * Step to the next prompt, or back to the draft after the newest.
   *
   * @returns The text to show, or undefined when the box already holds the user's own text.
   */
  newer(): string | undefined {
    if (this.cursor >= this.entries.length) return undefined
    this.cursor += 1
    return this.cursor === this.entries.length ? this.draft : this.entries[this.cursor]
  }
}
