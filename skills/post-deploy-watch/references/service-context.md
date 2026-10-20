# Private service context

Read this when mapping a PR to production resources. Use maintained service
guidance or the team's private operations configuration. Keep the mapping
outside the installed skill directory so skill updates preserve it.

Resolve the following before selecting production resources:

| Context | Required evidence |
| --- | --- |
| Repository scope | GitHub host and repository or organisation scope; visible repositories and known access gaps |
| Access | Existing read-only identity, account/project, region and environment; applicable production access rules |
| Release path | Release workflow, image or revision metadata, commit ancestry and workload readiness |
| Feature exposure | Required routes, workers, jobs, feature flags, intended cohort and rollout percentage |
| Business calendar | IANA timezone, holiday jurisdiction and authoritative calendar source |
| Telemetry | Logs, error tracking, performance, database, runtime capacity, queues, providers and cost sources |
| Operations state | Private durable state location, retention policy and execution host |
| Scheduling | Available runner, cadence, concurrency behaviour, credentials and host availability requirements |
| Escalation | Explicitly authorised destinations and actions; use the current conversation when none are configured |

Record the source and verification time for each resolved value. Treat stored
resource names as discovery hints until live state confirms them. Verify the
identity used by each telemetry client; CLI and application-default credentials
can differ.

If a required value is missing, continue with independent evidence and record
the gap. Do not substitute a different production account, infer release from
merge time, or claim a feature is stable without verified exposure and coverage.

## Map the execution path

Trace the changed behaviour through its actual callers, services, asynchronous
work, database and providers. Include independently deployed clients when they
control whether the feature is used. Verify every required workload and the
intended rollout cohort.

For container deployments, match image tags or digests to a commit containing
the PR. Inspect live traffic allocation, ready replicas and feature flags. For
mobile or desktop releases, also establish distribution and adoption of the
relevant client version.

## Collect operational evidence

Discover the actual source schemas and metric descriptors before querying.
Use exact UTC intervals with bounded queries, pagination and ingestion overlap.
Keep source checkpoints independent when one query fails or is truncated.

For error tracking, count events inside the observation interval. Include
existing issues that recur after exposure. Correlate representative events
with logs and traces, then inspect the final feature outcome. Issue lifetime
totals and a health endpoint alone do not establish feature health.

For database checks, prefer existing monitoring and query insights. If direct
access is authorised, verify the database identity and use a read-only
transaction with bounded statement and lock timeouts. Collect aggregate load,
connections, waits, long transactions, query cost and replication evidence as
applicable. Keep SQL literals and customer rows out of saved evidence. Do not
run load tests, production `EXPLAIN ANALYZE`, query-stat resets or session
termination as monitoring.

For background work, distinguish retries from affected executions. Check
queue depth, oldest age, enqueue-to-start delay, throughput, terminal failures
and final completion or freshness. Preserve deterministic security and
data-integrity failures even when they occur once.

Apply only exclusions that belong to this service and feature. Assess internal
test traffic when it exercises the released path. Keep sanitised aggregates,
query links and uncertainty in the watch record; keep credentials and customer
payloads out of it.
