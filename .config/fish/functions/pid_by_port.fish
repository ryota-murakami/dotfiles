# =============================================================================
# pid_by_port - Find Process Using a Specific Port
# =============================================================================
#
# DESCRIPTION:
#   Shows detailed information about processes using a specific port.
#   More detailed than kill-port, showing the full process info before
#   you decide to kill it.
#
# USAGE:
#   pid_by_port <port>
#
# ARGUMENTS:
#   port - Port number to investigate
#
# DEPENDENCIES:
#   - lsof (pre-installed on macOS)
#   - sudo (for full access)
#
# EXAMPLE:
#   $ pid_by_port 3000
#   Password: ****
#   COMMAND  PID   USER  FD  TYPE DEVICE SIZE/OFF NODE NAME
#   node    12345  me    23u IPv4 0x...  0t0  TCP *:3000 (LISTEN)
#
#   # Now you know it's node process 12345
#   # Can kill with: kill 12345 or kill-port 3000
#
# RELATED:
#   - kill-port.fish (to terminate the process)
#   - port_usage.fish (list all ports)
#   - get_pid_by_name.fish (find by process name)
#
# =============================================================================
function pid_by_port
    sudo lsof -i :$argv
end
