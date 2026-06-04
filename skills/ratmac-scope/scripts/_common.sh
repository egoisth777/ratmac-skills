#!/usr/bin/env bash
# _common.sh — POSIX shadow engine for ratmac-* skills (R4 parity). Source it:
#   . "$(dirname "$0")/_common.sh"
# Pure bash + coreutils. No external deps. Writes only under scheduler/ (R5).

set -euo pipefail

# --- scheduler root resolution (RQ1) ----------------------------------------------
# Precedence: arg1 → RATMAC_SCHEDULER_ROOT → cwd ancestor walk (arca/scheduler,
# scheduler, or a dir holding p-* children).
ratmac_root() {  # arg1: optional explicit root. Echoes the scheduler root path.
  local root="${1:-}"
  if [ -n "$root" ]; then
    if [ -d "$root" ]; then ( cd "$root" && pwd ); return 0; fi
    echo "BLOCKED: -Root '$root' does not exist." >&2; return 1
  fi
  if [ -n "${RATMAC_SCHEDULER_ROOT:-}" ]; then ( cd "$RATMAC_SCHEDULER_ROOT" && pwd ); return 0; fi
  local dir; dir="$(pwd)"
  while [ -n "$dir" ]; do
    if [ -d "$dir/arca/scheduler" ]; then ( cd "$dir/arca/scheduler" && pwd ); return 0; fi
    if [ -d "$dir/scheduler" ]; then ( cd "$dir/scheduler" && pwd ); return 0; fi
    if [ "$(basename "$dir")" = "scheduler" ]; then printf '%s\n' "$dir"; return 0; fi
    if ls -d "$dir"/p-* >/dev/null 2>&1; then printf '%s\n' "$dir"; return 0; fi
    local parent; parent="$(dirname "$dir")"
    [ "$parent" = "$dir" ] && break
    dir="$parent"
  done
  echo "BLOCKED: cannot resolve scheduler root. Set arg1=<scheduler>, or RATMAC_SCHEDULER_ROOT, or run inside a scheduler tree." >&2
  return 1
}

# --- active project: echoes "ROOT\tPROJ\tPATH" ------------------------------------
ratmac_proj() {  # arg1: optional root; arg2: optional proj name
  local root="${1:-}" proj="${2:-}" sched
  sched="$(ratmac_root "$root")" || return 1
  if [ "$(basename "$sched")" != "${sched}" ] && case "$(basename "$sched")" in p-*) true;; *) false;; esac; then
    printf '%s\t%s\t%s\n' "$(dirname "$sched")" "$(basename "$sched")" "$sched"; return 0
  fi
  local dirs=(); local d
  for d in "$sched"/p-*; do [ -d "$d" ] && dirs+=("$d"); done
  if [ -n "$proj" ]; then
    for d in "${dirs[@]:-}"; do
      [ -n "$d" ] || continue
      if [ "$(basename "$d")" = "$proj" ]; then printf '%s\t%s\t%s\n' "$sched" "$proj" "$d"; return 0; fi
    done
    echo "BLOCKED: project '$proj' not found under $sched" >&2; return 1
  fi
  if [ "${#dirs[@]}" -eq 1 ]; then
    printf '%s\t%s\t%s\n' "$sched" "$(basename "${dirs[0]}")" "${dirs[0]}"; return 0
  fi
  local active=()
  for d in "${dirs[@]:-}"; do
    [ -n "$d" ] || continue
    if [ -f "$d/state.md" ] && [ "$(ratmac_fm_get "$d/state.md" status)" = "active" ]; then active+=("$d"); fi
  done
  if [ "${#active[@]}" -eq 1 ]; then
    printf '%s\t%s\t%s\n' "$sched" "$(basename "${active[0]}")" "${active[0]}"; return 0
  fi
  echo "BLOCKED: cannot pick active project under $sched. Pass arg2=<p-name>." >&2; return 1
}

