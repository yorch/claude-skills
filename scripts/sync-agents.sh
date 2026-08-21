#!/usr/bin/env bash
#
# sync-agents.sh - generate per-harness agent definitions from agents/*.md
#
#   scripts/sync-agents.sh            regenerate generated/agents/<harness>/
#   scripts/sync-agents.sh --check    verify generated files are up to date (CI)
#
# agents/*.md (Claude Code format) is the single source of truth. Everything
# under generated/agents/ is generated -- never edit it by hand.
#
# Exit codes: 0 ok · 1 --check found drift · 2 bad input (unmappable tool)

set -euo pipefail

cd "$(dirname "$0")/.."
SRC=agents
GEN=generated/agents
HARNESSES="pi gemini codex"

die() { printf 'sync-agents: %s\n' "$1" >&2; exit "${2:-2}"; }

# Map a Claude Code tool name to a harness's vocabulary.
#
# An unmappable name is a HARD ERROR, not a warning. Verified behaviour: pi
# given a foreign allowlist grants no tools, then exits 0 with empty output --
# so a mis-mapped reviewer returns an empty review, and the orchestrator
# synthesises six empty sections into a clean bill of health. Silent
# fail-closed is more dangerous here than a build break.
map_tool() {
  case "$2:$1" in
    pi:Read)      echo read ;;
    pi:Grep)      echo grep ;;
    pi:Glob)      echo find,ls ;;
    pi:Bash)      echo bash ;;
    pi:Edit)      echo edit ;;
    pi:Write)     echo write ;;
    gemini:Read)  echo read_file,read_many_files ;;
    gemini:Grep)  echo grep_search ;;
    gemini:Glob)  echo glob,list_directory ;;
    gemini:Bash)  echo run_shell_command ;;
    gemini:Edit)  echo replace ;;
    gemini:Write) echo write_file ;;
    *)            die "no $2 mapping for Claude tool '$1' (add it to map_tool)" ;;
  esac
}

fm()   { sed -n '1,/^---$/{ /^---$/d; p; }' "$1" | sed -n "1,/^$/p"; }
field() { sed -n "s/^$2:[[:space:]]*//p" "$1" | head -1; }
body() { awk 'c==2{print} /^---$/{c++}' "$1"; }

gen_one() {
  src=$1 harness=$2
  name=$(field "$src" name)
  desc=$(field "$src" description)
  tools=$(field "$src" tools)
  [ -n "$name" ] || die "$src has no name:"

  out_dir="$GEN/$harness"; mkdir -p "$out_dir"

  case "$harness" in
    pi|gemini)
      mapped=""
      IFS=',' read -r -a arr <<< "$(printf '%s' "$tools" | tr -d ' ')"
      for t in "${arr[@]}"; do
        [ -z "$t" ] && continue
        m=$(map_tool "$t" "$harness")
        mapped="${mapped:+$mapped,}$m"
      done
      {
        echo "---"
        echo "name: $name"
        echo "description: $desc"
        echo "tools: $mapped"
        [ "$harness" = pi ] && { echo "systemPromptMode: replace"; echo "inheritProjectContext: true"; }
        echo "---"
        echo
        echo "<!-- GENERATED from $src by scripts/sync-agents.sh. Do not edit. -->"
        body "$src"
      } > "$out_dir/$name.md"
      ;;
    codex)
      # Codex has no tool allowlist; it uses a real sandbox, which is STRONGER
      # enforcement than omitting tools. Anything that can write gets
      # workspace-write; everything else is genuinely sandboxed read-only.
      case "$tools" in *Edit*|*Write*) sandbox=workspace-write ;; *) sandbox=read-only ;; esac
      {
        echo "# GENERATED from $src by scripts/sync-agents.sh. Do not edit."
        echo "name = \"$name\""
        printf 'description = "%s"\n' "$(printf '%s' "$desc" | sed 's/"/\\"/g')"
        echo "sandbox_mode = \"$sandbox\""
        echo 'developer_instructions = """'
        body "$src" | sed 's/\\/\\\\/g'
        echo '"""'
      } > "$out_dir/$name.toml"
      ;;
  esac
}

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
if [ "${1:-}" = --check ]; then cp -R "$GEN" "$tmp/before" 2>/dev/null || true; fi

rm -rf "$GEN"
count=0
for src in "$SRC"/*.md; do
  for h in $HARNESSES; do gen_one "$src" "$h"; done
  count=$((count+1))
done

if [ "${1:-}" = --check ]; then
  if ! diff -rq "$tmp/before" "$GEN" >/dev/null 2>&1; then
    die "generated agents are out of date -- run scripts/sync-agents.sh and commit" 1
  fi
  printf 'sync-agents: up to date (%s agents x %s harnesses)\n' "$count" "$(echo $HARNESSES | wc -w | tr -d ' ')"
else
  printf 'sync-agents: generated %s agents for: %s\n' "$count" "$HARNESSES"
fi
