#!/usr/bin/env bash
# uninstall.sh — POSIX shadow of uninstall.ps1. Sever ratmac-* links from ~/.claude/skills.
# Source repo untouched. Usage: uninstall.sh [--claude-dir <path>] [--only s1,s2] [--force]
set -uo pipefail

CLAUDE_DIR="${HOME}/.claude/skills"
ONLY=""
FORCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --claude-dir) CLAUDE_DIR="$2"; shift 2 ;;
    --only)       ONLY="$2"; shift 2 ;;
    --force)      FORCE=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ ! -d "$CLAUDE_DIR" ]; then echo "nothing to do: $CLAUDE_DIR absent"; exit 0; fi

in_only() {
  [ -z "$ONLY" ] && return 0
  local name="$1" item
  IFS=',' read -ra items <<< "$ONLY"
  for item in "${items[@]}"; do [ "$item" = "$name" ] && return 0; done
  return 1
}

for e in "$CLAUDE_DIR"/ratmac-*; do
  [ -e "$e" ] || [ -L "$e" ] || continue
  name="$(basename "$e")"
  in_only "$name" || continue
  if [ -L "$e" ]; then
    rm -rf "$e"
    echo "removed link: $name"
  else
    # debug-mode mirror: real dir of per-file symlinks. Count real (non-symlink) files.
    nonlink="$(find "$e" \( -type f -a ! -type l \) 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$nonlink" = "0" ] || [ "$FORCE" = "1" ]; then
      rm -rf "$e"
      echo "removed mirror dir: $name"
    else
      echo "STOP: $name is a real dir with non-symlink files — pass --force to delete"
    fi
  fi
done
echo "uninstall complete."
