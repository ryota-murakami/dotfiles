function utilize --description 'Copy file or directory to a package root directory'
    # Show help if no arguments
    if test (count $argv) -eq 0
        echo "Usage: utilize <file/dir> <browser|react|node|types|universal>"
        echo ""
        echo "Copy a file or directory to the root of a specified package."
        echo ""
        echo "Arguments:"
        echo "  file/dir    Path to file or directory to copy"
        echo "  package     Target package (browser|react|node|types|universal)"
        echo ""
        echo "Examples:"
        echo "  utilize ./myfile.ts browser"
        echo "  utilize ./mydir react"
        return 0
    end

    # Check if second argument is provided
    if test (count $argv) -lt 2
        echo "Error: Package name not specified" >&2
        echo "Usage: utilize <file/dir> <browser|react|node|types|universal>" >&2
        return 1
    end

    set source_path $argv[1]
    set package_name $argv[2]

    # Check if source exists
    if not test -e $source_path
        echo "Error: Source path '$source_path' does not exist" >&2
        return 1
    end

    # Get workspace root (assuming we're somewhere in the workspace)
    set workspace_root (git rev-parse --show-toplevel 2>/dev/null)
    if test $status -ne 0
        echo "Error: Not in a git repository. Cannot find workspace root." >&2
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
        return 1
    end
end

