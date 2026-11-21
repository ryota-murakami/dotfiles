/**
 * The way the HUD reaches the Input box's keyboard focus.
 *
 * Why it exists: `window.dwMirror.focusInput()` has to focus a textarea that a component owns; the
 * component registers it here when it mounts. Called by {@link InputBox} (register) and `host.ts`
 * (focus).
 */
let element: HTMLTextAreaElement | null = null

/**
 * Tell the door which textarea is the Input box.
 *
 * @param next - The textarea, or null when it unmounts.
 */
export function registerInput(next: HTMLTextAreaElement | null): void {
  element = next
}

/** Put the keyboard in the Input box. Does nothing before the box is drawn. */
export function focusInput(): void {
  element?.focus()
}
