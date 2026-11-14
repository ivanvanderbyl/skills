# Agent skills

Reusable agent skills for native application architecture and production operations.

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

To install the Reflex pattern skill for shared Swift cores and native Apple/Android apps, with an optional web target:

```sh
npx skills add ivanvanderbyl/skills --skill reflex-pattern
```

To install the Duo pattern skill for folding-iPhone layouts:

```sh
npx skills add ivanvanderbyl/skills --skill duo-pattern
```

## Skills

| Skill | Use it to |
| --- | --- |
| [duo-pattern](skills/duo-pattern/SKILL.md) | Lay out and navigate an app for iPhone Duo as a window over an ordered path of panes, so folding keeps the pane the user was on, with a tested Swift state owner and motion values fitted to the reference clip. |
| [reflex-pattern](skills/reflex-pattern/SKILL.md) | Design, build, migrate or continue Swift/Android apps, and optionally a web app, with typed core contracts, native persistence adapters, external APIs, offline/online sync, shared tests and resumable project state. |
| [post-deploy-watch](skills/post-deploy-watch/SKILL.md) | Discover recent merges, verify production exposure, and run a dedicated watch for each PR for at least two complete business dates. |

## Build native Swift and Android apps

```text
$reflex-pattern design a shared Swift core with SwiftData and Room adapters
$reflex-pattern convert this iOS repository into an Apple/Android monorepo
$reflex-pattern continue this project
$reflex-pattern add a web target on the same core
```

Each run starts from the project's `.reflex/` directory. The bundled `scripts/reflex_state.py` reports the phase and the next step, records each executed check per target with its evidence, marks a result stale when its sources change, and keeps decisions with IDs. A later run therefore continues from the files, with no chat history. The web target compiles the core to WebAssembly with JavaScriptKit's BridgeJS, which its authors mark experimental.

Its design guideline for navigation is the Duo pattern's rule applied to every target: the core owns one window over an ordered path of panes, and each host sets how many panes fit from its width. The iPhone rule is checked against the reference clips; the Android and web mapping is taken from vendor documentation and has not been run on a device.

Its data layer reference sets out the sync strategy for data the user can change: an edit is an outbox record laid over the server-confirmed row, never written into it, and eight rules keep the view consistent through app kills, lost requests and other people's edits. `assets/DataLayerCore.swift` models those rules for one resource with no imports, `assets/WritePathSimulation.swift` is a seeded simulation of the faults, and `assets/DataLayerTests.swift` holds one hand-driven test per rule and one control per rule that must fail when the rule is turned off. The rules were checked on that model, not against a real store, backend or device, and the browser store notes were observed in Chromium only.

The skill covers fresh projects, combining repositories and preserving an existing Apple package during migration. Its supporting references describe typed Swift/Kotlin contracts, native storage and migrations, sync recovery, API ownership, authentication, background work, platform services and testing. The guidance recommends architecture and verification steps; it does not supply a prebuilt application framework or sync engine.

## Lay out an app for iPhone Duo

```text
$duo-pattern adapt this app's navigation for iPhone Duo
$duo-pattern review this fold recording against the pattern
```

The skill encodes one rule: the app is a path of panes from general to specific, the closed device shows the last pane, the open device shows the last two, and a fold changes how many panes fit without changing which pane is last. `assets/PaneWindow.swift` implements that rule as a value type, and `assets/PaneWindowTests.swift` checks it against each clip in the Claude for iPhone Duo team's thread.

The motion values come from a frame-by-frame fit of an explainer animation, not from a device. The fold APIs are listed by name from the iOS 27.3 SDK; only the closed pose was run on the simulator.

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
