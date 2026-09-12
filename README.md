# NotchHUD

A MacBook-notch HUD for your AI agent swarm. Live status (Working / Needs me / Done) for every agentic CLI session (Claude Code, Codex, more), always-on peek, hover-expand glass panel, click-to-focus the exact terminal.

Built Swift 6 / SwiftUI + AppKit, SPM, Command Line Tools only (vendored DynamicNotchKit, macro-patched). See TASKS.md for build state and specs/ for milestone specs.

Build: `swift build` · Test: `swift test` · Bundle: `scripts/make-app.sh` → `build/NotchHUD.app`

Install runtime: `scripts/install.sh` — copies the emitter scripts to `~/.notch-hud/bin` and additively registers the Claude Code hooks (UserPromptSubmit→working, Stop→done, SessionEnd→remove) in `~/.claude/settings.json` (timestamped backup, idempotent).

## Controls

- **Hover** the notch to expand the panel; move away to collapse. **Pin** (📌 in the panel header) keeps it open.
- **⌃⌥⌘N** toggles the panel from anywhere, system-wide (Carbon hotkey, no Accessibility grant needed). Esc or a click outside also closes it. Change the chord in `NotchHUDApp.swift` (`GlobalHotKey(keyCode:modifiers:)`).
- **Open only with ⌃⌥⌘N** (gear menu in the panel, or the menu bar icon) turns hover off entirely: the panel opens and closes only via the hotkey, Esc, or a click outside. Pending approval cards still auto-expand.
- **Hide notch (hover still works)** ghosts the resting pill so it never covers screen content. Combine with the setting above for a fully invisible HUD that appears only on the hotkey.
- `notch` (alias added by `scripts/install.sh`) relaunches the app if it was quit.

## Codex setup

`scripts/notch-codex-notify` adapts Codex CLI's `notify` hook: on `agent-turn-complete` it emits status `done` via `~/.notch-hud/bin/notch-emit`, then chain-execs any notify program you already had (same args, payload included), so existing behavior is preserved. Fail-open: any error exits 0. Wire it in `~/.codex/config.toml` (back the file up first) by prepending it to your existing `notify`:

```toml
notify = [
    "/Users/you/.notch-hud/bin/notch-codex-notify",
    # ...your previous notify program and its args, if any...
]
```
