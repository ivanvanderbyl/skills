# GitHub discovery

Read this when selecting PRs by username and lookback instead of explicit URLs.
Use the existing authenticated `gh` CLI or connected GitHub read tools. Do not
install a client or request broader credentials for a scan.

## Resolve the scan

1. Select the GitHub host from the explicit scope, saved team configuration or
   current repository remote. Keep every query on that host. Resolve an
   omitted username, `me` or `@me` with `gh api user --jq .login` on that host.
   Validate an explicit username using its user endpoint. Compare logins
   without case sensitivity. Report failed authentication instead of guessing
   the local Git author or using a different GitHub account.
2. Use explicit repository or organisation filters when supplied. Otherwise
   use saved team scope, then the current remote's owner if it is an
   organisation. Verify the owner type through GitHub. If the current owner is
   a personal account or no team scope is available, ask for the intended
   organisation/repositories while resolving the user. Do not silently scan
   unrelated organisations or limit a team scan to the current repository.
3. Default N to 7. Validate a supplied N as a positive integer. Freeze `end`
   once in UTC and set `start = end - N * 24 hours`. Select actual merge times
   in `[start, end)`. Record the supplied language and resolved defaults.
4. Default to `merged-by`. For an explicit authored-PR request, use
   `authored-by`. Record the chosen relationship in the scan and each match.

For GitHub Enterprise, pass the verified host through `gh api --hostname` or
the connected client's host argument. Do not expose tokens while checking
identity. Username validation does not establish access to every team repo.

## Collect and verify candidates

Search the selected scope for all merged PRs in the frozen interval, then read
each candidate's pull-request details. The documented search qualifiers include
`org:`, `repo:`, `is:pr`, `is:merged`, `merged:` and `author:`. Use the PR's
`merged_by.login` to select the merger. Do not substitute author or `involves:`
for merger selection or rely on an unverified `merged-by:` search qualifier.

An example REST search is:

```text
gh api --hostname <host> --method GET search/issues --paginate --slurp -f 'q=org:<org> is:pr is:merged merged:<UTC-start>..<UTC-end>' -F per_page=100
```

Use `repo:<owner>/<repo>` instead of `org:` for an explicit repository scope.
Search each supplied scope and deduplicate the results. For `authored-by`,
add `author:<verified-login>` to reduce candidates, then verify the author
from the PR details. Do not add that filter in `merged-by` mode: a person can
merge another teammate's PR.

For every candidate, retrieve its actual PR detail endpoint:

```text
gh api --hostname <host> repos/<owner>/<repo>/pulls/<number> --jq '{number, url: .html_url, author: .user.login, merger: .merged_by.login, merged_at, merge_commit_sha, base: .base.ref}'
```

Verify a non-null merge time inside the exact half-open interval and the
requested author or merger. Keep the author, merger, base branch, merge
commit, match basis and PR URL. Do not require author and merger both to match.
Search boundaries may be inclusive; the detail timestamp is authoritative
for boundary filtering. Treat unavailable PR details as unresolved candidates.

Retrieve all pages. GitHub search exposes at most 1,000 results per query;
pagination alone cannot exceed that cap. Check `total_count`, page coverage
and `incomplete_results`. Split capped or incomplete queries into smaller
time windows and, when needed, repository scopes. Overlap split boundaries
and deduplicate, then apply the original exact interval. If a complete scan
cannot be obtained, report the missing partitions and mark discovery partial.
Use bounded read concurrency and respect rate-limit retry guidance.

GitHub search can lag recent merges. Check recent repository PR records when
an expected merge is absent, or record the indexing limit and recheck before
claiming completeness for the newest tail. Never report "no matches" after
an authentication error, capped search or failed detail lookup.

## Handle queues, existing watches and missing access

When GitHub records a merge queue or bot as `merged_by`, report that actual
actor. Do not infer the human merger from the PR author, assignee or reviewer.
If supplied queue/audit evidence identifies a human initiator, preserve it as
separate attribution. Include bot-merged authored PRs when the user selected
`authored-by`. In `merged-by` mode, retain ambiguous human attribution as
unresolved rather than asserting that the selected person merged it.

Save a sanitised scan manifest alongside operations state, outside disposable
feature worktrees. Include the scan ID, resolved inputs, exact interval,
queried scopes/partitions, completeness and candidate dispositions:

- `matched`: verified requested relationship and merge time; create or resume
  its dedicated watch.
- `excluded`: outside the interval or a different verified author/merger.
- `unresolved`: missing details, uncertain actor or incomplete access.
- `existing`: linked active watch or retained completed verdict; avoid another
  worker or schedule for the same PR/environment.

Keep discovery disposition separate from monitoring status. A matched merge
can still be `awaiting-exposure`, `not-armed` or `incomplete`. Inspect its diff
and release path before deciding which production signals apply. Retain a
recorded reason for changes that do not alter deployed behaviour, such as
documentation-only PRs; do not silently omit them from the scan result.

Search returns only repositories visible to the authenticated account. Report
that visibility boundary and known inaccessible repositories. For an explicit
team allowlist, require collection from every listed repository before calling
the scope complete. An organisation-wide query is not evidence that the
credential can see every private repository in that organisation.

For a monitoring request, continue into per-PR deployment verification and
dedicated watches without another routine approval. For a list-only request,
return the manifest summary without starting workers or schedules. Include
matched, existing, excluded and unresolved counts and the next action.

## Official references

- [GitHub PR search qualifiers](https://docs.github.com/en/search-github/searching-on-github/searching-issues-and-pull-requests)
- [Search API limits and incomplete results](https://docs.github.com/en/rest/search/search)
- [Pull-request detail API](https://docs.github.com/en/rest/pulls/pulls#get-a-pull-request)
