#!/bin/bash

#=========================================================
# ANSIColors
#=========================================================
GREEN="\033[0;32m"
BLUE="\033[0;34m"
RESET_COLOR="\033[0m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
MAGENTA="\033[0;35m"
CYAN="\033[0;36m"
BLACK_BOLD="\033[1;30m"
BG_GREEN="\033[42m"

#=========================================================
# Options
#=========================================================
DRY_RUN=false

#=========================================================
# Help Function
#=========================================================
show_help() {
    echo -e "${GREEN}dotfiles setup.sh${RESET_COLOR} - macOS development environment setup script"
    echo ""
    echo -e "${YELLOW}USAGE:${RESET_COLOR}"
    echo "    ./setup.sh [OPTIONS]"
    echo ""
    echo -e "${YELLOW}OPTIONS:${RESET_COLOR}"
    echo "    -h, --help      Show this help message and exit"
    echo "    -n, --dry-run   Show what would be done without making changes"
    echo ""
    echo -e "${YELLOW}WHAT THIS SCRIPT DOES:${RESET_COLOR}"
    echo -e "    1. ${CYAN}macOS Defaults${RESET_COLOR}"
    echo "       - Show hidden files in Finder"
    echo "       - Show POSIX path in Finder title bar"
    echo "       - Disable auto-capitalization, dash/quote substitution"
    echo "       - Disable spelling correction and text completion"
    echo "       - Disable Siri"
    echo ""
    echo -e "    2. ${CYAN}Homebrew${RESET_COLOR}"
    echo "       - Install packages from Brewfile (if needed)"
    echo ""
    echo -e "    3. ${CYAN}Symlinks${RESET_COLOR}"
    echo "       - Create symlinks from ~/dotfiles/.??* to ~/"
    echo "       - Excludes: .git, .DS_Store"
    echo ""
    echo -e "    4. ${CYAN}Fish Shell${RESET_COLOR}"
    echo "       - Add fish to /etc/shells (requires sudo)"
    echo "       - Set fish as default login shell"
    echo ""
    echo -e "${YELLOW}EXAMPLES:${RESET_COLOR}"
    echo "    ./setup.sh              # Run full setup"
    echo "    ./setup.sh --dry-run    # Preview changes without applying"
    echo "    ./setup.sh -h           # Show this help"
    echo ""
    exit 0
}

#=========================================================
# Argument Parsing
#=========================================================
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            echo -e "${RED}Unknown option: $1${RESET_COLOR}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

#=========================================================
# Dry Run Helper
#=========================================================
# Execute command or show what would be done in dry-run mode
run_cmd() {
    if $DRY_RUN; then
        echo -e "${MAGENTA}[DRY-RUN]${RESET_COLOR} Would run: $*"
    else
        "$@"
    fi
}

if $DRY_RUN; then
    echo -e "${MAGENTA}=========================================${RESET_COLOR}"
    echo -e "${MAGENTA}  DRY-RUN MODE - No changes will be made${RESET_COLOR}"
    echo -e "${MAGENTA}=========================================${RESET_COLOR}\n"
fi

#=========================================================
# Mac OSX Magic
#=========================================================
echo -e "${GREEN}Disabling press-and-hold for special characters...${RESET_COLOR}"
echo -e "${BLUE}Press-and-hold disabled.${RESET_COLOR}"

echo -e "${GREEN}Enabling visibility of hidden files in Finder...${RESET_COLOR}"
run_cmd defaults write com.apple.finder AppleShowAllFiles TRUE
echo -e "${BLUE}Hidden files are now visible in Finder.${RESET_COLOR}"

echo -e "${GREEN}Enabling POSIX path in Finder title bar...${RESET_COLOR}"
run_cmd defaults write com.apple.finder _FXShowPosixPathInTitle -bool true
echo -e "${BLUE}POSIX path is now shown in Finder title bar.${RESET_COLOR}"

echo -e "${GREEN}Disabling automatic text transformations to keep typing intentional and eco-friendly...${RESET_COLOR}"
echo -e "${CYAN}Turning off automatic capitalization, dash/quote substitution, spelling correction and text completion.${RESET_COLOR}"
run_cmd defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
run_cmd defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
run_cmd defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
run_cmd defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
run_cmd defaults write NSGlobalDomain NSAutomaticTextCompletionEnabled -bool false
echo -e "${BLUE}Automatic text transformations have been disabled.${RESET_COLOR}"
echo -e "${YELLOW}Tip: These settings reduce accidental edits and unnecessary typing — a small step toward being kinder to your time and device energy use.${RESET_COLOR}"

run_cmd defaults write com.apple.assistant.support 'Siri Enabled' -bool false
echo -e "${BLUE}Siri has been disabled.${RESET_COLOR}"

echo -e "${GREEN}Restarting Finder...${RESET_COLOR}"
run_cmd killall Finder
echo -e "${BLUE}Finder has been restarted.${RESET_COLOR}"

