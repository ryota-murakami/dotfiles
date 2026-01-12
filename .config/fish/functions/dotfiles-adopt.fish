# =============================================================================
# dotfiles-adopt - Move File/Directory to Dotfiles and Create Symlink
# =============================================================================
#
# DESCRIPTION:
#   Moves a file or directory into your dotfiles repository and creates a
#   symlink at the original location pointing to the moved file.
#   This is useful for "adopting" config files into your dotfiles management.
#
# USAGE:
#   dotfiles-adopt <path> [destination_name]
#
# ARGUMENTS:
#   path             - Path to the file or directory to adopt
#   destination_name - Optional. Name to use in dotfiles (defaults to original name)
#
# HOW IT WORKS:
#   1. Validates the source exists and dotfiles directory exists
#   2. Moves the file/directory to ~/dotfiles/
#   3. Creates a symlink at the original location → ~/dotfiles/<name>
#
# EXAMPLES:
#   # Adopt .vimrc into dotfiles
#   $ dotfiles-adopt ~/.vimrc
#   ✓ Moved ~/.vimrc → ~/dotfiles/.vimrc
#   ✓ Created symlink ~/.vimrc → ~/dotfiles/.vimrc
#
#   # Adopt with custom name
#   $ dotfiles-adopt ~/.config/nvim nvim-config
#   ✓ Moved ~/.config/nvim → ~/dotfiles/nvim-config
#   ✓ Created symlink ~/.config/nvim → ~/dotfiles/nvim-config
#
#   # Adopt into subdirectory
#   $ dotfiles-adopt ~/.config/starship.toml .config/starship.toml
#   ✓ Moved ~/.config/starship.toml → ~/dotfiles/.config/starship.toml
#   ✓ Created symlink ~/.config/starship.toml → ~/dotfiles/.config/starship.toml
#
# OPTIONS:
#   -n, --dry-run    Show what would be done without making changes
#   -h, --help       Show this help message
#
# RELATED:
#   - setup.sh (creates symlinks from dotfiles to ~/)
#
# =============================================================================

