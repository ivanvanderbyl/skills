# SRE skills

Agent skills for investigating production behaviour and monitoring released changes.

## Install

Use the [Skills CLI](https://github.com/vercel-labs/skills) to select a skill and your coding agent:

```sh
npx skills add ivanvanderbyl/skills
```

To install the post-deploy watch skill for Codex in your current project:

```sh
npx skills add ivanvanderbyl/skills --skill post-deploy-watch -a codex
```

Add `-g` to install across projects. The repository uses the [Agent Skills format](https://agentskills.io/specification).

## Skills

| Skill | Use it to |
| --- | --- |
| [post-deploy-watch](skills/post-deploy-watch/SKILL.md) | Discover recent merges, verify production exposure, and run a dedicated watch for each PR for at least two complete business dates. |

## Start a watch

```text
$post-deploy-watch last 3 days
$post-deploy-watch merged by @teammate last 7 days in example-team
$post-deploy-watch https://github.com/example-team/service/pull/123
```

The default discovery relationship is **merged by** the authenticated GitHub user. Use `authored by` to select the PR author instead. The default scope is the current repository owner's organisation, unless you supply or configure a different scope.

Before collecting production evidence, the skill resolves the service's deployment path, resources, access rules, business timezone and holiday calendar. Keep that mapping in private service guidance or an operations state directory. See [service context](skills/post-deploy-watch/references/service-context.md) for the required information.

Watches use existing read-only production access and record coverage separately for each telemetry source. Recurring monitoring requires a durable scheduler and execution host. Each watch records the scheduler receipt, first completed tick and next check. When those capabilities are unavailable, the skill returns the immediate assessment with an explicit monitoring gap and a resume prompt.

## Repository layout

Each skill lives in `skills/<name>/` with a `SKILL.md` entrypoint and its supporting references. Service identifiers, credentials, customer data, watch state and reports belong outside this repository.
