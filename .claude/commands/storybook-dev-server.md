# Storybook Dev Server Command

Start the Storybook dev server in a dedicated tmux session to prevent blocking your terminal:

1. Create/attach to tmux session: `tmux new -s storybook-dev-server -d`
2. Send commands to the session: `tmux send-keys -t storybook-dev-server "cd $(pwd) && yarn storybook" Enter` or `tmux send-keys -t storybook-dev-server "cd $(pwd) && pnpm storybook" Enter` or `tmux send-keys -t storybook-dev-server "cd $(pwd) && npm run storybook" Enter`
3. The server runs in background, accessible via `tmux attach -t storybook-dev-server`
