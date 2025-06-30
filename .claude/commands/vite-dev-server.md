# Vite Dev Server Command

Start the Vite dev server in a dedicated tmux session to prevent blocking your terminal:

1. Create/attach to tmux session: `tmux new -s vite-dev-server -d`
2. Send commands to the session: `tmux send-keys -t vite-dev-server "cd $(pwd) && yarn dev" Enter` or `tmux send-keys -t vite-dev-server "cd $(pwd) && pnpm dev" Enter` or `tmux send-keys -t vite-dev-server "cd $(pwd) && npm run dev" Enter`
3. The server runs in background, accessible via `tmux attach -t vite-dev-server`
