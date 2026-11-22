# Contributing

## Setup
```sh
eval "$(mise env)"            # flutter 3.50.1, JDK 17 (see mise.toml)
export ANDROID_HOME=~/Android/Sdk
flutter pub get
```

## Checks before a PR
```sh
dart analyze
flutter test --exclude-tags perf
flutter test --tags perf      # timing benchmarks; run separately, results depend on machine load
```
Network tests are opt-in. The servers are only reachable from a BDIX-peered ISP, so CI never reaches them.

## Parser corpus check
`tool/corpus_check.dart` replays a saved crawl through the parsers:
```sh
dart run tool/corpus_check.dart <dir containing tv.json and all.json>
```
Never commit crawl dumps, saved listings of real servers, or any personal data. Keep dumps outside the repo.

## Coding rules
- Small, targeted changes; no drive-by rewrites.
- Verify package APIs on pub.dev/docs before using them; do not guess.
- Never invent server data; test fixtures must come from real listings.
- UI code talks to `lib/data/repository.dart`; no drift types leave `lib/data`.
- Respect the decisions in `CLAUDE.md` (Flutter, media_kit, Apache-2.0).
- New dependency: check its license and add it to `docs/THIRD_PARTY.md`.

## Contact
Open an issue. Do not post emails or private data.
