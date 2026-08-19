#!/bin/sh
# Install the NotchHUD runtime: emitter scripts into ~/.notch-hud/bin and
# Claude Code hooks (UserPromptSubmit/Stop/SessionEnd) into ~/.claude/settings.json.
# Idempotent: safe to re-run. Does NOT register notch-approve (M4 out of scope).
set -eu

script_dir=$(CDPATH= cd -P "$(dirname "$0")" && pwd)
notch_home=${NOTCH_HUD_HOME:-"$HOME/.notch-hud"}
settings="$HOME/.claude/settings.json"

# Dirs: bin for scripts; sessions+seq used by notch-emit;
# pending/decisions/session-allow expected by AppEnvironment.swift.
for d in bin sessions seq pending decisions session-allow; do
    mkdir -p "$notch_home/$d"
    chmod 700 "$notch_home/$d"
done
echo "dirs ready under $notch_home"

for f in notch-emit notch-claude-hook notch-approve notch-codex-notify; do
    cp "$script_dir/$f" "$notch_home/bin/$f"
    chmod +x "$notch_home/bin/$f"
done
echo "installed notch-emit notch-claude-hook notch-approve notch-codex-notify to $notch_home/bin (notch-approve not registered; notch-codex-notify wired via ~/.codex/config.toml notify)"

hook_cmd="$notch_home/bin/notch-claude-hook"
NOTCH_HOOK_CMD="$hook_cmd" SETTINGS="$settings" python3 - <<'PY'
import json, os, shutil, sys, time

settings_path = os.environ["SETTINGS"]
hook_cmd = os.environ["NOTCH_HOOK_CMD"]
wanted = [("UserPromptSubmit", "working"), ("Stop", "done"), ("SessionEnd", "remove")]

if os.path.exists(settings_path):
    with open(settings_path) as f:
        settings = json.load(f)
else:
    settings = {}

hooks = settings.setdefault("hooks", {})
added = []
for event, status in wanted:
    entries = hooks.setdefault(event, [])
    if any("notch-claude-hook" in h.get("command", "")
           for e in entries for h in e.get("hooks", [])):
        print(f"skip {event}: notch hook already registered")
        continue
    entries.append({"hooks": [{"type": "command",
                               "command": f"{hook_cmd} {status}"}]})
    added.append(event)

if not added:
    print("settings.json unchanged")
    sys.exit(0)

if os.path.exists(settings_path):
    backup = f"{settings_path}.bak.{time.strftime('%Y%m%d-%H%M%S')}"
    shutil.copy2(settings_path, backup)
    print(f"backup: {backup}")

tmp = settings_path + ".tmp"
with open(tmp, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
os.replace(tmp, settings_path)
print(f"registered hooks in {settings_path}: {', '.join(added)}")
PY

echo "install complete"
