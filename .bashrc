[ -f ~/.fzf.bash ] && source ~/.fzf.bash
eval "$(pyenv init -)"
. "$HOME/.cargo/env"
source ~/.bash_completion/alacritty

[[ "$TERM_PROGRAM" == "kiro" ]] && . "$(kiro --locate-shell-integration-path bash)"

# --- Java 17 and Android SDK environment variables (guarded) ---
# Set JAVA_HOME to Java 17 only if available
if command -v /usr/libexec/java_home >/dev/null 2>&1; then
	_java17=$(/usr/libexec/java_home -v17 2>/dev/null)
	if [ -n "$_java17" ]; then
		export JAVA_HOME="$_java17"
	fi
fi

# Set ANDROID_HOME and add emulator/platform-tools to PATH only if SDK exists
if [ -d "$HOME/Library/Android/sdk" ]; then
	export ANDROID_HOME="$HOME/Library/Android/sdk"
	case ":$PATH:" in
		*":$ANDROID_HOME/emulator:"*) : ;;
		*) export PATH="$PATH:$ANDROID_HOME/emulator" ;;
	esac
	case ":$PATH:" in
		*":$ANDROID_HOME/platform-tools:"*) : ;;
		*) export PATH="$PATH:$ANDROID_HOME/platform-tools" ;;
	esac
fi


# source ~/.safe-chain/scripts/init-posix.sh # Safe-chain bash initialization script
