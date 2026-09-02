#!/usr/bin/env bash
#
# asset-inventory.sh — track the material that deliberately does NOT sync.
#
#   asset-inventory.sh scan       inventory this machine, write assets/<machine>.tsv
#   asset-inventory.sh diff       compare this machine against the other(s)
#   asset-inventory.sh plan       emit an rsync file-list and command for the gap
#   asset-inventory.sh discover   find large ignored files not covered by a root
#
# THE IDEA: sync the index, not the assets.
#
# Recordings, ROM dumps, frozen downloads and archives are deliberately excluded
# from git — they are large, they do not diff, and git would keep them forever.
# But nothing told you *what* was missing where, so the manual copy never
# happened, because you never saw the list. The inventories are small text files
# committed to ~/dev, so they ride the sync that already works, and the assets
# stay exactly where they are.
#
# OPT-IN BY ROOT, deliberately. A naive "list everything git ignores" scan is
# mostly build output — .app bundles, .o and .elf files, node_modules — which you
# should rebuild, not copy. So `scan` reads assets/scan-paths.tsv, and `discover`
# separately proposes large ignored files you might want to add to it.

set -uo pipefail

DEV="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
ASSETS="$DEV/assets"
ROOTS="$ASSETS/scan-paths.tsv"
MIN_MB="${MIN_MB:-1}"                       # ignore anything smaller than this
DISCOVER_MIN_MB="${DISCOVER_MIN_MB:-10}"    # `discover` is deliberately louder

# Build output and package caches: never worth hand-copying.
DENY='/(node_modules|\.build|\.next|\.venv|__pycache__|dist|build|Debug|Release|target|\.git|.*\.app)/|\.(o|d|elf|su|cyclo|lst|map|dSYM|pyc)$|\.DS_Store$'

machine_slug() {
  local n; n="$(scutil --get ComputerName 2>/dev/null || hostname -s 2>/dev/null || echo unknown)"
  printf '%s\n' "$n" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]\{1,\}/-/g; s/^-//; s/-$//'
}

MINE="$ASSETS/$(machine_slug).tsv"

# BSD stat (macOS) spells these -f%z/-f%m; GNU stat (Linux) spells them
# -c%s/-c%Y and rejects -f outright. Probed once against a file that is always
# present rather than sniffed from `uname`, so a BSD-flavoured Linux or a box
# with GNU coreutils installed over the top gets the right answer either way.
#
# This matters more than it looks: every caller ends in `|| continue`, so the
# wrong flag does not fail loudly — it skips every file and reports an empty
# inventory. An inventory whose whole job is saying what lives only on the other
# machine would then quietly claim this machine holds nothing.
if stat -f%z "${BASH_SOURCE[0]}" >/dev/null 2>&1; then
  STAT_SIZE='-f%z'; STAT_MTIME='-f%m'
elif stat -c%s "${BASH_SOURCE[0]}" >/dev/null 2>&1; then
  STAT_SIZE='-c%s'; STAT_MTIME='-c%Y'
else
  echo "error: neither BSD nor GNU stat understood here — cannot size files" >&2
  exit 1
fi
fsize()  { stat "$STAT_SIZE"  "$1" 2>/dev/null; }
fmtime() { stat "$STAT_MTIME" "$1" 2>/dev/null; }

human() { # human <bytes>
  awk -v b="$1" 'BEGIN{
    split("B K M G T",u," ");i=1
    while(b>=1024 && i<5){b/=1024;i++}
    printf (i==1 ? "%d%s\n" : "%.1f%s\n"), b, u[i]
  }'
}

seed_roots() {
  [ -f "$ROOTS" ] && return 0
  mkdir -p "$ASSETS" 2>/dev/null || return 1
  cat > "$ROOTS" <<'EOF'
# scan-paths.tsv — directories whose contents do NOT sync through git, and which
# therefore have to be copied between machines by hand. One path per line,
# relative to ~/dev. Comments and blank lines ignored.
#
# Opt-in on purpose: listing everything git ignores would mostly list build
# output, which you rebuild rather than copy. Use `asset-inventory.sh discover`
# to find large ignored files worth adding here.
#
# NOT worth listing: reference/ and vendor/ clones (they are git repos, recorded
# in repos.tsv, and bootstrap.sh clones them), or anything a build produces.

other
archive
EOF
  echo "  seeded $ROOTS"
}

