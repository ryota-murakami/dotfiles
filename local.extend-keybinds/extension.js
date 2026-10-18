const vscode = require("vscode")

/**
 * Registers extra keybind commands that the editor does not provide.
 *
 * Cursor, VS Code, and Devin Desktop have no built-in Scroll to Center.
 * This extension is the shared place for those commands so they work in
 * every workspace, not only DayKey.
 *
 * @param {vscode.ExtensionContext} context - The VS Code extension context.
 * @returns {void}
 */
function activate(context) {
  const scrollToCenterCommand = vscode.commands.registerCommand(
    "extend-keybinds.scrollToCenter",
    () => {
      scrollCurrentLineToCenter()
    },
  )

  context.subscriptions.push(scrollToCenterCommand)
}

/**
 * Disposes the extension.
 *
 * @returns {void}
 */
function deactivate() {}

/**
 * Scrolls the current cursor line to the center of the editor viewport.
 *
 * Triggered by `⌃X L`. Keeps the cursor in place and only moves the viewport,
 * matching WebStorm's Scroll to Center.
 *
 * @returns {void}
 *
 * @example
 * ```js
 * await vscode.commands.executeCommand("extend-keybinds.scrollToCenter")
 * ```
 */
function scrollCurrentLineToCenter() {
  const editor = vscode.window.activeTextEditor

  // No editor focused — nothing to center.
  if (!editor) {
    return
  }

  const position = editor.selection.active
  const revealRange = new vscode.Range(position, position)
  editor.revealRange(revealRange, vscode.TextEditorRevealType.InCenter)
}

module.exports = {
  activate,
  deactivate,
}
