# Orca scheduling

Read this when Orca runs the watch. Use the installed `orca-cli` skill if
available to select the session's executable. Otherwise use
`ORCA_CLI_COMMAND` when set; on macOS use `orca` when unset. On other hosts,
discover the actual Orca executable instead of guessing a binary name.

Load the version-matched `orca-cli` guide and its `references/automations.md`
before operating automations. Load `orchestration` before coordinating
supervised workers. Use the installed binary's help for fields not covered
by the guide. The commands here were verified against Orca on 2026-10-20;
the running host's guide takes precedence over these examples.

## Bind a watch to an existing workspace

Use one durable workspace per PR watch, separate from the disposable feature
checkout when that checkout may be removed. Use the full workspace selector
returned by Orca. Inspect existing automations and workers for the watch key
before creating another. Keep this workspace and its state until closeout.

Create one automation per watch in the existing workspace. Request session
reuse so ticks return to the assigned PR agent when it remains live. Orca
can fall back to a fresh session; the prompt must load the durable record.
For several PRs, keep an independent assignment and record for each one.

In these examples, `ORCA` is the resolved executable, not a literal command.
Substitute the actual selector and skill/state paths. Use the watch's resolved
[business timezone](../SKILL.md#calculate-the-minimum-window); the example uses
the default. Pass prompts as a tool argument or shell-quote them safely.

```text
ORCA automations list --json
ORCA automations create --name "post-deploy owner/repo#123 production" --trigger "*/10 * * * *" --timezone Australia/Melbourne --provider codex --workspace <exact-selector> --reuse-session --prompt '<tick prompt>' --disabled --json
ORCA automations show <id> --json
ORCA automations run <id> --json
ORCA automations runs --id <id> --json
ORCA automations edit <id> --enabled --json
```

Use a tick prompt that invokes `$post-deploy-watch`, names exactly one PR,
loads its absolute state path and performs one observation tick. Include the
worker assignment from [watch-record.md](watch-record.md). Tell the resumed
worker to update the schedule when the cadence phase changes and to disable
only its own automation after a terminal verdict or explicit stop.

Verify the initial run completed and wrote its record. Inspect the enabled
schedule and next due time before reporting `watching`. If manual execution
of a disabled automation is unsupported, enable it for the initial run and
verify the receipt instead of inventing a success.

After the first hour, change the trigger to `*/30 * * * *`. After 24 hours,
change it to `0 * * * *`. Re-read the saved schedule after each edit. These
schedules include weekends and holidays. Keep the minimum business-day end
in the record; do not rely on a weekday cron expression to implement it.

Check run history for missed, failed, skipped and overlapping runs. Serialise
ticks through the assigned session or the runner's supported concurrency
control. Skip duplicate concurrent collection without advancing checkpoints.
If the host cannot prevent overlapping writers, report the scheduling gap
and configure supported serial execution before claiming an active watch.

An automation schedule does not prove that its host stayed online. Verify the
execution host's operating requirements and saved run history. Backfill gaps
from each source checkpoint after a restart. Notify the user when host or
credential availability prevents the promised cadence.

For closeout, use `automations edit <id> --disabled --json`, then `show` to
verify. Preserve run history instead of removing the automation. Do not
modify the daily operations triage schedule or another PR's watch.
