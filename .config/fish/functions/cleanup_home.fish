# =============================================================================
# cleanup_home - Delete leftover dirs and files directly under ~
# =============================================================================
#
# DESCRIPTION:
#   Removes a fixed list of scratch dirs, generated images, and abandoned
#   tool config dirs from $HOME. Targets are children of $HOME only.
#   Missing entries are skipped. Re-running is safe.
#
# USAGE:
#   cleanup_home
#
# WHEN TO USE:
#   After trying a tool or agent that left a dot-dir or scratch folder
#   in $HOME and that tool is no longer in use.
#
# NOTE:
#   ~/go is included. Fish still prepends ~/go/bin in config.fish; that
#   PATH entry is left as-is.
#
# =============================================================================
function cleanup_home --description "Delete leftover scratch dirs and abandoned tool dirs directly under ~"
    # Fixed allowlist. Names are a single path segment under $HOME.
    set -l targets \
        src\
        gnupg \
        go \
        qa \
        qa-scratch \
        autoki-media \
        autoki-x-avatar-400.png \
        autoki-x-header-1500x500.png \
        .tabnine \
        .terramind \
        .nx \
        .next-devtools-mcp \
        .neovate \
        .mux \
        .moxby \
        .minimax \
        .tart \
        .trae \
        .tinycloud \
        .aider-desk \
        .adal \
        .bob \
        .storybook \
        .yarn \
        .zcode \
        .omp \
        .ona \
        .openhands \
        .pi \
        .pochi \
        .portless \
        .grok \
        .qoder \
        .qoder-cn \
        .qwen \
        .reasonix \
        .redhat \
        .roo \
        .rovodev \
        .sage \
        .snowflake \
        .vibe

    set -l removed 0
    set -l absent 0
    set -l failed 0

    # One exact child of $HOME per name. No globs, no nested search.
    for name in $targets
        if string match -q -r '[/]' -- $name
            or string match -q -- '..' $name
            echo "cleanup_home: refusing unsafe name: $name" >&2
            return 1
        end

        set -l path "$HOME/$name"

        # -L keeps a dangling symlink in scope; -e alone would miss it.
        if test -e $path -o -L $path
            command rm -rf -- $path
            if test -e $path -o -L $path
                echo "failed  $path" >&2
                set failed (math $failed + 1)
            else
                echo "removed $path"
                set removed (math $removed + 1)
            end
        else
            echo "absent  $path"
            set absent (math $absent + 1)
        end
    end

    echo "cleanup_home: removed $removed, absent $absent, failed $failed"
    if test $failed -gt 0
        return 1
    end
end
