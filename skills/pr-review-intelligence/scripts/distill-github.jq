# Distill a raw GitHub PR detail payload into the forge-neutral corpus schema.
#
#   jq -f distill-github.jq raw/pr-1234.json > distilled/pr-1234.json
#
# Two jobs:
#   1. Cut size. Raw payloads reach ~200 KB because diffHunk spans the whole hunk;
#      the anchored code is only its final lines. Distilled records are ~5 KB.
#   2. Normalize. GitHub and GitLab distillers emit the SAME shape, so the analyst
#      agent never branches on forge.
#
# Mechanical facts are computed here. Judgment calls (was this actually addressed?
# what category is it?) are deliberately left to the agent.

def is_bot: (.author.__typename // "") == "Bot";
def login: (.author.login // "unknown");

# diffHunk runs from the hunk header DOWN TO the commented line, so the code the
# reviewer is talking about is the TAIL. Truncating from the front returns the top
# of the file and discards the anchor entirely.
def code_context($n): (. // "") | split("\n") | .[-$n:] | join("\n");

def clip($n): (. // "") | if (length > $n) then .[0:$n] + "\n[…truncated]" else . end;

.data.repository.pullRequest as $pr
| ($pr.author.login // "unknown") as $prAuthor
| {
    forge: "github",
    number: $pr.number,
    title: $pr.title,
    url: $pr.url,
    merged_at: $pr.mergedAt,
    author: $prAuthor,
    size: {
      files: $pr.changedFiles,
      additions: $pr.additions,
      deletions: $pr.deletions,
      commits: $pr.commits.totalCount
    },

    # Explicit round markers. GitHub gives these directly; the GitLab distiller
    # derives an approximation from the commit timeline.
    change_request_rounds: [
      $pr.reviews.nodes[] | select(.state == "CHANGES_REQUESTED")
    ] | length,

    human_reviewers: [
      $pr.reviews.nodes[] | select(is_bot | not) | login
    ] | unique - [$prAuthor],

    # Reported so downstream can detect silent pagination truncation.
    threads_total: $pr.reviewThreads.totalCount,
    threads_fetched: ($pr.reviewThreads.nodes | length),

    threads: [
      $pr.reviewThreads.nodes[]
      | (.comments.nodes // []) as $comments
      | select($comments | length > 0)
      | ($comments[0] | is_bot) as $botInitiated
      | {
          path: .path,
          # line goes null on outdated threads; originalLine survives.
          line: (.line // .startLine // $comments[0].originalLine),
          resolved: .isResolved,
          outdated: .isOutdated,
          resolved_by: (.resolvedBy.login // null),

          # Bot-initiated threads are INVERTED signal: a bot suggestion the team
          # declined is evidence of what they consider noise. Never merge these
          # into positive review guidelines.
          bot_initiated: $botInitiated,

          # Mechanical inputs to the addressed/declined call. The agent makes the
          # call; these are the facts it reasons over.
          comment_count: ($comments | length),
          last_comment_by_pr_author: (($comments[-1] | login) == $prAuthor),
          reviewer_pushed_back: (
            [$comments[] | select((login) != $prAuthor)] | length > 1
          ),
          negative_reactions: (
            [ $comments[].reactionGroups[]?
              | select(.content == "THUMBS_DOWN")
              | .users.totalCount ] | add // 0
          ),

          code_context: ($comments[0].diffHunk | code_context(20)),

          comments: [
            $comments[]
            | {
                author: login,
                is_bot: is_bot,
                is_pr_author: ((login) == $prAuthor),
                created_at: .createdAt,
                body: (.bodyText | clip(2000))
              }
          ]
        }
    ]
  }
