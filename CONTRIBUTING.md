# Contributing

## Setup
```sh
eval "$(mise env)"            # flutter 3.50.1, JDK 17 (see mise.toml)
export ANDROID_HOME=~/Android/Sdk
flutter pub get
```

## Checks before a PR
```sh
dart analyze                  # must be clean
flutter test --exclude-tags perf   # what CI runs
flutter test                  # everything; takes about 4 minutes
flutter test --tags perf      # timing benchmarks
```
`test/data/perf_test.dart` (tag `perf`) has time budgets that depend on machine load. If it fails while other work is running, rerun it alone before treating it as a regression.

Tests must not use the live network. The servers are only reachable from a BDIX-peered ISP, so CI never reaches them; use saved fixtures and fakes. Live smoke tools are opt-in and never part of `flutter test`:
```sh
WATCHDOG_LIVE=1 flutter test tool/skeleton_index_smoke.dart       # needs BDIX; uses a temp database
WATCHDOG_LIVE="3D Movies" flutter test test/index/live_smoke_test.dart
```

## Database schema changes
A schema change needs all of:
1. Bump `schemaVersion` in `lib/data/database.dart` and add an `if (from < N)` step to `onUpgrade`. Note that drift's `createTable` does not create `@TableIndex` indexes; call `createIndex` for each one.
2. Regenerate code and schema snapshots:
```sh
dart run build_runner build --delete-conflicting-outputs
dart run drift_dev schema dump lib/data/database.dart drift_schemas
dart run drift_dev schema generate drift_schemas test/data/generated
```
3. Extend `test/data/migration_test.dart` with a migration test from the previous version.

## Secrets and signing
Never commit `key.properties`, `*.jks`/keystores, API keys (including a TMDB key), tokens or any other credential. They are git-ignored; keep it that way. Release APKs must be signed with the same key as earlier releases or Android refuses the update.

## Parser corpus check
`tool/corpus_check.dart` replays a saved crawl through the parsers:
```sh
dart run tool/corpus_check.dart <dir containing tv.json and all.json>
```
Never commit crawl dumps, saved listings of real servers, or any personal data. Keep dumps outside the repo.

## Coding rules
- Discuss larger changes in an issue before writing code. Keep answers and commit messages terse.
- Small, targeted changes; no drive-by rewrites.
- Verify package APIs on pub.dev/docs before using them; do not guess.
- Never invent server data; test fixtures must come from real listings.
- UI code talks to `lib/data/repository.dart`; no drift types leave `lib/data`.
- Respect the decisions in `CLAUDE.md` (Flutter, media_kit, Apache-2.0).
- New dependency: check its license and add it to `docs/THIRD_PARTY.md`.

## Contact
Open an issue. Do not post emails or private data.
