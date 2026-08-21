#!/usr/bin/env bash
#
# install-agents.sh - link this plugin's agents into other harnesses.
#
#   scripts/install-agents.sh --list
#   scripts/install-agents.sh --harness pi|gemini|codex|all
#   scripts/install-agents.sh --harness pi --uninstall
#
# Claude Code needs nothing: it auto-discovers the plugin's agents/ directory.
# The others only look in their own config dirs, so the generated wrappers are
# SYMLINKED there -- a plugin update then propagates with no re-install.
#
# Exit codes: 0 ok · 2 bad usage / missing generated files

set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd -P)
GEN="$ROOT/generated/agents"

die() { printf 'install-agents: %s\n' "$1" >&2; exit 2; }

# User-scope agent directory per harness. Verified on this machine from each
# harness's own docs/CLI, not guessed.
target_dir() {
  case "$1" in
    pi)     echo "$HOME/.pi/agent/agents" ;;   # docs: ~/.pi/agent/agents/**/*.md
    gemini) echo "$HOME/.gemini/agents" ;;     # docs: ~/.gemini/agents
    codex)  echo "$HOME/.codex/agents" ;;      # docs: ~/.codex/agents
    *)      die "unknown harness: $1" ;;
  esac
}
ext() { case "$1" in codex) echo toml ;; *) echo md ;; esac; }

cmd_list() {
  printf '%-8s %-34s %s\n' HARNESS 'AGENT DIR' STATUS
  printf '%-8s %-34s %s\n' claude '(plugin auto-discovery)' 'native, nothing to install'
  for h in pi gemini codex; do
    d=$(target_dir "$h"); e=$(ext "$h")
    if [ -d "$d" ]; then
      # count symlinks that point back into our generated tree
      n=$(find "$d" -maxdepth 1 -name "*.$e" -type l -lname "$GEN/*" 2>/dev/null | wc -l | tr -d ' ')
      st="$n linked"
    else
      st="dir absent (harness not configured)"
    fi
    printf '%-8s %-34s %s\n' "$h" "$(printf "%s" "$d" | sed "s#^$HOME#~#")" "$st"
  done
}

cmd_install() {
  h=$1 undo=$2
  [ -d "$GEN/$h" ] || die "no generated agents for $h -- run scripts/sync-agents.sh first"
  d=$(target_dir "$h"); e=$(ext "$h")
  mkdir -p "$d"
  n=0
  for f in "$GEN/$h"/*."$e"; do
    [ -e "$f" ] || continue
    base=$(basename "$f"); link="$d/$base"
    if [ "$undo" = yes ]; then
      # Only ever remove OUR symlinks. A real file at that path is someone
      # else's agent and must not be touched.
      if [ -L "$link" ]; then
        case "$(readlink "$link")" in "$GEN"/*) rm -f "$link"; n=$((n+1)) ;; esac
      fi
      continue
    fi
    if [ -e "$link" ] && [ ! -L "$link" ]; then
      printf '  SKIP %s (a real file exists there -- not overwriting)\n' "$base" >&2
      continue
    fi
    ln -sfn "$f" "$link"; n=$((n+1))
  done
  if [ "$undo" = yes ]; then printf 'unlinked %s agents from %s\n' "$n" "$d"
  else printf 'linked %s agents into %s\n' "$n" "$d"; fi
}

harness=""; undo=no
while [ $# -gt 0 ]; do
  case "$1" in
    --list)      cmd_list; exit 0 ;;
    --harness)   [ $# -ge 2 ] || die "missing value for --harness"; harness=$2; shift 2 ;;
    --uninstall) undo=yes; shift ;;
    -h|--help)   sed -n '3,10p' "$0" | sed 's/^#\{1\} \{0,1\}//'; exit 0 ;;
    *)           die "unknown flag: $1" ;;
  esac
done
[ -n "$harness" ] || { cmd_list; exit 0; }
if [ "$harness" = all ]; then for h in pi gemini codex; do cmd_install "$h" "$undo"; done
else cmd_install "$harness" "$undo"; fi
