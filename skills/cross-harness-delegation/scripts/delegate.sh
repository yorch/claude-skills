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

# Escape backslashes and double quotes so a path or task-id containing either
# cannot produce invalid JSON in meta.json -- the script's only state store.
json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# True only if $1 is the ROOT of a git worktree.
#
# This guard is load-bearing, not defensive clutter. `.delegates/worktrees/<id>`
# lives INSIDE the repo, so if that directory exists but is not a worktree --
# a partially failed `clean` (whose fallback is `rm -rf` + `prune`), or a
# hand-made directory -- then every `git -C "$wt" ...` silently resolves to the
# MAIN repo by walking up. `add -A` would then stage the user's own uncommitted
# work plus all of `.delegates/`, and the capture commit would land on their
# branch. Paths are normalized with `pwd -P` so symlinked roots still compare.
is_worktree_root() {
  _d=$(cd "$1" 2>/dev/null && pwd -P) || return 1
  _t=$(git -C "$_d" rev-parse --show-toplevel 2>/dev/null) || return 1
  _t=$(cd "$_t" 2>/dev/null && pwd -P) || return 1
  [ "$_d" = "$_t" ]
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
      --harness|--mode|--prompt-file|--task-id|--base|--model)
        # Guard the value explicitly: under `set -u` a trailing flag would
        # otherwise abort with "$2: unbound variable" and exit 1, which the
        # documented contract reserves for a harness failure.
        [ $# -ge 2 ] || die "missing value for $1"
        case "$1" in
          --harness)     harness=$2 ;;
          --mode)        mode=$2 ;;
          --prompt-file) prompt_file=$2 ;;
          --task-id)     task_id=$2 ;;
          --base)        base=$2 ;;
          --model)       model=$2 ;;
        esac
        shift 2 ;;
      *) die "unknown flag: $1" ;;
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
        # $$ disambiguates fan-out: date has 1s resolution, and two backgrounded
        # reviews of the same harness can easily start within the same second.
        task_id="review-$(date +%Y%m%d-%H%M%S)-$$-$harness"
      fi
      if [ "$(review_tier "$harness")" = configured ]; then
        printf 'delegate: WARNING: %s read-only is agent-config level, not sandbox-enforced.\n' "$harness" >&2
        printf 'delegate: it runs in the live tree (%s) and could write. Prefer codex/gemini/pi.\n' "$PWD" >&2
      fi
      ;;
    build)
      [ -n "$task_id" ] || die "--task-id is required for build mode"
      ;;
    *) die "mode must be review or build" ;;
  esac

  root=$(repo_root)
  run_dir="$root/.delegates/runs/$task_id"

  # Validate EVERYTHING that can fail before creating or touching any artifact.
  # Otherwise an aborted re-run (e.g. duplicate task-id) truncates the previous
  # run's result.txt and overwrites its prompt.md before failing -- destroying a
  # prior delegate's output via a command that ultimately did nothing.
  if [ "$mode" = build ]; then
    wt="$root/.delegates/worktrees/$task_id"
    branch="delegate/$task_id"
    if git -C "$root" rev-parse --verify --quiet "$branch" >/dev/null 2>&1; then
      die "branch $branch already exists; pick another --task-id or delete it"
    fi
    base_sha=$(git -C "$root" rev-parse "$base" 2>/dev/null) ||
      die "cannot resolve base ref: $base"
  else
    base_sha=$(git -C "$root" rev-parse HEAD 2>/dev/null || echo "")
  fi
  if [ -e "$run_dir" ]; then
    die "run artifacts already exist for task-id '$task_id'; pick another or remove $run_dir"
  fi

  mkdir -p "$run_dir"
  cp "$prompt_file" "$run_dir/prompt.md"
  prompt=$(cat "$run_dir/prompt.md")
  result_file="$run_dir/result.txt"
  : >"$result_file"

  if [ "$mode" = build ]; then
    git -C "$root" worktree add -b "$branch" "$wt" "$base_sha" >/dev/null ||
      die "failed to create worktree at $wt"
    workdir="$wt"
  else
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
    # auto_edit auto-approves edit tools ONLY -- shell/tool calls still prompt,
    # which deadlocks headlessly. Build briefs are required to run tests, so
    # yolo is the only workable setting. NOTE: a worktree bounds git state, not
    # the filesystem -- yolo can still run arbitrary commands anywhere. This is
    # weaker containment than codex's `-s workspace-write` sandbox.
    gemini:build)    set -- gemini --skip-trust --approval-mode yolo ;;
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
  "task_id": "$(json_escape "$task_id")",
  "harness": "$(json_escape "$harness")",
  "mode": "$(json_escape "$mode")",
  "model": "$(json_escape "$model")",
  "base_sha": "$(json_escape "$base_sha")",
  "workdir": "$(json_escape "$workdir")",
  "exit_code": $rc
}
EOF

  printf 'run dir: %s\n' "$run_dir" >&2
  if [ "$rc" -ne 0 ]; then
    printf 'harness exited %s; see %s/stderr.log\n' "$rc" "$run_dir" >&2
    # The run dir and (for build) the branch now exist, so re-running the same
    # --task-id is refused by the duplicate guards. Name the recovery, but lead
    # with the NON-destructive path: a harness that failed late may still have
    # produced real work, and the logs are often the point of a failed run.
    if [ "$mode" = build ]; then
      printf 'the worktree is intact -- a harness can fail late with real work already done.\n' >&2
      printf '  keep it:    delegate.sh collect %s     # commits whatever it produced\n' "$task_id" >&2
      printf '  retry:      use a different --task-id (cheapest, keeps this run)\n' >&2
      printf '  discard:    delegate.sh clean %s --force && git branch -D delegate/%s && rm -rf %s\n' \
        "$task_id" "$task_id" "$run_dir" >&2
      printf '              (--force DISCARDS uncommitted output; rm -rf deletes stderr.log)\n' >&2
    else
      printf '  retry: use a different --task-id, or rm -rf %s to reuse this one\n' "$run_dir" >&2
    fi
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

  harness=$(json_field "$run_dir/meta.json" harness)

  if [ "$mode" != build ]; then
    printf 'task:    %s (review)\n' "$task_id"
    printf 'harness: %s\n' "$harness"
    printf 'result:  %s\n' "$run_dir/result.txt"
    return 0
  fi

  # Build mode. If the worktree is already cleaned, the saved patch is all that
  # is left -- say so plainly rather than silently printing a review summary.
  if [ ! -d "$wt" ]; then
    printf 'task:    %s (build -- worktree already cleaned)\n' "$task_id"
    printf 'harness: %s\n' "$harness"
    printf 'branch:  delegate/%s\n' "$task_id"
    if [ -s "$run_dir/diff.patch" ]; then
      printf 'diff:    %s\n' "$run_dir/diff.patch"
      printf '\nThe worktree is gone; the diff above is the surviving evidence.\n'
    else
      printf 'diff:    (none)\n'
      printf '\nThe worktree is gone and no diff was ever captured -- either the\n'
      printf 'delegate changed nothing, or the run was discarded with clean --force.\n'
      printf 'Check "git log delegate/%s" before assuming work was done.\n' "$task_id"
    fi
    return 0
  fi

  # Never run git against a directory that is not actually a worktree: it would
  # resolve to the parent repo and commit the user's own work onto their branch.
  if ! is_worktree_root "$wt"; then
    die "$wt exists but is not a git worktree root; refusing to run git there (a stale directory from a failed clean?). Remove it manually after checking its contents."
  fi

  # Count the delegate's OWN commits before we add one of our own, so the
  # commit-discipline check can still tell whether the delegate obeyed a
  # "do not commit" brief. Persisted on first capture: SKILL.md prescribes
  # running `collect` twice (verify, then integrate), and on the second run
  # base_sha..HEAD already contains our own capture commit, which would
  # otherwise be misattributed to the delegate -- inverting the exact answer
  # this field exists to give.
  if [ -f "$run_dir/delegate_commits" ]; then
    delegate_commits=$(cat "$run_dir/delegate_commits")
  else
    delegate_commits=$(git -C "$wt" rev-list --count "$base_sha"..HEAD 2>/dev/null || echo 0)
    printf '%s\n' "$delegate_commits" >"$run_dir/delegate_commits"
  fi

  # Stage everything so uncommitted AND untracked delegate output are captured.
  # Then COMMIT it onto the branch: the prompt contract tells delegates not to
  # commit, so without this the branch would stay pinned at base and `clean`
  # would destroy the work while claiming to keep it.
  #
  # --no-verify and gpgsign=false are REQUIRED, not hygiene. This commit is a
  # capture step, not authorship. A repo with a failing pre-commit hook (husky,
  # lint-staged, pre-commit) or an unavailable signing key would otherwise abort
  # collect under `set -e`, leaving diff.patch unwritten AND the worktree dirty
  # -- at which point `clean` refuses and the only escape is `clean --force`,
  # which discards exactly the work this function exists to preserve.
  git -C "$wt" add -A
  if ! git -C "$wt" diff --cached --quiet; then
    if ! git -C "$wt" \
        -c user.email=delegate@local -c user.name="delegate ($harness)" \
        -c commit.gpgsign=false \
        commit -q --no-verify -m "delegate output: $task_id ($harness)