# --- active slice path under a proj (echo path or empty) --------------------------
ratmac_active_slice() {  # arg1: proj path
  local pp="$1" d slices=()
  for d in "$pp"/s-*; do [ -d "$d" ] && [ "$(basename "$d")" != "archive" ] && slices+=("$d"); done
  [ "${#slices[@]}" -eq 0 ] && return 0
  if [ "${#slices[@]}" -eq 1 ]; then printf '%s\n' "${slices[0]}"; return 0; fi
  for d in "${slices[@]}"; do
    if [ -f "$d/state.md" ] && [ "$(ratmac_fm_get "$d/state.md" status)" = "active" ]; then printf '%s\n' "$d"; return 0; fi
  done
  return 0
}

# --- resolve a task ref to its grad/ dir (echo path or empty) ---------------------
ratmac_resolve_task() {  # arg1: slice path, arg2: task ref
  local sp="$1" t="$2" name
  name="$(basename "$t")"
  case "$name" in t-*) ;; *) name="t-$name" ;; esac
  [ -d "$sp/grad/$name" ] && printf '%s\n' "$sp/grad/$name"
  return 0
}

# --- proj mode -------------------------------------------------------------------
ratmac_mode() { ratmac_fm_get "$1/state.md" mode; }  # arg1: proj path

# --- timestamps -------------------------------------------------------------------
ratmac_stamp() { if [ -n "${1:-}" ]; then printf '%s' "$1"; else date '+%Y-%m-%d-%H:%M:%S'; fi; }
ratmac_id() {
  local ts="${1:-}"
  if [ -n "$ts" ]; then
    if printf '%s' "$ts" | grep -qE '^[0-9]{14}$'; then printf '%s' "$ts"; return; fi
    local d; d="$(printf '%s' "$ts" | tr -cd '0-9')"
    if [ "${#d}" -ge 14 ]; then printf '%s' "${d:0:14}"; return; fi
  fi
  date '+%Y%m%d%H%M%S'
}

# --- template expansion {{KEY}} ---------------------------------------------------
ratmac_expand() {  # arg1: template path; remaining: KEY=VALUE pairs
  local tpl="$1"; shift
  local text; text="$(cat "$tpl")"
  local pair k v
  for pair in "$@"; do
    k="${pair%%=*}"; v="${pair#*=}"
    text="${text//\{\{$k\}\}/$v}"
  done
  printf '%s' "$text"
}

# --- frontmatter scalar read (single key; tolerates GENERATED sentinel on line 1) --
ratmac_fm_get() {  # arg1: file, arg2: key
  local f="$1" key="$2"
  [ -f "$f" ] || return 0
  awk -v k="$key" '
    NR==1 && $0 ~ /<!--[[:space:]]*GENERATED/ {next}
    !seen && $0=="---" {seen=1; infm=1; next}
    infm && $0=="---" {exit}
    infm && $0 ~ "^"k":" { sub("^"k": *",""); print; exit }
  ' "$f" | sed 's/^"//; s/"$//'
}

# --- R9 concurrent-edit guard (twin of pwsh Assert-RatmacFresh) -------------------
# Snapshot a file's `time-modified` at read (via ratmac_fm_get), then call this just
# before the first mutating write. If the on-disk `time-modified` advanced past the
# snapshot (arg2), a hand-edit landed under us — STOP rather than clobber it (R9).
# Prints the HUMAN_DECISION_REQUIRED marker BEFORE the contract and exits 3. A missing
# file or empty snapshot is treated as fresh (returns 0, no stop). The fixed-width
# yyyy-MM-dd-HH:mm:ss / yyyyMMddHHmmss stamps compare correctly as strings, matching
# the pwsh [string]$cur -gt [string]$SeenTs test (R4 byte-parity).
ratmac_assert_fresh() {  # arg1: file path, arg2: seen time-modified snapshot
  local f="$1" seen="${2:-}" cur
  [ -n "$seen" ] || return 0
  [ -f "$f" ] || return 0
  cur="$(ratmac_fm_get "$f" time-modified)"
  [ -n "$cur" ] || return 0
  if [ "$cur" \> "$seen" ]; then
    echo "HUMAN_DECISION_REQUIRED concurrent edit: $f time-modified ($cur) advanced past read snapshot ($seen) — re-read and retry (R9)."
    exit 3
  fi
  return 0
}

