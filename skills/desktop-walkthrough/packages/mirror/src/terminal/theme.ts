/**
 * The names of the theme's colours, as custom properties of `theme.css`.
 *
 * Why it exists: rows colour themselves through CSS, but the tool rows and the spinner line pick
 * a colour by data (a tool's status, a spinner mode), so they need the names as values. A spec checks
 * that every name here has a value in `theme.css`.
 */
export const THEME_COLOR_NAMES = [
  'text',
  'inactive',
  'inactiveShimmer',
  'subtle',
  'promptBorder',
  'claude',
  'claudeShimmer',
  'success',
  'error',
  'warning',
  'warningShimmer',
  'permission',
  'suggestion',
  'remember',
  'permissionShimmer',
  'claudeBlue_FOR_SYSTEM_SPINNER',
  'autoAccept',
  'merged',
  'skill',
  'planMode',
  'ide',
  'bashBorder',
  'background',
  'professionalBlue',
  'chromeYellow',
  'fastMode',
  'fastModeShimmer',
  'briefLabelYou',
  'briefLabelClaude',
  'userMessageBackground',
  'userMessageBackgroundHover',
  'bashMessageBackgroundColor',
  'memoryBackgroundColor',
  'composerSidebarBackground',
  'selectionBg',
  'diffAdded',
  'diffRemoved',
  'diffAddedDimmed',
  'diffRemovedDimmed',
  'diffAddedWord',
  'diffRemovedWord',
  'rainbow_red',
  'rainbow_orange',
  'rainbow_yellow',
  'rainbow_green',
  'rainbow_blue',
  'rainbow_indigo',
  'rainbow_violet',
] as const

/** A colour of the dark theme, by the name Claude Code gives it. */
export type ThemeColorName = (typeof THEME_COLOR_NAMES)[number]

/**
 * The CSS value of a theme colour, for an inline `style` that picks a colour by data.
 *
 * @param name - The theme's own name for the colour (`success`, `error`, …).
 * @returns A `var(--name)` expression.
 */
export function themeColor(name: ThemeColorName): string {
  return `var(--${name})`
}
