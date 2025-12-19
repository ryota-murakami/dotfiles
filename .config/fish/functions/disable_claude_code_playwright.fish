# =============================================================================
# disable_claude_code_playwright - Remove Playwright MCP Server from Claude Code
# =============================================================================
#
# DESCRIPTION:
#   Removes the Playwright MCP server configuration from ~/.claude.json's
#   mcpServers field. Validates JSON syntax after modification.
#
# USAGE:
#   disable_claude_code_playwright
#
# WHAT IT DOES:
#   1. Checks if ~/.claude.json exists
#   2. Checks if playwright exists in mcpServers
#   3. Removes playwright configuration if present
#   4. Validates JSON syntax after modification
#
# EXAMPLE:
#   $ disable_claude_code_playwright
#   ✓ Removed playwright MCP server from ~/.claude.json
#
#   # If not found:
#   $ disable_claude_code_playwright
#   ℹ Playwright is not configured in ~/.claude.json
#
# RELATED:
#   - enable_claude_code_playwright.fish (add playwright)
#
# =============================================================================
function disable_claude_code_playwright
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

    # Check if playwright exists in mcpServers
    if not jq -e '.mcpServers.playwright' $claude_json >/dev/null 2>&1
        echo "ℹ Playwright is not configured in ~/.claude.json"
        return 0
    end

    # Remove playwright from mcpServers
    set -l tmp_file (mktemp)
    jq 'del(.mcpServers.playwright)' $claude_json > $tmp_file

    # Validate the new JSON
    if not jq empty $tmp_file 2>/dev/null
        echo "✗ Error: JSON syntax error after modification"
        rm -f $tmp_file
        return 1
    end

    # Apply the changes
    mv $tmp_file $claude_json
    echo "✓ Removed playwright MCP server from ~/.claude.json"
    return 0
end
