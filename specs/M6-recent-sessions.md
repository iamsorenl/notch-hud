# M6 spec — Recent sessions & resume from the notch

Goal: the panel gains a **Recents** section — the most recent finished Claude Code
conversations across all projects — and clicking one reopens that exact
conversation in a new Terminal tab via `claude --resume`. The resumed session
re-enters the spool through the existing hooks, so its row promotes from Recents
back to Live with no extra plumbing. Phase A of the Console direction: the
SessionIndex built here is the data layer later phases (Console window,
SwiftTerm) reuse.

Reviewed as an Agent-Native visual plan 2026-08-18 (local-files mode); decisions
below reflect Cooper's answers there.

## INVARIANTS
- **Read-only over `~/.claude/projects`.** The index never writes, renames, or
  locks a transcript. A corrupt transcript can never be made worse by NotchHUD.
- **Head-only reads.** Transcripts reach 86 MB; every row's metadata lives in the
  first few KB. Read a bounded head (64 KB / 200 lines, whichever first) per
  file, never the whole file.
- **Skip, never crash.** The transcript format is Claude Code's internal,
  unversioned format. Any line that doesn't parse is skipped; a file with no
  parsable title records falls back to directory-name + mtime. Fixtures in
  SessionIndexTests document the assumed shape so a format change fails loudly
  in tests, not silently in the panel.
- **Live sessions never appear in Recents.** A transcript whose sessionId is
  claimed by any spool envelope (`claude-<sessionId>`) is excluded.

## 1. SessionIndex (`Sources/NotchHUD/Store/SessionIndex.swift`)
- `RecentSession`: `id` (transcript UUID), `title` (aiTitle ▸ lastPrompt ▸
  project dir name), `projectName` (last component of cwd), `cwd`,
  `lastActive` (file mtime).
- Record shapes parsed from the head:
  `{"type":"ai-title","aiTitle":...}`, `{"type":"last-prompt","lastPrompt":...}`
  (both optional-field tolerant), and `cwd` from any record carrying it.
- Pure, injectable, ProcessPoller-style: `parseHead(_:)` and
  `plan(candidates:liveSessionIDs:limit:)` are static and unit-tested; file I/O
  stays thin. Scan sorts by mtime descending before reading heads, reads only as
  many files as needed to fill the caps.
- Refresh is lazy: rescan when the panel expands. No watchers, no timers.

## 2. ResumeLauncher (`Sources/NotchHUD/Focus/ResumeLauncher.swift`)
- `command(for:)` → `cd <escaped cwd> && claude --resume <id>` (cwd falls back
  to `~` if the directory no longer exists).
- `resume(_:)` → AppleScript to Terminal.app: `do script` in a new tab +
  activate, via the existing `AppleScriptRunner` (same Automation permission and
  error mapping as click-to-focus).
- Denied automation: the row copies `command(for:)` to the clipboard and shows
  the existing Grant Automation affordance.

## 3. Recents UI (`RecentsSectionView.swift`, `RecentSessionRowView.swift`)
- Muted section below live sessions in `NotchPanelView`; live sessions stay
  visually dominant.
- Filter-chip row heads the section: **All** (flat, newest first) + one chip per
  project with recents, ordered by most-recent activity, overflow behind a
  `+N` chip. Every view caps at 8 rows. Selected chip persists while the panel
  is open, resets to All on collapse.
- Row: title · project folder name · relative age. Click → ResumeLauncher.

## GATE M6
Build + tests green (SessionIndex fixtures: head parse, exclusion, ordering,
cap, malformed-line skip). Cooper: expand panel → Recents shows real history
with working chips → click a recent → Terminal tab opens the resumed
conversation → its row promotes to Live.

## Explicitly deferred
Console window + transcript reader (Phase B); SwiftTerm-embedded sessions
(Phase C); resume into iTerm2/kitty/WezTerm; Codex history (lives outside
`~/.claude/projects`); time/agent filter chips (the chip row generalizes when
wanted).
