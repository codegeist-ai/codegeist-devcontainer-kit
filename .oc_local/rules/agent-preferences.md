# Agent Preferences

## Configuration Scope

- Keep agent-created settings and instructions in the current project workspace.
- Never write files or configuration in the user's home directory outside the
  workspace, including `~/.config/opencode/`. Use project-owned `.oc_local/`
  overlays for OpenCode preferences and the approved temporary storage for
  disposable artifacts.

## Web Search

- Use the installed `ddgr` command through the shell for general web searches:
  `ddgr --json --num 5 "search terms"`. JSON mode is non-interactive.
- Keep the built-in OpenCode `websearch` tool disabled in `.oc_local/opencode.json`.
  Use `ddgr` rather than requesting a hosted search-provider connection.
- Read relevant result URLs and prefer official sources. Continue using Context7
  for library and framework documentation when applicable.