# --- frontmatter scalar set (bump time-modified unless setting it) ----------------
ratmac_fm_set() {  # file, key, value, [ts]
  local f="$1" key="$2" val="$3" ts; ts="$(ratmac_stamp "${4:-}")"
  awk -v k="$key" -v v="$val" -v tm="$ts" '
    BEGIN{infm=0; closing=0; done=0}
    !opened && $0=="---" {opened=1; infm=1; print; next}
    infm && $0=="---" && !closing {
      if(!done){ print k": "v; done=1 }
      closing=1; print; next
    }
    infm && !closing && $0 ~ "^"k":" { print k": "v; done=1; next }
    infm && !closing && $0 ~ "^time-modified:" && k!="time-modified" { print "time-modified: "tm; next }
    {print}
  ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}

# --- append-only log line (S19) ---------------------------------------------------
ratmac_log() {  # logpath, verb, [args], [ts]
  local lp="$1" verb="$2" args="${3:-}" ts; ts="$(ratmac_stamp "${4:-}")"
  local line; if [ -n "$args" ]; then line="$ts $verb $args"; else line="$ts $verb"; fi
  if [ ! -f "$lp" ]; then
    mkdir -p "$(dirname "$lp")"
    printf -- '---\ntime-created: %s\ntime-modified: %s\n---\n\n%s\n' "$ts" "$ts" "$line" > "$lp"
    return 0
  fi
  printf '%s\n' "$line" >> "$lp"
  ratmac_fm_set "$lp" time-modified "$ts" "$ts"
}

# --- task ## affects dedupe-add (S18, RQ13) — echoes "added=N dup=M" --------------
ratmac_affects_add() {  # statepath, [ts], paths...
  local f="$1" ts="${2:-}"; shift 2
  local added=0 dup=0 p norm
  # ensure a "## affects" section exists
  if ! grep -qE '^##[[:space:]]+affects[[:space:]]*$' "$f"; then printf '\n## affects\n' >> "$f"; fi
  for p in "$@"; do
    norm="$(printf '%s' "$p" | tr '\\' '/' | sed 's/^ *//; s/ *$//')"
    [ -n "$norm" ] || continue
    # is it already a bullet under affects?
    if awk -v want="$norm" '
        /^##[[:space:]]+affects[[:space:]]*$/ {ina=1; next}
        ina && /^##[[:space:]]/ {ina=0}
        ina && /^[[:space:]]*-[[:space:]]/ { v=$0; sub(/^[[:space:]]*-[[:space:]]*/,"",v); if(v==want){found=1} }
        END{exit found?0:1}
      ' "$f"; then dup=$((dup+1)); continue; fi
    # append the bullet AFTER the last existing line of the affects section, i.e.
    # right before the next "## " heading (or at EOF). Matches pwsh insert-at-sec.End.
    awk -v want="$norm" '
      ina && !ins && /^##[[:space:]]/ { print "- " want; ins=1; ina=0 }
      {print}
      !ina && !ins && /^##[[:space:]]+affects[[:space:]]*$/ { ina=1 }
      END{ if(ina && !ins) print "- " want }
    ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    added=$((added+1))
  done
  [ -n "$ts" ] && ratmac_fm_set "$f" time-modified "$(ratmac_stamp "$ts")" "$ts"
  printf 'added=%s dup=%s\n' "$added" "$dup"
}

