# =============================================================================
# genpasswd - Generate Secure Password
# =============================================================================
#
# DESCRIPTION:
#   Generates a secure, random password using pwgen and automatically
#   copies it to the clipboard. Perfect for creating account passwords.
#
# USAGE:
#   genpasswd <length>
#
# ARGUMENTS:
#   length - Number of characters for the password (e.g., 16, 32)
#
# FLAGS USED:
#   -B : Avoid ambiguous characters (0/O, 1/l/I)
#   -s : Generate secure (harder to memorize) passwords
#   -y : Include at least one special character
#
# DEPENDENCIES:
#   - pwgen (brew install pwgen)
#   - pbcopy/pbpaste (pre-installed on macOS)
#
# EXAMPLE:
#   $ genpasswd 20
#   #K9$mN2@pQ7&xY4!wB3z
#   Has been copied to clipboard
#
# RELATED:
#   - base64rand.fish (for API keys/tokens)
#
# =============================================================================
function genpasswd
    pwgen -Bsy $argv 1 |pbcopy |pbpaste; echo "Has been copied to clipboard"
end
