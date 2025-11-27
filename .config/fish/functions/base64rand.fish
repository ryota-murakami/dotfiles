# =============================================================================
# base64rand - Generate Random Base64 String
# =============================================================================
#
# DESCRIPTION:
#   Generates a cryptographically secure random base64-encoded string.
#   Useful for creating API keys, tokens, or secrets.
#
# USAGE:
#   base64rand
#
# OUTPUT:
#   44-character base64 string (256 bits of entropy)
#
# DEPENDENCIES:
#   - openssl (pre-installed on macOS)
#
# EXAMPLE:
#   $ base64rand
#   K7mN3pQ9xY2vW8bC4fH6jL0sA5tR1uE3iO7yU9wX2zA=
#
# RELATED:
#   - genpasswd.fish (human-readable passwords)
#
# =============================================================================
function base64rand
    openssl rand -base64 32
end
