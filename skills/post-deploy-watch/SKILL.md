---
name: post-deploy-watch
description: >-
  Monitor released features for production stability with a dedicated SRE agent
  per PR for at least two business days. Discover recent merged PRs by GitHub
  username, defaulting to the authenticated user. Use when asked to watch a
  deployment, monitor a teammate's recent merges, monitor a feature after
  release, or investigate regressions during its watch.
  Skip CI babysitting, deployment execution, and general daily operations triage.
---

# Post-deploy Watch

Operate as the SRE responsible for a released feature's stability. Trace the
feature through its callers, services, background work, database and providers.
Assess customer outcomes and resource pressure across that path.

If the request only creates or extends this skill, lists PRs, or reviews a
previous report, produce that artifact without starting production watches or
scheduled tasks.

## Select PRs

Accept explicit PR URLs or discover PRs from a GitHub username and lookback.
For discovery, follow [GitHub discovery](references/github-discovery.md).
Resolve these defaults at invocation time rather than storing a person's
login in the skill:

- Username: the authenticated GitHub account on the selected host. Treat
  `me`, `@me` and an omitted username the same way.
- Lookback: seven rolling days when omitted. Accept a positive integer N;
  discovery days are 24-hour periods, separate from the watch's business days.
- Scope: the supplied repositories/organisation, then a saved team scope,
  then the current repository owner's organisation. Use accessible repositories
  across that organisation unless the user narrows the scope.
- Relationship: the recorded merger for "merged by" or "I merged". Match the
  author only when the request says "authored by" or "my PRs that merged".

Examples:

```text
$post-deploy-watch
$post-deploy-watch last 3 days
$post-deploy-watch @teammate last 14 days
$post-deploy-watch merged by @teammate last 7 days in example-team
$post-deploy-watch authored by me last 7 days in example-team/web
$post-deploy-watch list my merges last 7 days
```

Report the resolved user, relationship, host, scope, exact UTC interval and
discovery completeness. Deduplicate by repository and PR number. Pass each
matched PR to the ownership workflow. Resume existing active watches, retain
completed verdicts and keep awaiting-release candidates visible. Do not infer
deployment from merge time or skip a candidate because its merge is already
older than two business days.

Complete the current frozen scan rather than creating an ongoing discovery
schedule. Add recurring discovery only when requested. If a saved discovery
run resumes later, keep active watches even after their PRs leave its rolling
lookback. The lookback selects candidates; it does not shorten their watches.

## Establish ownership and scope

1. Resolve each PR's repository, diff, merge commit and tracked issue. Map the
   changed behaviour to deployed workloads, routes, jobs, tables, dependencies,
   feature flags and intended users. Read applicable production access rules
   and the private service mapping described in
   [service context](references/service-context.md).
2. Create one dedicated worker and watch record per PR and environment. Use a
   stable key such as `owner/repo#123:production`. Reuse an existing watch for
   that key. Keep the coordinator responsible for assignment and combined
   summaries. Let each worker manage its own watch schedule.
3. Give each worker the [watch record and assignment](references/watch-record.md).
   Delegate the PR's full investigation to that worker. Keep it assigned across
   ticks; if its session ends, resume its record in a replacement worker.
4. Keep attribution and checkpoints separate when several PRs share a release.
   Reuse shared infrastructure measurements when their scope and times match.
   Link a shared incident across affected watches instead of duplicating it.
5. If worker capacity is exhausted, record the unassigned PRs as pending and
   report the coverage gap. Do not describe a coordinator's pooled summary as
   a dedicated watch.

Use the available agent runner. In Orca, read the `orchestration` skill if
available and use its version-matched guide for supervised workers. Read
[Orca scheduling](references/orca.md) for durable recurrence. In other runners,
discover the actual scheduling and agent capabilities before using them.

## Verify release and exposure

Verify the read-only identity, account/project, environment and resource
selection before querying production. Report unavailable access as a gap.
Keep credentials, connection strings and customer payloads out of reports.

Match the PR commit, or a descendant containing it, to a successful release
and the live revision/image on every workload needed by the feature. Check
traffic allocation, ready replicas and feature flag/cohort state. Record the
actual deployment and exposure times separately from merge time.

Start the minimum watch at the later of the required workloads becoming ready
and the intended cohort receiving the enabled feature. If exposure is not
established, keep the watch `awaiting-exposure` and inspect rollout health.
Retain early-canary evidence but start the full watch when the intended
rollout is reached. A health endpoint alone does not prove feature use.