# ---------------------------------------------------------------------------
# scan
# ---------------------------------------------------------------------------
cmd_scan() {
  seed_roots
  local min_bytes=$((MIN_MB * 1024 * 1024)) n=0 total=0
  local tmp; tmp="$(mktemp)" || return 1

  while read -r root; do
    case "$root" in ''|\#*) continue ;; esac
    [ -d "$DEV/$root" ] || continue
    while IFS= read -r f; do
      local rel="${f#"$DEV"/}"
      printf '%s\n' "$rel" | grep -qE "$DENY" && continue
      local sz mt
      sz="$(fsize "$f")" || continue
      [ "${sz:-0}" -ge "$min_bytes" ] || continue
      mt="$(fmtime "$f" || echo 0)"
      printf '%s\t%s\t%s\n' "$rel" "$sz" "$mt" >> "$tmp"
      n=$((n+1)); total=$((total+sz))
    done < <(find "$DEV/$root" -type f 2>/dev/null)
  done < "$ROOTS"

  mkdir -p "$ASSETS" 2>/dev/null
  { printf '# path\tbytes\tmtime   — %s, %s files >= %sM, %s total\n' \
      "$(machine_slug)" "$n" "$MIN_MB" "$(human "$total")"
    sort "$tmp" 2>/dev/null; } > "$MINE"
  rm -f "$tmp"

  echo "  wrote ${MINE#"$DEV"/}  ($n files, $(human "$total"))"
  echo "  commit it and it reaches the other machine by itself"
}

# ---------------------------------------------------------------------------
# diff — both directions, against every other inventory present
# ---------------------------------------------------------------------------
rows() { grep -v '^#' "$1" 2>/dev/null | cut -f1,2; }

