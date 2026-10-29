# =============================================================================
# sfw - Toggle Socket Firewall package manager wrapping
# =============================================================================
#
# DESCRIPTION:
#   Wraps the real `sfw` binary. Intercepts `on`, `off`, `toggle`, `status`
#   subcommands to enable/disable the package manager aliases defined in
#   conf.d/21-sfw.fish (synchronized with ~/.aliases-sfw for bash/zsh).
#   All other arguments are passed through to the real sfw binary.
#
# USAGE:
#   sfw on       Enable sfw wrapping (npm, pnpm, pip, cargo, ... route via sfw)
#   sfw off      Disable sfw wrapping (package managers run directly)
#   sfw toggle   Flip the current state
#   sfw status   Show current state
#   sfw <args>   Forward to the real sfw binary (e.g. `sfw npm install`)
#
# STATE:
#   ~/.sfw-disabled - flag file; present = OFF, absent = ON (fail-safe ON).
#   New shells pick up the state via the guard in 21-sfw.fish / .aliases-sfw.
#   The sfw binary remains directly usable even when wrapping is OFF.
#
# EXAMPLE:
#   $ sfw off
#   ✓ sfw wrapping disabled (npm, pnpm, pip, ... run directly)
#   $ sfw on
#   ✓ sfw wrapping enabled
#
# =============================================================================
function sfw --description "Socket Firewall: on/off/toggle/status, or proxy to real sfw"
    set -l flag ~/.sfw-disabled

    switch "$argv[1]"
        case on
            # Clear flag first so the guard in 21-sfw.fish re-creates aliases
            rm -f $flag
            source ~/.config/fish/conf.d/21-sfw.fish
            echo "✓ sfw wrapping enabled (npm, pnpm, pip, ... route via sfw)"
        case off
            touch $flag
            functions -e npm npx pnpm pnpx yarn bun pip pip3 uv cargo 2>/dev/null
            echo "✓ sfw wrapping disabled (npm, pnpm, pip, ... run directly)"
        case toggle
            if test -f $flag
                sfw on
            else
                sfw off
            end
        case status
            if test -f $flag
                echo "sfw wrapping: OFF"
            else
                echo "sfw wrapping: ON"
            end
        case '*'
            command sfw $argv
    end
end
