# Distill a raw GitLab MR payload into the forge-neutral corpus schema.
#
#   jq -f distill-gitlab.jq raw/mr-1234.json > distilled/mr-1234.json
#
# Emits the SAME shape as distill-github.jq so the analyst agent never branches
# on forge. Where GitLab lacks a GitHub field, the closest honest proxy is used
# and the difference is noted inline.
#
# Input is the combined record written by fetch-gitlab-corpus.sh:
#   { mr: {...}, discussions: [...], commits: [...] }

def clip($n): (. // "") | if (length > $n) then .[0:$n] + "\n[…truncated]" else . end;

# GitLab bot detection is heuristic - there is no __typename equivalent.
# Covers GitLab's own service accounts plus the common review bots.
def is_bot_name:
  . as $n
  | ($n | test("(?i)(^|[-_])bot($|[-_])"))
    or ($n | test("(?i)^(gitlab-bot|project_\\d+_bot\\d*|group_\\d+_bot\\d*)"))
    or ($n | test("(?i)(coderabbit|renovate|dependabot|sonarqube|codeclimate|greptile)"));

.mr as $mr
| ($mr.author.username // "unknown") as $mrAuthor
| .commits as $commits
| {
    forge: "gitlab",
    number: $mr.iid,
    title: $mr.title,
    url: $mr.web_url,
    merged_at: $mr.merged_at,
    author: $mrAuthor,
    size: {
      # GitLab's MR list does not return diff stats; null rather than a guess.
      files: null,
      additions: null,
      deletions: null,
      commits: ($commits | length)
    },

    # GitLab has no review object and therefore no CHANGES_REQUESTED marker.
    # Proxy: count commits pushed after the first review note, i.e. how many
    # times the author went back and reworked. Not equivalent to GitHub's
    # explicit rounds - it over-counts when authors push unrelated work mid-review.
    change_request_rounds: (
      ([ .discussions[].notes[] | .created_at ] | sort | first) as $firstNote
      | if $firstNote == null then 0
        else [ $commits[] | select(.created_at > $firstNote) ] | length
        end
    ),
    change_request_rounds_is_proxy: true,

    human_reviewers: (
      [ .discussions[].notes[]
        | .author.username
        | select(is_bot_name | not) ]
      | unique - [$mrAuthor]
    ),

    # fetch-gitlab-corpus.sh already filtered to diff-anchored, non-system
    # threads, so fetched == total for this forge.
    threads_total: (.discussions | length),
    threads_fetched: (.discussions | length),

    threads: [
      .discussions[]
      | (.notes // []) as $notes
      | select($notes | length > 0)
      | ($notes[0]) as $first
      | {
          path: ($first.position.new_path // $first.position.old_path),

          # new_line goes null when the anchored code changed - this doubles as
          # GitLab's only signal for GitHub's isOutdated.
          line: ($first.position.new_line // $first.position.old_line),

          resolved: ($first.resolved // false),
          outdated: ($first.position.new_line == null),
          resolved_by: ($first.resolved_by.username // null),

          bot_initiated: ($first.author.username | is_bot_name),

          comment_count: ($notes | length),
          last_comment_by_pr_author: (($notes[-1].author.username) == $mrAuthor),
          reviewer_pushed_back: (
            [ $notes[] | select(.author.username != $mrAuthor) ] | length > 1
          ),

          # GitLab has no reactions on notes in this payload; award emoji are a
          # separate endpoint and not worth an extra request per thread.
          negative_reactions: 0,

          # GitLab does not return the surrounding hunk with the discussion.
          # Left null; the agent works from the comment text and file path.
          code_context: null,

          # GitLab returns structured suggestions, which GitHub only embeds as a
          # ```suggestion fence. A suggestion that was applied is strong evidence
          # the feedback was addressed.
          has_suggestion: ([ $notes[] | select((.suggestions | length) > 0) ] | length > 0),

          comments: [
            $notes[]
            | {
                author: .author.username,
                is_bot: (.author.username | is_bot_name),
                is_pr_author: (.author.username == $mrAuthor),
                created_at: .created_at,
                body: (.body | clip(2000))
              }
          ]
        }
    ]
  }