function dotfiles-adopt
    # Configuration
    set -l dotfiles_dir "$HOME/dotfiles"
    set -l dry_run false

    # Colors
    set -l green (set_color green)
    set -l red (set_color red)
    set -l yellow (set_color yellow)
    set -l cyan (set_color cyan)
    set -l magenta (set_color magenta)
    set -l reset (set_color normal)

    # Parse arguments
    set -l positional_args
    for arg in $argv
        switch $arg
            case -h --help
                echo "$green""dotfiles-adopt$reset - Move file/directory to dotfiles and create symlink"
                echo ""
                echo "$yellow""USAGE:$reset"
                echo "    dotfiles-adopt [OPTIONS] <path> [destination_name]"
                echo ""
                echo "$yellow""ARGUMENTS:$reset"
                echo "    path             Path to the file or directory to adopt"
                echo "    destination_name Optional name to use in dotfiles (default: original name)"
                echo ""
                echo "$yellow""OPTIONS:$reset"
                echo "    -n, --dry-run    Show what would be done without making changes"
                echo "    -h, --help       Show this help message"
                echo ""
                echo "$yellow""EXAMPLES:$reset"
                echo "    dotfiles-adopt ~/.vimrc"
                echo "    dotfiles-adopt ~/.config/nvim nvim-config"
                echo "    dotfiles-adopt ~/.config/starship.toml .config/starship.toml"
                echo ""
                return 0
            case -n --dry-run
                set dry_run true
            case '-*'
                echo "$red""Error: Unknown option: $arg$reset"
                echo "Use --help for usage information"
                return 1
            case '*'
                set -a positional_args $arg
        end
    end

    # Validate arguments
    if test (count $positional_args) -lt 1
        echo "$red""Error: No path specified$reset"
        echo "Usage: dotfiles-adopt <path> [destination_name]"
        echo "Use --help for more information"
        return 1
    end

    set -l source_path $positional_args[1]
    set -l dest_name

    # Determine destination name
    if test (count $positional_args) -ge 2
        set dest_name $positional_args[2]
    else
        set dest_name (basename $source_path)
    end

    # Resolve to absolute path
    set -l abs_source_path (realpath $source_path 2>/dev/null)
    if test -z "$abs_source_path"
        echo "$red""Error: Path does not exist: $source_path$reset"
        return 1
    end

    # Validate source exists
    if not test -e $abs_source_path
        echo "$red""Error: Path does not exist: $abs_source_path$reset"
        return 1
    end

    # Check if source is already a symlink
    if test -L $abs_source_path
        echo "$yellow""Warning: $abs_source_path is already a symlink$reset"
        set -l link_target (readlink $abs_source_path)
        echo "  Points to: $link_target"
        echo "$red""Aborting to prevent data loss$reset"
        return 1
    end

    # Validate dotfiles directory exists
    if not test -d $dotfiles_dir
        echo "$red""Error: Dotfiles directory does not exist: $dotfiles_dir$reset"
        return 1
    end

    # Build destination path
    set -l dest_path "$dotfiles_dir/$dest_name"

    # Check if destination already exists
    if test -e $dest_path
        echo "$red""Error: Destination already exists: $dest_path$reset"
        echo "Please remove it first or use a different destination name"
        return 1
    end

    # Create parent directories if needed (for paths like .config/foo.toml)
    set -l dest_parent (dirname $dest_path)
    if not test -d $dest_parent
        if $dry_run
            echo "$magenta""[DRY-RUN]$reset Would create directory: $dest_parent"
        else
            mkdir -p $dest_parent
            if test $status -ne 0
                echo "$red""Error: Failed to create directory: $dest_parent$reset"
                return 1
            end
        end
    end

    # Show dry-run header
    if $dry_run
        echo "$magenta""=========================================$reset"
        echo "$magenta""  DRY-RUN MODE - No changes will be made$reset"
        echo "$magenta""=========================================$reset"
        echo ""
    end

    # Determine file type for display
    set -l file_type "file"
    if test -d $abs_source_path
        set file_type "directory"
    end

    echo "$cyan""Adopting $file_type into dotfiles...$reset"
    echo "  Source: $abs_source_path"
    echo "  Destination: $dest_path"
    echo ""

    # Step 1: Move to dotfiles
    if $dry_run
        echo "$magenta""[DRY-RUN]$reset Would move: $abs_source_path → $dest_path"
    else
        mv $abs_source_path $dest_path
        if test $status -ne 0
            echo "$red""Error: Failed to move $abs_source_path$reset"
            return 1
        end
        echo "$green""✓$reset Moved $abs_source_path → $dest_path"
    end

    # Step 2: Create symlink at original location
    if $dry_run
        echo "$magenta""[DRY-RUN]$reset Would create symlink: $abs_source_path → $dest_path"
    else
        ln -s $dest_path $abs_source_path
        if test $status -ne 0
            echo "$red""Error: Failed to create symlink$reset"
            echo "$yellow""Warning: File has been moved but symlink creation failed!$reset"
            echo "  File location: $dest_path"
            echo "  Run manually: ln -s $dest_path $abs_source_path"
            return 1
        end
        echo "$green""✓$reset Created symlink $abs_source_path → $dest_path"
    end

    # Success message
    echo ""
    if $dry_run
        echo "$magenta""=========================================$reset"
        echo "$magenta""  DRY-RUN COMPLETE - No changes were made$reset"
        echo "$magenta""=========================================$reset"
        echo "$yellow""Run without --dry-run to apply changes$reset"
    else
        echo "$green""✓ Successfully adopted into dotfiles!$reset"
        echo ""
        echo "$yellow""Next steps:$reset"
        echo "  1. cd $dotfiles_dir"
        echo "  2. git add $dest_name"
        echo "  3. git commit -m \"Add $dest_name\""
    end

    return 0
end
