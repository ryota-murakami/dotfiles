# =============================================================================
# flush_dns_cache - Clear macOS DNS Cache
# =============================================================================
#
# DESCRIPTION:
#   Clears the DNS cache on macOS to resolve domain name lookup issues.
#   Useful after changing DNS servers, modifying /etc/hosts, or when
#   experiencing DNS-related connectivity problems.
#
# USAGE:
#   flush_dns_cache
#
# REQUIRES:
#   sudo password (runs with elevated privileges)
#
# WHAT IT DOES:
#   1. dscacheutil -flushcache : Clears the DNS cache
#   2. killall -HUP mDNSResponder : Restarts the DNS resolver daemon
#
# WHEN TO USE:
#   - After editing /etc/hosts file
#   - After changing DNS server settings
#   - When websites aren't resolving correctly
#   - After VPN connection issues
#   - When old DNS records seem cached
#
# EXAMPLE:
#   $ flush_dns_cache
#   Password: ****
#   # DNS cache cleared - try accessing the website again
#
#   # Common workflow after editing hosts:
#   $ sudo nano /etc/hosts
#   # Add: 127.0.0.1 myapp.local
#   $ flush_dns_cache
#   $ ping myapp.local  # Now resolves correctly
#
# =============================================================================
function flush_dns_cache
    sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
end
