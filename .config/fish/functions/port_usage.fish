# =============================================================================
# port_usage - List All TCP Ports in Use
# =============================================================================
#
# DESCRIPTION:
#   Shows all TCP ports currently in LISTEN state on the system.
#   Displays the process name, PID, and port number for each listener.
#   Requires sudo for complete information.
#
# USAGE:
#   port_usage
#
# OUTPUT COLUMNS:
#   - COMMAND: Process name
#   - PID: Process ID
#   - USER: Owner
#   - FD: File descriptor
#   - TYPE: Connection type
#   - DEVICE: Network device
#   - SIZE/OFF: Size/Offset
#   - NODE: Protocol
#   - NAME: Address:Port
#
# DEPENDENCIES:
#   - lsof (pre-installed on macOS)
#   - sudo (for full access)
#
# EXAMPLE:
#   $ port_usage
#   Password: ****
#   COMMAND   PID USER   ... NAME
#   node    12345 me     ... *:3000 (LISTEN)
#   postgres 6789 me     ... *:5432 (LISTEN)
#   nginx    1234 root   ... *:80 (LISTEN)
#
# RELATED:
#   - kill-port.fish (kill process on specific port)
#   - pid_by_port.fish (check specific port)
#
# =============================================================================
function port_usage
    sudo lsof -PiTCP -sTCP:LISTEN
end
