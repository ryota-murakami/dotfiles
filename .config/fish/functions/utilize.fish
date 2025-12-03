# utilize - Copy files/directories to monorepo package roots
#
# USAGE:
#   utilize <file/dir> <package>
#   utilize <file1,file2,file3> <package>  # Multiple files/dirs (comma-separated)
#
# ARGUMENTS:
#   file/dir  - Path to the file or directory to copy (comma-separated for multiple)
#   package   - Target package name (browser|react|node|types|universal)
#
# PACKAGE MAPPING:
#   browser   → packages/browser
#   react     → packages/next-react
#   node      → packages/node
#   types     → packages/types
#   universal → packages/universal
#
# REQUIREMENTS:
#   - ~/utils directory must exist with packages/ subdirectory
#   - Target package directory must exist
#
# EXAMPLES:
#   utilize ./utils.ts browser                    # Copy utils.ts to packages/browser/
#   utilize ./components react                    # Copy components/ dir to packages/next-react/
#   utilize ./types.d.ts types                    # Copy types.d.ts to packages/types/
#   utilize ./utils.ts,./types.d.ts browser       # Copy multiple files to packages/browser/
#   utilize ./src/utils.ts,./src/components react # Copy multiple files/dirs to packages/next-react/
#
function utilize --description 'Copy file or directory to a package root directory'
    # Show help if no arguments
    if test (count $argv) -eq 0
        echo "Usage: utilize <file/dir> <browser|react|node|types|universal>"
        echo ""
        echo "Copy a file or directory to the root of a specified package."
        echo ""
        echo "Arguments:"
        echo "  file/dir    Path to file or directory to copy (comma-separated for multiple)"
        echo "  package     Target package (browser|react|node|types|universal)"
        echo ""
        echo "Examples:"
        echo "  utilize ./myfile.ts browser"
        echo "  utilize ./mydir react"
        echo "  utilize ./file1.ts,./file2.ts browser  # Copy multiple files"
        return 0
    end

    # Check if second argument is provided
    if test (count $argv) -lt 2
        echo "Error: Package name not specified" >&2
        echo "Usage: utilize <file/dir> <browser|react|node|types|universal>" >&2
        return 1
    end

    set source_paths_str $argv[1]
    set package_name $argv[2]

    # Split comma-separated paths
    set source_paths (string split ',' $source_paths_str)

    # Set workspace root to ~/utils
    set workspace_root "$HOME/utils"
    if not test -d $workspace_root
        echo "Error: Workspace root '$workspace_root' does not exist." >&2
        return 1
    end

    # Map package name to directory
    switch $package_name
        case browser
            set target_dir "$workspace_root/packages/browser"
        case react
            set target_dir "$workspace_root/packages/next-react"
        case node
            set target_dir "$workspace_root/packages/node"
        case types
            set target_dir "$workspace_root/packages/types"
        case universal
            set target_dir "$workspace_root/packages/universal"
        case '*'
            echo "Error: Invalid package name '$package_name'" >&2
            echo "Valid packages: browser, react, node, types, universal" >&2
            return 1
    end

    # Check if target directory exists
    if not test -d $target_dir
        echo "Error: Target directory '$target_dir' does not exist" >&2
        return 1
    end

    # Process each source path
    set has_error 0
    for source_path in $source_paths
        # Trim whitespace from path
        set source_path (string trim $source_path)

        # Check if source exists
        if not test -e $source_path
            echo "Error: Source path '$source_path' does not exist" >&2
            set has_error 1
            continue
        end

        # Get the basename of source for the copy
        set source_basename (basename $source_path)

        # Copy the file or directory
        if test -d $source_path
            cp -r $source_path $target_dir/
        else
            cp $source_path $target_dir/
        end

        if test $status -eq 0
            echo "✅ Successfully copied '$source_basename' to $target_dir/"
        else
            echo "Error: Failed to copy '$source_path' to '$target_dir'" >&2
            set has_error 1
        end
    end

    if test $has_error -eq 1
        return 1
    end
end

