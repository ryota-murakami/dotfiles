# =============================================================================
# print_argv - Debug Function Arguments
# =============================================================================
#
# DESCRIPTION:
#   Debug helper that displays how arguments are passed to fish functions.
#   Useful when developing new functions or debugging argument parsing.
#
# USAGE:
#   print_argv <arg1> <arg2> ...
#
# OUTPUT:
#   Shows $argv (all arguments) and individual indexed arguments.
#
# FISH ARGUMENT HANDLING:
#   - $argv : List of all arguments
#   - $argv[1] : First argument
#   - $argv[2] : Second argument
#   - (count $argv) : Number of arguments
#
# EXAMPLE:
#   $ print_argv hello world
#   $argv: hello world
#   $argv[1]: hello
#   $argv[2]: world
#
#   $ print_argv "hello world" foo
#   $argv: hello world foo
#   $argv[1]: hello world
#   $argv[2]: foo
#
# =============================================================================
function print_argv
    echo "\$argv: $argv"
    echo "\$argv[1]: $argv[1]"
    echo "\$argv[2]: $argv[2]"
end
