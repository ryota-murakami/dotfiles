/**
 * What the row components of the Mirror are built from: the theme's colour names, the glyph row with
 * its marker cell, the `⎿` result gutter, dim text, the column count and the markdown-free text
 * arithmetic. The tool rows, the tool-group rows and the live area import from here.
 */
export { Columns, useColumns } from './columns'
export { Dim, GLYPH, Gutter, RowLayout, type DimTone, type RowLayoutProps } from './RowLayout'
export { THEME_COLOR_NAMES, themeColor, type ThemeColorName } from './theme'
export { isAtBottom, useStickToBottom } from './useStickToBottom'
export { cellWidth, displayWidth, hardWrapLines, wrapLines } from './width'
