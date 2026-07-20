# NotchHUD — Build Task List

Source of truth for the `/goal` autonomous loop. A task is checked off ONLY when its acceptance check passes (built AND run AND observed). Executor: GPT-5.6 Sol via `codex exec`. Manager: Claude (audits + runs the gate).

Legend: `[ ]` todo · `[~]` in progress · `[x]` verified done

---

## M0 — Notch skeleton
- [x] `Package.swift` (executable `NotchHUD`, macOS 14 target, DynamicNotchKit dependency) — vendored + patched DynamicNotchKit (@Entry/#Preview stripped for CLT)
- [x] App entry: `NotchHUDApp` + `AppDelegate`, `LSUIElement`/`.accessory`, no Dock icon
- [x] `AppEnvironment` (spool path `~/.notch-hud/sessions`, staleness thresholds)
- [x] `NotchWindowManager` wrapping DynamicNotchKit: peek (hardcoded count) + hover-expand static list
- [x] `HoverController` hybrid (tracking window + global mouse monitor, debounced)
- [x] **GATE M0 (build/launch):** `swift build` exits 0; app launches, stays alive, no Dock icon
- [x] **GATE M0 (hover):** widened hitRect covers the visible peek; automated eval `evals/hover_eval.sh` = 4/4 triggers; COOPER CONFIRMED panel drops on hover (2026-07-20)
- [x] M0.5: pure `NotchGeometry` + `swift test` target — 8/8 tests pass (incl. peek-edge regression); hover eval still PASS post-refactor

### Design decisions locked
- **Dark glass** for this app (approved exception to light-theme rule; chin fuses with hardware).
- **Hybrid indicator direction** (2026-07-20): premium glass panel + a subtle reactive mascot accent. Inspiration + differentiation vs Marc Lou's Pac-Man notch (x.com/marclou/status/2079013991834337774): his is Codex-only + 2-state; ours = multi-agent, 3-state (adds "Needs me"), click-to-focus, premium. Mascot needs a distinct working-loop / needs-you / celebratory-done. Detail work lands in M6.

## M1 — One real Claude session end-to-end
- [x] `~/.notch-hud/bin/notch-emit` shared emitter (atomic write, `seq`) — valid JSON verified. NOTE: tty capture returns null, needs fix for M2 click-to-focus
- [x] `notch-claude-hook` shim (stdin JSON → status → notch-emit) — verified with simulated payload (working→done, seq 1→2)
- [x] `Session`, `SessionEnvelope`, `SessionStatus`, `TerminalIdentity` models
- [x] `SpoolWatcher` (DispatchSource vnode + 150ms debounce + rescan-diff), `SpoolReader`, `SessionStore` (@Observable) — watcher verified: 3 fixture sessions rendered live with correct colors + sort (screenshot)
- [x] Views wired to live store (peek count + panel + rows update from spool)
- [x] Add `UserPromptSubmit`→working, `Stop`→done Claude hooks — installed PROJECT-SCOPED (.claude/settings.json in notch-hud) per Cooper, safe test before global
- [x] **GATE M1: COOPER CONFIRMED (2026-07-20)** — real Claude session showed Working (blue) then Done (green)
- [x] Promoted hooks to GLOBAL ~/.claude/settings.json (additive, backup made, all existing hooks preserved) + added SessionEnd→remove for clean lifecycle. Project-scoped copy removed.

## M2 — Click to focus
- [ ] `FocusDispatcher` + `FocusStrategy` protocol + `AppleScriptRunner`
- [ ] `TerminalAppStrategy` (AppleScript match by tty, raise window/tab)
- [ ] `NSAppleEventsUsageDescription` in Info.plist; deny-path affordance
- [ ] **GATE M2:** click a row → correct Terminal tab raises; Automation prompt grant works; deny shows affordance

## M3 — Full Claude state machine + staleness
- [ ] Idempotent diff-preview installer adds SessionStart/Notification/SessionEnd hooks
- [ ] `StalenessSweeper` (90s demote) + pid reconciliation
- [ ] **GATE M3:** permission prompt → Needs-me state; `kill -9` mid-turn → row demotes to unknown in 90s then drops

## M4 — Generic poller
- [ ] `ProcessPoller` (ps tpgid busy/idle, agent regex, source-rank so it never overwrites hook files)
- [ ] **GATE M4:** non-hooked agent appears Working then clears on exit; never clobbers a live Claude file

## M5 — Codex adapter
- [ ] `notch-codex-notify` wrapper (maps turn-end → done, chain-execs SkyComputerUseClient)
- [ ] Wire poller to supply Codex `working`
- [ ] **GATE M5:** Codex turn → Working (poller) → Done (notify); computer-use still functions

## M6 — Design polish + productize
- [ ] Liquid Glass material (macOS 26) + NSVisualEffectView fallback; dark-glass panel per art direction
- [ ] Status colors + per-state motion (breathing / blink / checkmark)
- [ ] "The Merge" signature moment (matchedGeometry morph + Vortex burst + count tick + name flash)
- [ ] Pow micro-feedback, Kenney sounds + NSHapticFeedbackManager, SF Pro Rounded, settings window
- [ ] Non-notch fallback pill + multi-monitor re-pin
- [ ] **GATE M6:** on-screen review of all motion moments; final acceptance = 3+ real sessions (2 Claude, 1 Codex), correct peek count, correct states, The Merge fires, click raises correct tab

---
## Completion condition (the `/goal`)
Every box above `[x]`, `swift build` exits 0, the app launches, and each GATE has been confirmed on screen. Stop after the run if all gates green, or halt for a human on any gate that needs visual judgment.
