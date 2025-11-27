# =============================================================================
# remove_chrome_cache - Clear Google Chrome Cache
# =============================================================================
#
# DESCRIPTION:
#   Removes all Chrome cache directories to free disk space and fix
#   browser issues. Chrome can accumulate gigabytes of cache over time.
#
# USAGE:
#   remove_chrome_cache
#
# DIRECTORIES REMOVED:
#   - Cache (general cache)
#   - Code Cache (JavaScript bytecode)
#   - Media Cache (video/audio)
#   - extensions_crx_cache (extension packages)
#   - Shared Dictionary (compression dictionaries)
#   - IndexedDB (local databases)
#   - WebStorage (localStorage/sessionStorage)
#   - CacheStorage (Service Worker cache)
#   - Service Worker (PWA data)
#   - ShaderCache (GPU shaders)
#   - GrShaderCache (Skia graphics shaders)
#   - GPUCache (GPU-related cache)
#
# WHEN TO USE:
#   - Chrome using too much disk space
#   - Website display issues
#   - Browser slowdown
#   - After clearing cookies/history
#
# NOTE:
#   Close Chrome before running for best results.
#   Chrome will recreate cache directories on next launch.
#
# EXAMPLE:
#   $ du -sh ~/Library/Application\ Support/Google/Chrome/Default/Cache
#   2.1G    Cache
#
#   $ remove_chrome_cache
#
#   # After Chrome restart, cache is fresh
#
# =============================================================================
function remove_chrome_cache
    rm -rf ~/Library/Application\ Support/Google/Chrome/Default/Cache
    rm -rf ~/Library/Application\ Support/Google/Chrome/Default/Code\ Cache
    rm -rf ~/Library/Application\ Support/Google/Chrome/Default/Media\ Cache
    rm -rf ~/Library/Application\ Support/Google/Chrome/Default/extensions_crx_cache
    rm -rf ~/Library/Application\ Support/Google/Chrome/Default/Shared\ Dictionary
    rm -rf ~/Library/Application\ Support/Google/Chrome/Default/IndexedDB
    rm -rf ~/Library/Application\ Support/Google/Chrome/Default/WebStorage
    rm -rf ~/Library/Application\ Support/Google/Chrome/Default/CacheStorage
    rm -rf ~/Library/Application\ Support/Google/Chrome/Default/Service\ Worker
    rm -rf ~/Library/Application\ Support/Google/Chrome/ShaderCache
    rm -rf ~/Library/Application\ Support/Google/Chrome/GrShaderCache
    rm -rf ~/Library/Application\ Support/Google/Chrome/GPUCache
    rm -rf ~/Library/Application\ Support/Google/Chrome/GPUCache
end
