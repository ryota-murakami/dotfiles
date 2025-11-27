# =============================================================================
# get_pid_by_name - Find Process ID by Name
# =============================================================================
#
# DESCRIPTION:
#   Searches for a process by name and returns its PID.
#   Returns only the first match if multiple processes exist.
#
# USAGE:
#   get_pid_by_name <process_name>
#
# ARGUMENTS:
#   process_name - Name (or partial name) to search for
#
# OUTPUT:
#   Single PID number (first match)
#
# DEPENDENCIES:
#   - ps, grep, awk (pre-installed on macOS)
#
# EXAMPLE:
#   $ get_pid_by_name node
#   12345
#
#   # Use with kill:
#   $ kill (get_pid_by_name node)
#
#   # Or store in variable:
#   $ set pid (get_pid_by_name postgres)
#   $ echo "Postgres PID: $pid"
#
# RELATED:
#   - pid_by_port.fish (find by port number)
#
# =============================================================================
function get_pid_by_name
    ps -e | grep -m1 $argv | awk '{print $1}'
end