Auto-committed by delegate.sh collect so the work survives cleanup.
Not reviewed, hooks bypassed. Squash or drop before merging."; then
      die "could not commit delegate output in $wt; the worktree is intact -- inspect it before running clean"
    fi
  fi

  git -C "$wt" diff "$base_sha" HEAD >"$run_dir/diff.patch"
  commits=$(git -C "$wt" rev-list --count "$base_sha"..HEAD 2>/dev/null || echo 0)
  files=$(git -C "$wt" diff --name-only "$base_sha" HEAD | wc -l | tr -d ' ')
  printf 'task:    %s\n' "$task_id"
  printf 'harness: %s\n' "$harness"
  printf 'commits: %s total (%s by the delegate itself)\n' "$commits" "$delegate_commits"
  printf 'files:   %s\n' "$files"
  printf 'branch:  delegate/%s\n' "$task_id"
  printf 'diff:    %s\n' "$run_dir/diff.patch"
  printf 'result:  %s   <- a CLAIM, not evidence\n' "$run_dir/result.txt"
  printf '\nchanged files:\n'
  git -C "$wt" diff --name-status "$base_sha" HEAD
}

# ---------------------------------------------------------------- clean

cmd_clean() {
  # Accept --force in any position: `clean --force <id>` previously parsed the
  # flag as the task-id, printed "no worktree for --force" and exited 0, leaving
  # the real worktree in place while reporting success.
  task_id=""; force=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --force) force=--force; shift ;;
      -*)      die "unknown flag: $1" ;;
      *)       [ -n "$task_id" ] && die "unexpected argument: $1"; task_id=$1; shift ;;
    esac
  done
  [ -n "$task_id" ] || die "usage: delegate.sh clean <task-id> [--force]"

  root=$(repo_root)
  wt="$root/.delegates/worktrees/$task_id"
  if [ ! -d "$wt" ]; then
    printf 'no worktree for %s\n' "$task_id"
    return 0
  fi

  # Refuse to discard work that was never committed to the branch. Removing the
  # worktree deletes the working tree, so uncommitted output would be lost while
  # the "kept" branch stayed empty. `collect` is what commits it.
  if [ "$force" != --force ]; then
    # A directory that is not a worktree root would make `git status` report on
    # the PARENT repo -- so a dirty main checkout would masquerade as dirty
    # delegate output. Check identity before trusting any git answer here.
    if ! is_worktree_root "$wt"; then
      die "$wt exists but is not a git worktree root; refusing to touch it (a stale directory from a failed clean?). Inspect its contents, then remove it manually."
    fi
    # Capture stdout ONLY. Merging stderr would let a benign warning that git
    # prints while still exiting 0 (fsmonitor/watchman hooks, "unable to
    # access", deprecation notices) read as uncommitted output -- steering the
    # user toward --force, the one command that destroys work. Fail closed on a
    # genuine non-zero exit instead.
    if ! status=$(git -C "$wt" status --porcelain 2>/dev/null); then
      die "cannot determine worktree state for $task_id (git status failed); refusing to remove -- use --force only if you intend to discard it"
    fi
    if [ -n "$status" ]; then
      die "worktree $task_id has uncommitted delegate output; run 'delegate.sh collect $task_id' first (or 'clean $task_id --force' to discard it)"
    fi
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