#=========================================================
# Install essential tools from Brewfile
#=========================================================
# Decide whether to skip brew bundle by checking if all current leaves exist in Brewfile
BREWFILE="$HOME/dotfiles/Brewfile"
if [ -f "$BREWFILE" ]; then
  # collect current leaves (avoid mapfile for macOS bash 3.2 compatibility)
  LEAVES="$(brew leaves 2>/dev/null | sort -u)"
  # collect brew entries from Brewfile (formula names only)
  BREW_PKGS="$(awk -F '"' '/^\s*brew\s+"/{print $2}' "$BREWFILE" | sort -u)"

  ALL_CONTAINED=1
  if [ -n "$LEAVES" ]; then
    for leaf in $LEAVES; do
      if ! echo "$BREW_PKGS" | grep -qx "$leaf"; then
        ALL_CONTAINED=0
        break
      fi
    done
  fi

  if [ "$ALL_CONTAINED" -eq 1 ]; then
    echo -e "${BLUE}All brew leaves are present in Brewfile. Skipping brew bundle.${RESET_COLOR}"
  else
    echo -e "${GREEN}Starting Brewfile installations...${RESET_COLOR}"
    run_cmd brew bundle
    if ! $DRY_RUN; then
      echo -e "\n${GREEN}Brewfile install has just completed!!${RESET_COLOR}\n"
      sleep 3s
    fi
  fi
else
  echo -e "${YELLOW}Brewfile not found at $BREWFILE. Running brew bundle in current directory if Brewfile exists here...${RESET_COLOR}"
  if [ -f Brewfile ]; then
    echo -e "${GREEN}Starting Brewfile installations...${RESET_COLOR}"
    run_cmd brew bundle
    if ! $DRY_RUN; then
      echo -e "\n${GREEN}Brewfile install has just completed!!${RESET_COLOR}\n"
      sleep 3s
    fi
  else
    echo -e "${RED}No Brewfile found. Skipping brew bundle.${RESET_COLOR}"
  fi
fi
#=========================================================
# Create Symlink
#=========================================================
echo -e "${GREEN}Creating symlinks for dotfiles...${RESET_COLOR}"
cd "$HOME/dotfiles" || exit 1
for f in .??*
do
    [[ "$f" =~ ^[^\.].* ]] && continue
    [[ "$f" == ".git" ]] && continue
    [[ "$f" == ".DS_Store" ]] && continue

    if [ -e "$HOME/$f" ]; then
        if $DRY_RUN; then
            echo -e "${MAGENTA}[DRY-RUN]${RESET_COLOR} Would overwrite: $HOME/$f"
        else
            read -p "File $HOME/$f exists. Overwrite? (y/n) " -n 1 -r
            echo    # move to a new line
            if [[ ! $REPLY =~ ^[Yy]$ ]]
            then
                continue
            fi
        fi
    fi

    run_cmd ln -sf "$HOME/dotfiles/$f" "$HOME/$f"

    if $DRY_RUN; then
        echo -e "${MAGENTA}[DRY-RUN]${RESET_COLOR} Would create symlink: ${f}"
    else
        echo -e "${BLACK_BOLD}${BG_GREEN}Created ${f}${RESET_COLOR} symlink."
    fi
done
echo -e "${BLACK_BOLD}${BG_GREEN}Symlink creation task completed!${RESET_COLOR}"
if ! $DRY_RUN; then
    sleep 1s
fi
#=========================================================
# Setup fish-shell (fish-shell is contained in Brewfile)
#=========================================================
echo -e "${GREEN}Setting up fish shell...${RESET_COLOR}"
if grep -qE "/opt/homebrew/bin/fish" /etc/shells; then
    echo -e "${BLUE}Fish shell already registered in /etc/shells${RESET_COLOR}"
else
    if $DRY_RUN; then
        echo -e "${MAGENTA}[DRY-RUN]${RESET_COLOR} Would add /opt/homebrew/bin/fish to /etc/shells (requires sudo)"
    else
        echo "/opt/homebrew/bin/fish" | sudo tee -a /etc/shells
    fi
fi

if $DRY_RUN; then
    echo -e "${MAGENTA}[DRY-RUN]${RESET_COLOR} Would run: chsh -s /opt/homebrew/bin/fish"
else
    chsh -s /opt/homebrew/bin/fish
fi

#=========================================================
# Finish
#=========================================================
if ! $DRY_RUN; then
    sleep 0.5s
fi

echo -e "\n"
if $DRY_RUN; then
    echo -e "${MAGENTA}=========================================${RESET_COLOR}"
    echo -e "${MAGENTA}  DRY-RUN COMPLETE - No changes were made${RESET_COLOR}"
    echo -e "${MAGENTA}=========================================${RESET_COLOR}"
    echo -e "${YELLOW}Run without --dry-run to apply changes${RESET_COLOR}"
else
    echo -e "${GREEN}Setup has just completed!!${RESET_COLOR}"
fi
