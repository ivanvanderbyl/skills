# Watch record and worker assignment

Read this when creating or resuming a PR watch. Store one record per repository,
PR and environment. Use atomic replacement or the state store's conditional
write support. Have one worker write that record at a time. Record ownership
before replacement so an older session cannot overwrite a resumed watch.

## Record contents

| Group | Required contents |
| --- | --- |
| Identity | Watch key, PR URL, issue URL if present, repository, environment and feature summary |
| Discovery | Explicit PR or scan ID; selected host/user/relationship, repository or organisation scope, fixed lookback start/end, author, recorded merger, merge time and match evidence |
| Ownership | Coordinator, dedicated worker/task/session, execution host, state location and current writer |
| Release | Merge commit, deployed commit/digest per workload, rollout proof, traffic/cohort and flag evidence, deployment and exposure times |
| Calendar | IANA timezone, holiday jurisdiction/dates/source, assumption status, two qualifying dates, earliest completion in local time and UTC |
| Schedule | Scheduler ID, enabled/verified status, cadence/phase, last completed run, next due time, host availability assumptions |
| Scope | Routes, workers, jobs, tables, providers, feature outcome and expected work cycles |
| Baseline | Fixed intervals, query links/filters, values, units, denominators, cohorts, SLOs or provisional decision criteria and their rationale |
| Coverage | Per source: last successful end, overlap/lag, completeness, sampling/retention constraints and unresolved gaps |
| Findings | Stable fingerprint, first/last observed, severity, customer impact/breadth, evidence links, PR attribution and confidence, disposition |
| Delivery | Authorised destinations/actions, escalation fingerprint, delivery evidence or pending handoff |
| Progress | Status, tick summaries, business-date summaries, next action/review and extension reason |
| Closeout | Final observed end, representative outcomes, remaining uncertainty, verdict and verified schedule disablement |

Store source links and sanitised aggregates. Do not retain customer content,
email addresses, tokens, raw request/response bodies or raw SQL with literals
in the watch record. Use the organisation's approved operational retention.

Keep per-source completeness independent of the overall status. For example,
`degraded` can coexist with incomplete database collection. Derive any overall
coverage endpoint from the oldest required successful source checkpoint;
do not substitute the latest tick timestamp.

## Worker assignment

Fill this prompt with actual values. Deliver it to the dedicated PR worker.
Do not put credentials into the prompt.

```text
Use $post-deploy-watch at <skill-path> as the SRE for <PR URL> in <environment>.
You own only watch <key>. Coordinator: <handle>. State: <absolute path or URI>.
Read the saved record before collecting evidence. Preserve source checkpoints
and the fixed baseline. Verify the deployed commit, exposure and scope.
Business timezone/calendar: <value and confirmation status>.
Earliest completion: <local and UTC, or awaiting verified exposure>.
Collect logs, Sentry, performance, database and other applicable operational
signals for this feature. Use read-only production access under <access rules>.
Authorised notification actions: <explicit destinations/actions, or current
conversation only>. Production mitigation authority: <scope, or none>.
For this tick, fix an observation end, inspect each source since its saved
successful checkpoint, investigate changes and save the record before yielding.
Return status, evidence, coverage gaps, escalation and the next check/action.
Do not report a two-business-day watch complete from a single observation.
```

On restart, include the previous worker identity and record version in the
assignment. Confirm the previous worker is inactive or fenced before changing
the writer. A new session keeps the same PR ownership and observation history.

## Report form

```text
<status> | <PR> | <environment> | revision <commit/digest>
Exposure: <time and cohort>. Observed: <UTC start/end>.
Minimum end: <local date/time and timezone> (<UTC>).
Monitoring: <verified scheduler/host status>; next check <time>.
Outcome: <successful operations / attempts, final-result evidence>.
Signals: <baseline -> current, units, sample/traffic context, source links>.
Findings: <impact, attribution/confidence, evidence, escalation or None>.
Coverage: <source completeness and gaps>.
Next action or verdict: <owner, evidence required, review time>.
```