# --- read a section's bullet list (skip fence markers) ----------------------------
ratmac_affects_list() {  # arg1: file, arg2: section (default affects)
  local f="$1" sec="${2:-affects}"
  [ -f "$f" ] || return 0
  awk -v s="$sec" '
    $0 ~ "^##[[:space:]]+"s"[[:space:]]*$" {ina=1; next}
    ina && /^##[[:space:]]/ {ina=0}
    ina && /<!--/ {next}
    ina && /^[[:space:]]*-[[:space:]]/ { v=$0; sub(/^[[:space:]]*-[[:space:]]*/,"",v); sub(/[[:space:]]*$/,"",v); print v }
  ' "$f"
}

# --- GENERATED fence rewrite (S20, R10 idempotent) — returns 0 if changed, 1 if not -
# Single-pair rule: only the FIRST open->close pair is touched; later fences ignored
# (matches pwsh $g0/$g1). Unbalanced fence (open marker, no matching close): we do NOT
# delete past the missing close — that would truncate user data. We leave the dangling
# open in place and append a FRESH balanced fence at EOF, then write into it. This is
# the canonical rule, mirrored byte-for-byte with pwsh Set-RatmacFence.
ratmac_fence_set() {  # file, section, [ts], then body lines on stdin
  local f="$1" sec="${2:-affects}" ts="${3:-}"
  local newregion; newregion="$(cat)"
  newregion="${newregion%$'\n'}"
  local has; has="$(grep -c '<!--[[:space:]]*GENERATED[[:space:]]*-->' "$f" || true)"
  # is the FIRST open marker matched by a close? (balanced => closed=1)
  local closed; closed="$(awk '
    !opened && /<!--[[:space:]]*GENERATED[[:space:]]*-->/ { opened=1; next }
    opened && /<!--[[:space:]]*\/GENERATED[[:space:]]*-->/ { print "1"; found=1; exit }
    END { if(!found) print "0" }
  ' "$f")"
  # capture only the FIRST balanced GENERATED region (single-pair rule, matches pwsh)
  local oldregion
  oldregion="$(awk '
    !opened && /<!--[[:space:]]*GENERATED[[:space:]]*-->/ { opened=1; next }
    opened && !closed && /<!--[[:space:]]*\/GENERATED[[:space:]]*-->/ { closed=1; next }
    opened && !closed { print }
  ' "$f")"
  oldregion="${oldregion%$'\n'}"
  # idempotent only when a BALANCED fence already exists and its body matches; a fresh
  # or unbalanced-needs-append fence always writes (matches pwsh $created flag).
  if [ "$has" != "0" ] && [ "$closed" = "1" ] && [ "$oldregion" = "$newregion" ]; then return 1; fi
  local tmp="$f.tmp"
  if [ "$has" = "0" ]; then
    # no fence at all: ensure section heading exists, drop fence under it
    if ! grep -qE "^##[[:space:]]+$sec[[:space:]]*$" "$f"; then printf '\n## %s\n' "$sec" >> "$f"; fi
    awk -v sec="$sec" -v repl="$newregion" '
      {print}
      !ins && $0 ~ "^##[[:space:]]+"sec"[[:space:]]*$" {
        print "<!-- GENERATED -->"
        if (repl != "") print repl
        print "<!-- /GENERATED -->"
        ins=1
      }
    ' "$f" > "$tmp"
  elif [ "$closed" != "1" ]; then
    # unbalanced: open marker, no close. Leave the dangling open untouched and append
    # a fresh balanced fence at EOF (do NOT consume to EOF). Matches pwsh $g1<0 branch.
    cp "$f" "$tmp"
    [ -n "$(tail -c1 "$tmp")" ] && printf '\n' >> "$tmp"   # ensure trailing newline
    if [ -n "$newregion" ]; then
      printf '\n<!-- GENERATED -->\n%s\n<!-- /GENERATED -->\n' "$newregion" >> "$tmp"
    else
      printf '\n<!-- GENERATED -->\n<!-- /GENERATED -->\n' >> "$tmp"
    fi
  else
    # rewrite ONLY the first balanced GENERATED region (single-pair rule, matches pwsh)
    awk -v repl="$newregion" '
      done { print; next }
      !opened && /<!--[[:space:]]*GENERATED[[:space:]]*-->/ {
        print; opened=1
        if (repl != "") print repl
        next
      }
      opened && !closed_seen && /<!--[[:space:]]*\/GENERATED[[:space:]]*-->/ {
        closed_seen=1; done=1; print; next
      }
      opened && !closed_seen && !done { next }   # drop old first-region body
      { print }
    ' "$f" > "$tmp"
  fi
  mv "$tmp" "$f"
  [ -n "$ts" ] && ratmac_fm_set "$f" time-modified "$(ratmac_stamp "$ts")" "$ts"
  return 0
}

