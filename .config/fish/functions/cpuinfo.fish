# =============================================================================
# cpuinfo - Display CPU/Hardware Information
# =============================================================================
#
# DESCRIPTION:
#   Shows detailed hardware information including CPU model, memory,
#   serial number, and other system specifications using macOS
#   System Profiler.
#
# USAGE:
#   cpuinfo
#
# OUTPUT INCLUDES:
#   - Model Name & Identifier
#   - Chip (Apple Silicon) or Processor Name
#   - Total Number of Cores
#   - Memory
#   - Serial Number
#   - Hardware UUID
#
# DEPENDENCIES:
#   - system_profiler (pre-installed on macOS)
#
# EXAMPLE:
#   $ cpuinfo
#   Hardware Overview:
#     Model Name: MacBook Pro
#     Chip: Apple M1 Pro
#     Total Number of Cores: 10
#     Memory: 16 GB
#     ...
#
# =============================================================================
function cpuinfo
    system_profiler SPHardwareDataType
end
