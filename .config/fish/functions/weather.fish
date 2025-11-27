# =============================================================================
# weather - Display Weather Forecast
# =============================================================================
#
# DESCRIPTION:
#   Fetches and displays weather forecast from wttr.in service.
#   Shows current conditions, temperature, and 3-day forecast.
#
# USAGE:
#   weather              # Show weather for Tokyo (default)
#   weather <city>       # Show weather for specified city
#
# ARGUMENTS:
#   city - Optional city name (default: tokyo)
#          Can use city names, airport codes, or coordinates
#
# DEPENDENCIES:
#   - curl (pre-installed on macOS)
#   - Internet connection
#
# EXAMPLE:
#   $ weather
#   Weather report: Tokyo
#   [ASCII art weather display]
#
#   $ weather "new york"
#   Weather report: New York
#   [ASCII art weather display]
#
#   $ weather SFO  # San Francisco airport
#
# =============================================================================
function weather
    if [ -z $argv ]
        set locate tokyo
    else
        set locate $argv
    end

    curl wttr.in/$locate
end
