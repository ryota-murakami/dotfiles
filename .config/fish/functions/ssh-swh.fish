# =============================================================================
# ssh-swh - Switch SSH Keys
# =============================================================================
#
# DESCRIPTION:
#   Manages SSH agent identity by clearing all keys and optionally
#   adding a new one. Useful when working with multiple Git accounts
#   or servers that require different SSH keys.
#
# USAGE:
#   ssh-swh                  # Clear all SSH keys from agent
#   ssh-swh <key_path>       # Clear all keys and add specified key
#
# ARGUMENTS:
#   key_path - Optional path to SSH key to add (e.g., ~/.ssh/id_work)
#
# WHAT IT DOES:
#   1. ssh-add -D : Removes all identities from the agent
#   2. If key provided: ssh-add <key> : Adds the specified key
#
# COMMON USE CASES:
#   - Switching between personal and work GitHub accounts
#   - Connecting to different servers with specific keys
#   - Troubleshooting SSH authentication issues
#
# EXAMPLE:
#   # Clear all keys:
#   $ ssh-swh
#   All identities removed.
#
#   # Switch to work key:
#   $ ssh-swh ~/.ssh/id_work
#   All identities removed.
#   Identity added: /Users/me/.ssh/id_work
#
#   # Verify:
#   $ ssh-add -l
#   4096 SHA256:xxx... /Users/me/.ssh/id_work (RSA)
#
# =============================================================================
function ssh-swh
    ssh-add -D
    if [ -z $argv ]
        return
    else
        ssh-add $argv
    end
end
