function claude --description 'Claude Code wrapper: load only local MCP servers (skip claude.ai connectors)'
    # `command` prefix bypasses this function and runs the real binary on PATH.
    # Without it, the function recurses into itself.
    command claude --strict-mcp-config --mcp-config ~/.claude/mcp-local.json $argv
end
