#!/usr/bin/env bash
#
# delegate.sh - invoke another agent harness headlessly, with worktree isolation.
#
#   delegate.sh list
#   delegate.sh run --harness <h> --mode review --prompt-file <f> [--model M]
#   delegate.sh run --harness <h> --mode build --prompt-file <f> --task-id <slug> [--base REF] [--model M]
#   delegate.sh collect <task-id>
#   delegate.sh clean <task-id>
#
# Exit codes:
#   0  harness ran to completion  (does NOT mean the task succeeded)
#   1  harness exited non-zero
#   2  precondition failed (unknown/uninstalled harness, ineligible mode, not a git repo)
#
# Bash 3.2 compatible (macOS system bash). No jq dependency.

set -euo pipefail

HARNESSES="pi opencode codex gemini crush aider"

die() { printf 'delegate: %s\n' "$1" >&2; exit "${2:-2}"; }

usage() { sed -n '3,15p' "$0" | sed 's/^#\{1\} \{0,1\}//'; }

repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || die "not inside a git repository"
}

harness_installed() { command -v "$1" >/dev/null 2>&1; }

# Read-only enforcement tier: enforced | configured | none
#   enforced   - the harness itself refuses writes (sandbox / approval policy)
#   configured - restriction comes from agent config, weaker but real
#   none       - no read-only mode exists; ineligible for review
review_tier() {
  case "$1" in
    codex|gemini|pi) echo enforced ;;
    opencode)        echo configured ;;
    crush|aider)     echo none ;;
    *)               echo unknown ;;
  esac
}

known_harness() {
  case " $HARNESSES " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

# ---------------------------------------------------------------- list

cmd_list() {
  printf '%-10s %-11s %-20s %s\n' HARNESS INSTALLED REVIEW BUILD
  for h in $HARNESSES; do
    tier=$(review_tier "$h")
    if harness_installed "$h"; then
      if [ "$tier" = none ]; then rev="no (unenforced)"; else rev="yes ($tier)"; fi
      bld=yes
      inst=yes
    else
      inst=no; rev="-"; bld="-"
    fi
    printf '%-10s %-11s %-20s %s\n' "$h" "$inst" "$rev" "$bld"
  done
}

# ---------------------------------------------------------------- run

cmd_run() {
  harness=""; mode=""; prompt_file=""; task_id=""; base="HEAD"; model=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --harness)     harness=$2; shift 2 ;;
      --mode)        mode=$2; shift 2 ;;
      --prompt-file) prompt_file=$2; shift 2 ;;
      --task-id)     task_id=$2; shift 2 ;;
      --base)        base=$2; shift 2 ;;
      --model)       model=$2; shift 2 ;;
      *)             die "unknown flag: $1" ;;
    esac
  done

  [ -n "$harness" ] || die "--harness is required"
  [ -n "$mode" ] || die "--mode is required (review|build)"
  [ -n "$prompt_file" ] || die "--prompt-file is required"
  [ -f "$prompt_file" ] || die "prompt file not found: $prompt_file"
  known_harness "$harness" || die "unknown harness: $harness"
  harness_installed "$harness" || die "$harness is not installed"

  case "$mode" in
    review)
      if [ "$(review_tier "$harness")" = none ]; then
        die "$harness has no read-only enforcement and is ineligible for review mode"
      fi
      if [ -z "$task_id" ]; then
        task_id="review-$(date +%Y%m%d-%H%M%S)-$harness"
      fi
      ;;
    build)
      [ -n "$task_id" ] || die "--task-id is required for build mode"
      ;;
    *) die "mode must be review or build" ;;
  esac

  root=$(repo_root)
  run_dir="$root/.delegates/runs/$task_id"
  mkdir -p "$run_dir"
  cp "$prompt_file" "$run_dir/prompt.md"
  prompt=$(cat "$run_dir/prompt.md")
  result_file="$run_dir/result.txt"
  : >"$result_file"

  if [ "$mode" = build ]; then
    wt="$root/.delegates/worktrees/$task_id"
    branch="delegate/$task_id"
    if git -C "$root" rev-parse --verify --quiet "$branch" >/dev/null 2>&1; then
      die "branch $branch already exists; pick another --task-id or delete it"
    fi
    base_sha=$(git -C "$root" rev-parse "$base" 2>/dev/null) ||
      die "cannot resolve base ref: $base"
    git -C "$root" worktree add -b "$branch" "$wt" "$base_sha" >/dev/null ||
      die "failed to create worktree at $wt"
    workdir="$wt"
  else
    base_sha=$(git -C "$root" rev-parse HEAD 2>/dev/null || echo "")
    workdir="$PWD"
  fi

  # Build argv directly in the positional params. Never round-trip through a
  # file or a string: prompts are multi-line and would be split on newlines.
  # Flags precede the prompt so the prompt is unambiguously the positional.
  set --
  case "$harness:$mode" in
    codex:review)    set -- codex exec -s read-only -o "$result_file" ;;
    codex:build)     set -- codex exec -s workspace-write -o "$result_file" ;;
    # gemini: without --skip-trust it silently downgrades --approval-mode to
    # "default" ("folder is not trusted") and then blocks on approval prompts.
    gemini:review)   set -- gemini --skip-trust --approval-mode plan ;;
    gemini:build)    set -- gemini --skip-trust --approval-mode auto_edit ;;
    # pi review allowlists read-only tools. `bash` is deliberately excluded:
    # a shell is a write primitive.
    pi:review)       set -- pi -p -t read,grep,find,ls ;;
    pi:build)        set -- pi -p ;;
    opencode:review) set -- opencode run --agent plan ;;
    opencode:build)  set -- opencode run --auto ;;
    # crush: `run` already auto-approves in non-interactive mode. --yolo is
    # rejected by the `run` subcommand in every position (it is interactive-only),
    # so it must NOT be passed here.
    crush:build)     set -- crush run --quiet ;;
    # aider: --auto-commits defaults to True, so disable it explicitly.
    # --no-check-update stops aider self-upgrading and exiting 0 without working.
    # History files are redirected out of the worktree so they never pollute the diff.
    # --no-gitignore stops aider adding its own .gitignore entries to the diff.
    aider:build)     set -- aider --yes-always --no-auto-commits --no-check-update --no-gitignore \
                       --chat-history-file "$run_dir/aider.chat.md" \
                       --input-history-file "$run_dir/aider.input.md" ;;
    *)               die "$harness does not support mode '$mode'" ;;
  esac

  if [ -n "$model" ]; then
    set -- "$@" --model "$model"
  fi

  # How the prompt is delivered differs: aider reads it from a file, gemini
  # takes it behind -p, everything else takes it as a trailing positional.
  case "$harness" in
    aider)  set -- "$@" --message-file "$run_dir/prompt.md" ;;
    gemini) set -- "$@" -p "$prompt" ;;
    *)      set -- "$@" "$prompt" ;;
  esac

  printf -- '-> %s [%s] in %s\n' "$harness" "$mode" "$workdir" >&2

  # stdin MUST be /dev/null. Several harnesses (codex exec confirmed) detect a
  # non-TTY stdin and block forever waiting to append piped input to the prompt,
  # even when the prompt was already supplied on argv. Closing stdin is the only
  # reliable way to keep a headless run headless.
  rc=0
  ( cd "$workdir" && "$@" ) </dev/null >"$run_dir/stdout.log" 2>"$run_dir/stderr.log" || rc=$?

  # Every harness except codex (which was given -o) reports on stdout.
  if [ ! -s "$result_file" ]; then
    cp "$run_dir/stdout.log" "$result_file"
  fi

  cat >"$run_dir/meta.json" <<EOF
{
  "task_id": "$task_id",
  "harness": "$harness",
  "mode": "$mode",
  "model": "$model",
  "base_sha": "$base_sha",
  "workdir": "$workdir",
  "exit_code": $rc
}
EOF

  printf 'run dir: %s\n' "$run_dir" >&2
  if [ "$rc" -ne 0 ]; then
    printf 'harness exited %s; see %s/stderr.log\n' "$rc" "$run_dir" >&2
    exit 1
  fi
}

