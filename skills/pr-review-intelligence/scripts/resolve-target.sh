#!/usr/bin/env bash
# Resolve the forge host and project path from a git remote URL.
#
# Usage:
#   resolve-target.sh [REMOTE_URL]
#
#   REMOTE_URL  defaults to `git remote get-url origin`
#
# Emits JSON: { host, forge, path, slug, project_encoded, is_public_host }
#
# Why this exists: both `gh` and `glab` fall back to their PUBLIC host
# (github.com / gitlab.com) whenever a hostname is neither passed nor inferable
# from the current directory's git remote. On a GitHub Enterprise or self-hosted
# GitLab instance that fallback is silent and dangerous - a request for
# `acme/api` reaches the PUBLIC repo of that name, and the run produces a
# complete, plausible report mined from someone else's codebase with no error.
#
# So the host is resolved once, here, and passed explicitly to every API call
# rather than inferred per-invocation from a working directory that may not be
# the target repository at all.

set -euo pipefail

command -v jq >/dev/null || { echo "error: jq not found on PATH" >&2; exit 2; }

REMOTE="${1:-}"
if [ -z "$REMOTE" ]; then
  REMOTE="$(git remote get-url origin 2>/dev/null)" || {
    echo "error: no remote URL given and 'git remote get-url origin' failed." >&2
    echo "       Pass the remote URL explicitly, or set repo/forge inputs." >&2
    exit 2
  }
fi

# --- parse host and path out of the remote URL -----------------------------
# Handles: git@host:path.git | ssh://git@host:port/path.git | https://host/path.git
url="$REMOTE"
url="${url%.git}"

case "$url" in
  *://*)
    rest="${url#*://}"        # strip scheme
    rest="${rest#*@}"         # strip optional user@
    hostport="${rest%%/*}"
    host="${hostport%%:*}"    # strip :port
    path="${rest#*/}"
    ;;
  *@*:*)
    rest="${url#*@}"          # scp-like: git@host:path
    host="${rest%%:*}"
    path="${rest#*:}"
    ;;
  *)
    echo "error: cannot parse remote URL: $REMOTE" >&2
    exit 2
    ;;
esac

path="${path#/}"
path="${path%/}"

if [ -z "$host" ] || [ -z "$path" ]; then
  echo "error: cannot parse host/path from remote URL: $REMOTE" >&2
  exit 2
fi

# --- determine the forge ---------------------------------------------------
# Known public hosts are unambiguous. Anything else could be either product --
# a hostname like git.acme.com says nothing about what is behind it -- so probe
# authentication rather than guess from the URL shape.
forge=""
is_public="true"

case "$host" in
  github.com) forge="github" ;;
  gitlab.com) forge="gitlab" ;;
  *)
    is_public="false"
    gh_ok=false
    glab_ok=false
    command -v gh   >/dev/null && gh   auth status --hostname "$host" >/dev/null 2>&1 && gh_ok=true
    command -v glab >/dev/null && glab auth status --hostname "$host" >/dev/null 2>&1 && glab_ok=true

    if   [ "$gh_ok" = true ]  && [ "$glab_ok" = false ]; then forge="github"
    elif [ "$glab_ok" = true ] && [ "$gh_ok" = false ];  then forge="gitlab"
    elif [ "$gh_ok" = true ]  && [ "$glab_ok" = true ]; then
      cat >&2 <<EOF
error: both gh and glab are authenticated to ${host}, so the forge is ambiguous.
       Pass the forge explicitly (forge=github or forge=gitlab).
EOF
      exit 1
    else
      cat >&2 <<EOF
error: neither gh nor glab is authenticated to ${host}.

       This looks like a self-hosted instance (GitHub Enterprise or GitLab).
       Authenticate first, then re-run:

         gh auth login --hostname ${host}
         # or
         glab auth login --hostname ${host}

       Do NOT fall back to the public host: gh and glab both default to
       github.com / gitlab.com, which would mine a different repository of the
       same name.
EOF
      exit 1
    fi
    ;;
esac

# GitLab projects can be nested (group/subgroup/project); the API wants the path
# URL-encoded. GitHub is always owner/name.
project_encoded="${path//\//%2F}"

jq -n \
  --arg host "$host" \
  --arg forge "$forge" \
  --arg path "$path" \
  --arg enc "$project_encoded" \
  --argjson pub "$is_public" \
  '{host: $host, forge: $forge, path: $path, slug: $path,
    project_encoded: $enc, is_public_host: $pub}'
