# =============================================================================
# kill-port - Kill Processes on a Specific Port
# =============================================================================
#
# DESCRIPTION:
#   Forcefully terminates all processes listening on a specified port.
#   Essential for development when a port is stuck (e.g., crashed server,
#   orphaned process from previous session).
#
# USAGE:
#   kill-port <port>
#
# ARGUMENTS:
#   port - Port number to free (e.g., 3000, 8080)
#
# HOW IT WORKS:
#   1. Uses lsof to find process IDs using the port
#   2. Pipes PIDs to kill -9 for forceful termination
#   3. Reports success
#
# DEPENDENCIES:
#   - lsof (pre-installed on macOS)
#   - xargs (pre-installed on macOS)
#
# EXAMPLE:
#   $ kill-port 3000
#   Killed processes on port 3000
#
#   # Typical use case:
#   $ npm start
#   Error: Port 3000 is already in use
#   $ kill-port 3000
#   Killed processes on port 3000
#   $ npm start  # Works now!
#
# RELATED:
#   - port_usage.fish (list all ports in use)
#   - pid_by_port.fish (see what's using a port)
#
# =============================================================================
function kill-port
    if test -z "$argv[1]"
        echo "Usage: kill-port <port>"
        echo "Example: kill-port 3000"
        return 1
    end
    lsof -ti :$argv[1] | xargs kill -9
    echo "Killed processes on port $argv[1]"
end