cmd_diff() {
  [ -f "$MINE" ] || { echo "  no inventory for this machine yet — run: asset-inventory.sh scan"; return 0; }
  local other found=0
  shopt -s nullglob
  for other in "$ASSETS"/*.tsv; do
    [ "$other" = "$MINE" ] && continue
    [ "$other" = "$ROOTS" ] && continue
    found=1
    local name; name="$(basename "$other" .tsv)"
    echo
    echo "vs $name"

    local only_there only_here
    only_there="$(comm -13 <(rows "$MINE" | sort) <(rows "$other" | sort) | cut -f1 | sort -u)"
    only_here="$(comm -23 <(rows "$MINE" | sort) <(rows "$other" | sort) | cut -f1 | sort -u)"

    if [ -n "$only_there" ]; then
      local c b; c="$(printf '%s\n' "$only_there" | wc -l | tr -d ' ')"
      # The wanted paths go in as a file, not as -v: awk rejects a -v value
      # containing newlines ("newline in string"), and every path here is a
      # line. Reading them as FNR==NR also leaves spaces in names alone.
      b="$(awk -F'\t' '
        NR==FNR{want[$0]=1; next}
        /^#/{next}
        want[$1]{s+=$2} END{print s+0}' <(printf '%s\n' "$only_there") "$other")"
      echo "  on $name but NOT here:  $c file(s), $(human "$b")"
      printf '%s\n' "$only_there" | sed 's/^/    /' | head -20
      [ "$c" -gt 20 ] && echo "    ...and $((c - 20)) more"
    fi
    if [ -n "$only_here" ]; then
      local c; c="$(printf '%s\n' "$only_here" | wc -l | tr -d ' ')"
      echo "  here but NOT on $name:  $c file(s)"
      printf '%s\n' "$only_here" | sed 's/^/    /' | head -20
      [ "$c" -gt 20 ] && echo "    ...and $((c - 20)) more"
    fi
    [ -z "$only_there" ] && [ -z "$only_here" ] && echo "  identical"
  done
  [ "$found" = "0" ] && echo "  no other machine's inventory here yet — it arrives with the next ~/dev pull"
  return 0
}

# ---------------------------------------------------------------------------
# plan — make acting on the gap a paste, not a project
# ---------------------------------------------------------------------------
cmd_plan() {
  [ -f "$MINE" ] || { echo "  run scan first"; return 0; }
  local other found=0
  shopt -s nullglob
  for other in "$ASSETS"/*.tsv; do
    [ "$other" = "$MINE" ] && continue
    [ "$other" = "$ROOTS" ] && continue
    found=1
    local name host pull push
    name="$(basename "$other" .tsv)"
    host="$name.local"          # mDNS guess; edit if your LAN disagrees
    pull="$ASSETS/pull-from-$name.txt"
    push="$ASSETS/push-to-$name.txt"

    comm -13 <(rows "$MINE" | cut -f1 | sort) <(rows "$other" | cut -f1 | sort) > "$pull"
    comm -23 <(rows "$MINE" | cut -f1 | sort) <(rows "$other" | cut -f1 | sort) > "$push"

    echo
    if [ -s "$pull" ]; then
      echo "to pull $(wc -l < "$pull" | tr -d ' ') file(s) from $name, run HERE:"
      echo "  rsync -av --files-from=\"$pull\" \"$host:$DEV/\" \"$DEV/\""
    fi
    if [ -s "$push" ]; then
      echo "to push $(wc -l < "$push" | tr -d ' ') file(s) to $name, run HERE:"
      echo "  rsync -av --files-from=\"$push\" \"$DEV/\" \"$host:$DEV/\""
    fi
    [ -s "$pull" ] || [ -s "$push" ] || { echo "nothing to move for $name"; rm -f "$pull" "$push"; }
  done
  [ "$found" = "0" ] && echo "  no other inventory to plan against yet"
  echo
  echo "  the file lists are plain text — read or trim them before running anything"
  return 0
}

# ---------------------------------------------------------------------------
# discover — large ignored files that no root covers
# ---------------------------------------------------------------------------
cmd_discover() {
  seed_roots
  local min_bytes=$((DISCOVER_MIN_MB * 1024 * 1024)) n=0
  echo "large ignored files (>= ${DISCOVER_MIN_MB}M) outside any scanned root:"
  while read -r path; do
    case "$path" in ''|\#*|.) continue ;; esac
    [ -d "$DEV/$path/.git" ] || continue
    while IFS= read -r f; do
      local full="$DEV/$path/$f" rel="$path/$f"
      [ -f "$full" ] || continue
      printf '%s\n' "$rel" | grep -qE "$DENY" && continue
      # already covered by a scanned root?
      local covered=0 root
      while read -r root; do
        case "$root" in ''|\#*) continue ;; esac
        case "$rel" in "$root"/*) covered=1; break ;; esac
      done < "$ROOTS"
      [ "$covered" = "1" ] && continue
      local sz; sz="$(fsize "$full")" || continue
      [ "${sz:-0}" -ge "$min_bytes" ] || continue
      printf '  %-8s %s\n' "$(human "$sz")" "$rel"
      n=$((n+1))
    done < <(git -C "$DEV/$path" ls-files --others --ignored --exclude-standard 2>/dev/null)
  done < <(awk -F'\t' '$1!~/^#/ && $1!="" && $2=="mine" {print $1}' "$DEV/repos.tsv" 2>/dev/null)

  if [ "$n" = "0" ]; then
    echo "  none"
  else
    echo
    echo "  add any of these directories to ${ROOTS#"$DEV"/} to track them,"
    echo "  or ignore this list — build output belongs on neither machine's inventory"
  fi
  return 0
}

case "${1:-diff}" in
  scan)     cmd_scan ;;
  diff)     cmd_diff ;;
  plan)     cmd_plan ;;
  discover) cmd_discover ;;
  *) echo "usage: asset-inventory.sh {scan|diff|plan|discover}" >&2; exit 1 ;;
esac

exit 0
