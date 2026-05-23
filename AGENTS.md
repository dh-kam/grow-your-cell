# Agent Instructions

- Debugging, execution, testing, and build commands must run inside the existing `cell-term` tmux session.
- Do not close the `cell-term` session. If it is accidentally closed, recreate it as `cell-term`.
- Do not add windows or panes to `cell-term`.
- Assume the user may be watching the `cell-term` session live, so keep commands and output intentional and easy to follow.
- Keep a separate `cell-run` tmux session for the long-running game process / hot-reload loop.
- Do not close the `cell-run` session. If it is accidentally closed, recreate it as `cell-run`.
- Do not add windows or panes to `cell-run`.
- Use `cell-run` only for the persistent game runner. Keep other debugging, one-off execution, testing, and build commands in `cell-term`.