# --- slice ## tasks table upsert --------------------------------------------------
ratmac_task_row() {  # slicestate, task, issue, sprint, status, [ts]
  local f="$1" task="$2" issue="${3:-—}" sprint="${4:-—}" status="$5" ts="${6:-}"
  local name="$task"; case "$name" in t-*) ;; *) name="t-$name" ;; esac
  [ -n "$issue" ] || issue="—"; [ -n "$sprint" ] || sprint="—"
  local row="| [[$name]] | $issue | $sprint | $status |"
  if ! grep -qE '^##[[:space:]]+tasks[[:space:]]*$' "$f"; then
    printf '\n## tasks\n| task | issue | sprint | status |\n|---|---|---|---|\n' >> "$f"
  elif ! grep -qE '^\|[[:space:]]*task[[:space:]]*\|' "$f"; then
    awk '
      {print}
      !ins && /^##[[:space:]]+tasks[[:space:]]*$/ { print "| task | issue | sprint | status |"; print "|---|---|---|---|"; ins=1 }
    ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  fi
  if grep -qE "\[\[$name\]\]" "$f"; then
    awk -v name="$name" -v row="$row" '
      $0 ~ "\\[\\["name"\\]\\]" { print row; next }
      { print }
    ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  else
    awk -v row="$row" '
      /^##[[:space:]]+tasks[[:space:]]*$/ {intab=1}
      intab && /^##[[:space:]]/ && !/tasks/ && started { print row; intab=0; started=0 }
      intab && /^\|/ {started=1}
      intab && started && !/^\|/ { print row; intab=0; started=0 }
      {print}
      END{ if(intab && started) print row }
    ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  fi
  [ -n "$ts" ] && ratmac_fm_set "$f" time-modified "$(ratmac_stamp "$ts")" "$ts"
}

# --- scheduler-relative display path ----------------------------------------------
ratmac_relpath() {  # abspath, root
  local p="$1" r; r="$(dirname "$2")"
  case "$p" in "$r"/*) printf '%s' "${p#"$r"/}";; *) printf '%s' "$p";; esac
}

# --- uniform contract (R7) --------------------------------------------------------
# KEY=VALUE pairs → fenced contract block. Field order is engine-enforced: incoming
# pairs are emitted in the canonical key order (matching pwsh Write-RatmacContract),
# not in caller order. Keys absent from input are skipped; non-canonical keys dropped.
ratmac_contract() {
  local order=('Run mode' 'Active proj' 'Active slice' 'Active task' 'Classification' 'Skill chain' \
               'Files touched' 'Files generated' 'Lint result' 'Regen result' \
               'Open questions' 'Human decisions required' 'Blocked items' 'Next safe action' 'Residual risk')
  echo '```contract'
  local k pair key val have
  for k in "${order[@]}"; do
    have=0; val=''
    for pair in "$@"; do
      key="${pair%%=*}"
      if [ "$key" = "$k" ]; then val="${pair#*=}"; have=1; fi   # last occurrence wins
    done
    [ "$have" -eq 1 ] && printf '%s: %s\n' "$k" "$val"
  done
  echo '```'
}

ratmac_tpl_dir() { echo "$(dirname "$(dirname "$1")")/templates"; }  # arg1: script path
