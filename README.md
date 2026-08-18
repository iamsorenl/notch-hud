# NotchHUD

A MacBook-notch HUD for your AI agent swarm. Live status (Working / Needs me / Done) for every agentic CLI session (Claude Code, Codex, more), always-on peek, hover-expand glass panel, click-to-focus the exact terminal.

Built Swift 6 / SwiftUI + AppKit, SPM, Command Line Tools only (vendored DynamicNotchKit, macro-patched). See TASKS.md for build state and specs/ for milestone specs.

Build: `swift build` · Test: `swift test` · Bundle: `scripts/make-app.sh` → `build/NotchHUD.app`

Install runtime: `scripts/install.sh` — copies the emitter scripts to `~/.notch-hud/bin` and additively registers the Claude Code hooks (UserPromptSubmit→working, Stop→done, SessionEnd→remove) in `~/.claude/settings.json` (timestamped backup, idempotent).