# ---------------------------------------------------------------- collect

json_field() { sed -n "s/.*\"$2\": *\"\([^\"]*\)\".*/\1/p" "$1"; }

cmd_collect() {
  task_id=${1:-}; [ -n "$task_id" ] || die "usage: delegate.sh collect <task-id>"
  root=$(repo_root)
  run_dir="$root/.delegates/runs/$task_id"
  [ -d "$run_dir" ] || die "no such run: $task_id"

  base_sha=$(json_field "$run_dir/meta.json" base_sha)
  mode=$(json_field "$run_dir/meta.json" mode)
  wt="$root/.delegates/worktrees/$task_id"

  if [ "$mode" = build ] && [ -d "$wt" ]; then
    # Stage everything so uncommitted AND untracked delegate output land in the
    # diff. The worktree is disposable, so mutating its index is harmless.
    git -C "$wt" add -A
    git -C "$wt" diff --cached "$base_sha" >"$run_dir/diff.patch"
    commits=$(git -C "$wt" rev-list --count "$base_sha"..HEAD 2>/dev/null || echo 0)
    files=$(git -C "$wt" diff --cached --name-only "$base_sha" | wc -l | tr -d ' ')
    printf 'task:    %s\n' "$task_id"
    printf 'harness: %s\n' "$(json_field "$run_dir/meta.json" harness)"
    printf 'commits: %s\n' "$commits"
    printf 'files:   %s\n' "$files"
    printf 'branch:  delegate/%s\n' "$task_id"
    printf 'diff:    %s\n' "$run_dir/diff.patch"
    printf 'result:  %s   <- a CLAIM, not evidence\n' "$run_dir/result.txt"
    printf '\nchanged files:\n'
    git -C "$wt" diff --cached --name-status "$base_sha"
  else
    printf 'task:    %s (review)\n' "$task_id"
    printf 'harness: %s\n' "$(json_field "$run_dir/meta.json" harness)"
    printf 'result:  %s\n' "$run_dir/result.txt"
  fi
}

# ---------------------------------------------------------------- clean

cmd_clean() {
  task_id=${1:-}; [ -n "$task_id" ] || die "usage: delegate.sh clean <task-id>"
  root=$(repo_root)
  wt="$root/.delegates/worktrees/$task_id"
  if [ ! -d "$wt" ]; then
    printf 'no worktree for %s\n' "$task_id"
    return 0
  fi
  # Worktree removal is known to fail on non-empty dirs and on repos with
  # submodules; fall back to a manual rm plus prune.
  if ! git -C "$root" worktree remove --force "$wt" 2>/dev/null; then
    rm -rf "$wt"
    git -C "$root" worktree prune
  fi
  printf 'removed worktree %s (branch delegate/%s kept)\n' "$wt" "$task_id"
}

# ---------------------------------------------------------------- dispatch

cmd=${1:-}
if [ $# -gt 0 ]; then shift; fi
case "$cmd" in
  list)    cmd_list "$@" ;;
  run)     cmd_run "$@" ;;
  collect) cmd_collect "$@" ;;
  clean)   cmd_clean "$@" ;;
  -h|--help|help|"") usage ;;
  *)       die "unknown command: $cmd" ;;
esac
