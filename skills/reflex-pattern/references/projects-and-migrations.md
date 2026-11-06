# Projects and migrations

Select the route that matches the supplied repositories. Preserve approved platform and core choices. A native Android port can use Kotlin/Compose with a shared Swift core; it does not require rewriting SwiftUI in Kotlin.

## New Apple and Android projects

Start with one observable journey and its typed state/action contract. Choose data authority and online/offline behaviour for that journey. Inspect the installed compiler, SDKs and native build tools before choosing the first build targets. Build the UI-free core and a persistent host CLI, then connect an Apple demo and an Android demo to that owner. Make the same input and expected result run through the core and both native interfaces. A pair of empty projects does not prove the architecture.

For a new monorepo, this is one usable layout:

```text
Package.swift
Sources/AppCore/
Sources/AppCLI/
platforms/apple/
platforms/android/
contracts/core/v1/
contracts/api/
tests/behaviour/
tests/mobile/
```

Set Swift target paths explicitly when sources live outside SwiftPM's conventional directories. Keep the root package entry point when consumers install from the repository root.

Keep generated Swift/Kotlin boundary code reproducible from the chosen schemas. Give each platform's repository its own native models and migrations. The core/API contract version and SwiftData/Room schema versions are separate. Use [typed contracts](typed-contracts.md) and [persistence and sync](persistence-and-sync.md) before adding storage or replication.

If the user wants two repositories, give the shared core a clear owner and distribution path. The Apple repository can own a source package that publishes Android artifacts, or an existing shared package can own both. Pin the core and test-contract versions in both repositories. Do not create an additional repository solely to fit this example.

Choose one canonical shared test suite and make both repositories run the relevant version. Distinguish a source change being merged from both platform consumers receiving it.

## Convert an existing iOS repository into a monorepo

1. Inventory public library products, minimum OS versions, package URLs, pinned revisions, targets, schemes, snapshots, resource bundles and build scripts. Include macOS if supported.
2. Record current dirty files and existing test failures. Use an isolated branch or worktree when local work would otherwise mix with the migration. Preserve user changes in the source checkout.
3. Extract the portable target before changing layout broadly. Keep source-compatible exports or adapters for existing public types. Build a small external consumer using the original import and package URL shape.
4. Add Android and shared contracts alongside the Apple implementation. Move Apple directories only where the move improves ownership or tooling. An operational monorepo does not require renaming every directory.
5. Update manifest paths, XcodeGen inputs, generated Xcode projects, scheme references, script working directories, CI path filters and documentation together. Preserve resource and snapshot lookup relative to their new source paths.
6. Run the existing semantic tests and build each supplied Apple demo. Preserve supported macOS checks. If the package has no demo, use a small independent public consumer to verify its import, initializers and resources. Add Android as a required consumer of the shared core rather than a copied implementation.

Inventory existing SwiftData/Core Data stores and CloudKit or custom-server sync before moving persistence ownership. Preserve stable domain IDs, pending edits, relationship semantics and account mapping. Adding Room does not migrate or synchronize an Apple store. Build explicit adapter mappings and test actual released-store upgrades.

For a sync-authority change, define data export/backfill, identity mapping, duplicate prevention, legacy-client coexistence, cutover and rollback before enabling a second writer. Disabling CloudKit and starting a REST queue does not transfer existing iCloud data. An iCloud identity is not automatically the same identity as an application's backend account. Stage changes per dataset or account using a defined authoritative path, and preserve the existing sync path until the replacement's migration contract is ready.

Do not remove a working Apple feature because the first Android implementation lacks an equivalent. Track the feature until it has an implementation and platform evidence or the user explicitly changes scope. A smallest-useful-increment request can stop after one verified journey; list the remaining migration work instead of declaring full parity.

## Combine two existing repositories

Inspect both repositories before choosing a destination. Record source commit IDs, licenses, package coordinates, release tags, CI requirements and dirty scope. Identify conflicting root files and generated paths before importing files.

Choose an import method that matches the requested history requirements:

- A snapshot import can preserve a provenance record mapping each imported subtree to its source commit.
- A history-preserving subtree import or merge can retain source commits without rewriting the original repositories.

Do not run history-rewriting filters or delete source repositories as part of ordinary consolidation. Keep remotes and publication coordinates unchanged unless the user requests changing them. Verify private dependency access in the new checkout and CI context.

After import, run each platform's existing checks before core extraction. Resolve overlapping implementations against the agreed contract and shared journeys. Similar class names do not establish equivalent behaviour.

## Completion evidence

Record the source revisions, resulting layout, public compatibility checks and commands for building each host. Include a clean consumer build, one shared behaviour journey on every core host, one mobile journey on both native apps and platform-specific checks that remain required. List untested features and pre-existing failures separately from new regressions.