If the watch starts late, backfill from exposure using retained telemetry.
Record unfillable gaps. A later unrelated deployment does not reset the watch
when it preserves the monitored behaviour. Record a new exposure and restart
the minimum window after a corrective release or material change to that
behaviour. When the feature is rolled back, report `rolled-back` and check
recovery; do not label the feature stable.

Use maintained service guidance or private configuration to resolve production
resources. Revalidate resource hints against deployment configuration and live
state. Keep organisation-specific mappings outside this public skill package.

## Calculate the minimum window

Default to `Australia/Melbourne` and metropolitan Melbourne's Victorian
public-holiday calendar. Count Monday to Friday, excluding public holidays
and their observed or substitute dates. Verify the relevant years against
the [Business Victoria calendar](https://business.vic.gov.au/business-information/public-holidays)
and record the source and dates used. Include Melbourne Cup Day for Melbourne.

Use another timezone or calendar when the user explicitly supplies an
override. Preserve an existing watch's recorded explicit override on resume.
Apply the resolved business timezone to scheduling and daily summaries. Use
the IANA timezone so daylight saving follows Melbourne's local dates. If
holiday dates cannot be verified, continue collection and keep the calendar
unconfirmed until a stable closeout can be assessed.

Require at least two complete local business dates after the exposure date.
Do not count the partial release date, weekends or public holidays. The
earliest completion is midnight after the second qualifying date. Record the
local date, timezone and UTC instant so daylight-saving changes remain clear.

For a Friday release with no holidays, count Monday and Tuesday and finish no
earlier than Wednesday at 00:00 local. If Monday is a public holiday, count
Tuesday and Wednesday and finish no earlier than Thursday at 00:00 local.
Use a longer user-requested window when supplied.

Continue checks overnight, over weekends and on holidays. Those periods still
contain production risk even though they do not advance the business-day count.
Extend the watch when representative traffic, a relevant batch cycle, recovery
evidence or required telemetry remains missing. State the next review time and
the evidence needed; elapsed time alone does not establish stability.

## Arm persistent monitoring

Persist the record outside the disposable feature worktree. Use the configured
operations state store; otherwise use a private host directory such as
`~/.local/state/post-deploy-watch/`. Keep only sanitised evidence summaries and
source links. Make the record accessible to the assigned execution host.

Set up recurring execution when the user asks to start a watch. Verify the
saved scheduler ID, enabled state, cadence, timezone, target host/workspace,
prompt and next due time. Confirm the first completed tick and its saved
checkpoint before reporting monitoring as active. If the scheduler does not
expose a next-run field, calculate the due time and identify it as calculated.

Use this default cadence unless the service's risk or user request calls for
another interval:

| Time since exposure | Check interval |
| --- | --- |
| First hour | 10 minutes, including an immediate check |
| Remainder of first 24 hours | 30 minutes |
| After 24 hours through closeout | 60 minutes |

Inspect full intervals between successful checkpoints so cadence changes and
missed runs do not discard evidence. Keep existing production alerts in place.
These periodic investigations supplement their detection coverage.

If durable scheduling is unavailable, run the immediate assessment and report
`not-armed` with the exact limitation and a concrete resume prompt. Do not
promise background observation from an open chat, sleeping loop or child
agent whose lifetime ends with the turn. If a host needs to stay awake and
connected, disclose that dependency. Preserve incomplete coverage on restart.

## Run each observation tick

Fix one UTC end time per tick, allowing for known ingestion delay. For each
source, query `[last_successful_end, tick_end)` and record its own coverage.
Use a small overlap for late events and deduplicate by stable event identifiers.
Advance only the sources whose queries finished successfully. Paginate or split
bounded intervals when a result limit is reached. Distinguish empty results
from failed, sampled, truncated or delayed collection.

Build a baseline from the previous revision and comparable traffic before
exposure. Prefer the preceding 24 hours plus matching weekday/business-hour
windows from the previous week when available. Mark weak or absent baselines.
Keep baseline queries and values fixed; do not absorb a regression into them.

Choose explicit queries and decision thresholds for the feature before judging
the first post-release results. Prefer existing SLOs and alerts. Otherwise
record provisional criteria using observed variation, an absolute impact floor,
and a relevant denominator. Never invent a service SLO or use one arbitrary
percentage for every feature. A deterministic security or data-integrity
failure needs attention even when it occurs once.

Inspect every applicable signal family. Record why a family is inapplicable
or unavailable rather than silently dropping it.

| Signal | Evidence and comparison |
| --- | --- |
| Feature outcomes | Attempts, completions, failure rate, adoption/cohort exposure and successful final output; include delayed work and expected freshness |
| Application logs | New error causes, recurring spikes, timeouts, cancellations and recovered retries across entry points and workers |
| Sentry | New, regressed and existing issues receiving events in this environment and window; inspect event details, release tags, traces and affected breadth |
| Performance | Request/job rate, failure rate, p50/p95/p99 latency, slow traces, database spans and provider time; compare successful and failed operations separately |
| Database | CPU/load, memory, connections/pool waits, I/O, storage growth, lock waits, deadlocks, long transactions, query cost/call count and replication lag where relevant |
| Runtime capacity | CPU/memory, OOMs, restarts, readiness, instance/replica count, concurrency, scaling limits and capacity-related request failures |
| Async work | Queue depth and oldest age, enqueue-to-start latency, throughput, retries, failed/dead jobs and scheduled/Temporal completion where applicable |
| Dependencies and cost | Provider errors, quotas/rate limits, caches, network failures and spend per successful operation when the feature changes consumption |

Compare rates with rates and like periods with like periods. Preserve sample
size, traffic mix, rollout percentage and metric units. Use counter deltas,
accounting for resets. Aggregate latency distributions rather than averaging
percentiles. Judge shared database pressure alongside demand and feature query
cost; a simultaneous CPU rise alone does not identify the responsible PR.

Count Sentry events inside the observation window. Issue lifetime totals and
first-seen dates alone cannot measure a post-release regression. Include older
issues that recur after release. Correlate representative events with logs and
traces, then check final outcomes. Deduplicate wrappers, retries and multiple
telemetry records for one failure. Retain distinct affected breadth.

Prefer existing metrics and query insights for database diagnosis. When an
authorised direct connection is needed, verify database identity and use a
read-only transaction with bounded timeouts and aggregate queries. Do not
run load tests, production `EXPLAIN ANALYZE`, query-stat resets or session
termination as monitoring. Report unavailable database visibility explicitly.

## Investigate and escalate

Classify a signal's relationship to the PR as `confirmed`, `plausible`,
`unrelated` or `unknown`. Use changed paths, revision/cohort differences,
onset time and representative execution evidence. Timing alone supports a
hypothesis. Investigate severe impact promptly even when attribution is unknown.

Separate new or elevated failures from baseline noise. Check whether retries
or fallbacks reached a successful final result. Use supplied service exclusions;
do not inherit an unrelated report's suppressions or discard internal test
failures that exercise the released feature without assessing their relevance.

- Escalate immediately for confirmed data loss, security/privacy defects,
  broad customer failure, breached critical SLOs or exhausted capacity.
- Escalate sustained regressions against the recorded criteria with impact,
  breadth, first/last occurrence, baseline comparison and source links.
- Keep isolated, recovered failures under observation with an explicit
  recurrence or impact condition that would raise their priority.
- Report collection gaps and missed scheduler runs as incomplete monitoring.
  Backfill them when possible; do not report telemetry loss as product health.

Use the current conversation for findings. Send Slack/email messages, post PR
comments, create Linear issues or invoke paging only when that destination
and action are authorised by the user or saved watch configuration. Record
the destination, delivery result and deduplication key when sending is allowed.
When no external route is authorised, surface the escalation here and prepare
the concrete handoff. Do not imply an on-call person has been notified.

Keep production operations read-only under a monitoring request. Provide an
evidence-backed mitigation or rollback recommendation when needed. Execute
changes only under separate authority, and follow the incident workflow when
one exists. After mitigation, verify the affected path succeeds and pressure
recovers before changing its status.

## Report and close

Save each tick before yielding. Report meaningful changes immediately, provide
a daily summary at the end of each business date, and issue a final verdict.
Keep quiet ticks in the record to avoid repeating unchanged findings.

Include the PR, deployed revision, exposure time, observed UTC window, local
minimum end, scheduler state/next check, outcome, signal comparisons, open
findings and missing evidence. Link queries, dashboards, traces and issues.
Use `watching`, `degraded`, `awaiting-exposure`, `incomplete`, `not-armed`,
`stable`, `rolled-back` or `stopped` as appropriate.

Close as `stable` only when the calendar is confirmed, the minimum window has
elapsed, required telemetry covers it through ingestion delay, representative
feature use and relevant work cycles succeeded, and material regressions are
resolved. Inspect a final fresh interval rather than closing from a timer.
Keep recovery evidence separate from absence of new errors. State residual
uncertainty; do not promise that observation proves future reliability.

After a terminal verdict or an explicit user stop, disable only this watch's
schedule and verify the disabled state. Preserve the final record and evidence
links. If coverage remains insufficient, continue with a stated next review
or hand over as `incomplete`; do not silently retire the watch.
