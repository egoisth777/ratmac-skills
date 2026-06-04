#!/usr/bin/env bash
# install.sh — POSIX shadow of install.ps1. Symlink ratmac-* skills into ~/.claude/skills.
# develop = per-skill DIR symlink (ln -s on the dir). debug = per-file symlink (mirror tree, ln -s each file).
# Usage: install.sh [--mode develop|debug] [--claude-dir <path>] [--only s1,s2] [--force]
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC_SKILLS="$HERE/skills"

MODE="develop"
CLAUDE_DIR="${HOME}/.claude/skills"
ONLY=""
FORCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --mode)       MODE="$2"; shift 2 ;;
    --claude-dir) CLAUDE_DIR="$2"; shift 2 ;;
    --only)       ONLY="$2"; shift 2 ;;
    --force)      FORCE=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

case "$MODE" in develop|debug) ;; *) echo "BLOCKED --mode must be develop|debug" >&2; exit 2 ;; esac

mkdir -p "$CLAUDE_DIR"

# is name in the comma-separated --only filter? (empty filter = accept all)
in_only() {
  [ -z "$ONLY" ] && return 0
  local name="$1" item
  IFS=',' read -ra items <<< "$ONLY"
  for item in "${items[@]}"; do [ "$item" = "$name" ] && return 0; done
  return 1
}

results=()
count=0
for sd in "$SRC_SKILLS"/ratmac-*; do
  [ -d "$sd" ] || continue
  name="$(basename "$sd")"
  in_only "$name" || continue
  source="$(cd "$sd" && pwd)"
  target="$CLAUDE_DIR/$name"
  count=$((count+1))

  # existing target handling
  if [ -e "$target" ] || [ -L "$target" ]; then
    if [ -L "$target" ]; then
      existing="$(readlink "$target")"
      if [ "$existing" = "$source" ] && [ "$MODE" = "develop" ]; then
        results+=("no-op:  $name (already linked)"); continue
      fi
      if [ "$FORCE" = "1" ]; then rm -rf "$target"
      else results+=("WARN:   $name exists as link to '$existing' — pass --force to relink"); continue; fi
    else
      if [ "$FORCE" = "1" ]; then rm -rf "$target"
      else results+=("STOP:   $name exists as a REAL dir — refusing to destroy. Inspect, then --force."); continue; fi
    fi
  fi

  if [ "$MODE" = "develop" ]; then
    if ln -s "$source" "$target" 2>/dev/null; then results+=("linked: $name -> $source (symlink)")
    else results+=("ERROR:  $name — ln -s failed"); fi
  else  # debug: mirror dir tree, per-file symlink
    mkdir -p "$target"
    n=0
    while IFS= read -r d; do
      rel="${d#"$source"/}"
      mkdir -p "$target/$rel"
    done < <(find "$source" -mindepth 1 -type d)
    while IFS= read -r f; do
      rel="${f#"$source"/}"
      dst="$target/$rel"
      [ -e "$dst" ] || [ -L "$dst" ] && rm -f "$dst"
      if ln -s "$f" "$dst" 2>/dev/null; then n=$((n+1))
      else results+=("ERROR:  $name/$rel — ln -s failed"); fi
    done < <(find "$source" -type f)
    results+=("mirrored: $name ($n files linked)")
  fi
done

for r in "${results[@]:-}"; do [ -n "$r" ] && printf '%s\n' "$r"; done
echo
echo "Mode: $MODE | ClaudeDir: $CLAUDE_DIR | skills: $count"
echo "Restart Claude Code (or /skills reload) to discover."
