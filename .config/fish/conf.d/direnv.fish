# Override Homebrew's vendor_conf.d/direnv.fish.
# That file pins a Cellar version path like:
#   /opt/homebrew/Cellar/direnv/2.38.1/bin/direnv hook fish | source
# After `brew upgrade direnv`, already-running shells break because the
# old binary path is gone. Hook via PATH so the stable symlink is used.
if command -q direnv
    direnv hook fish | source
end
