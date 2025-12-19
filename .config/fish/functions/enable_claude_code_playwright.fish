# =============================================================================
# enable_claude_code_playwright - Add Playwright MCP Server to Claude Code
# =============================================================================
#
# DESCRIPTION:
#   Adds the Playwright MCP server configuration to ~/.claude.json's
#   mcpServers field. Prevents duplicate entries and validates JSON syntax.
#
# USAGE:
#   enable_claude_code_playwright
#
# WHAT IT DOES:
#   1. Checks if ~/.claude.json exists
#   2. Checks if playwright is already configured in mcpServers
#   3. Adds playwright configuration if not present
#   4. Validates JSON syntax after modification
#
# PLAYWRIGHT CONFIG:
#   {
#     "command": "npx",
#     "args": ["-y", "@playwright/mcp@latest"]
#   }
#
# EXAMPLE:
#   $ enable_claude_code_playwright
#   ✓ Added playwright MCP server to ~/.claude.json
#
#   # If already exists:
#   $ enable_claude_code_playwright
#   ℹ Playwright is already configured in ~/.claude.json
#
# RELATED:
#   - disable_claude_code_playwright.fish (remove playwright)
#
# =============================================================================
function enable_claude_code_playwright
    set -l claude_json ~/.claude.json

    # Check if ~/.claude.json exists
    if not test -f $claude_json
        echo "✗ Error: $claude_json does not exist"
        return 1
    end

    # Check if jq is available
    if not command -q jq
        echo "✗ Error: jq is required but not installed"
        return 1
    end

    # Validate current JSON syntax
    if not jq empty $claude_json 2>/dev/null
        echo "✗ Error: $claude_json contains invalid JSON"
        return 1
    end

    # Check if playwright already exists in mcpServers
    if jq -e '.mcpServers.playwright' $claude_json >/dev/null 2>&1
        echo "ℹ Playwright is already configured in ~/.claude.json"
        return 0
    end

    # Add playwright to mcpServers
    set -l tmp_file (mktemp)
    jq '.mcpServers.playwright = {"command": "npx", "args": ["-y", "@playwright/mcp@latest"]}' $claude_json > $tmp_file

    # Validate the new JSON
    if not jq empty $tmp_file 2>/dev/null
        echo "✗ Error: JSON syntax error after modification"
        rm -f $tmp_file
        return 1
    end

    # Apply the changes
    mv $tmp_file $claude_json
    echo "✓ Added playwright MCP server to ~/.claude.json"
    return 0
end
