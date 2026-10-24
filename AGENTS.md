# AGENTS.md — Tunes Automation Policy

Tunes is a private music library + player fed by Telegram channels, built for one person.
Two zones: `tunesd/` (TypeScript daemon on the box) and `app/` (Flutter on Android).

Before working on Tunes, read [`docs/SPEC.md`](docs/SPEC.md) — master product specification.
Spec wins on direction. On safety, privacy, or ban-safety, this policy wins.

**This repo ships an app + a daemon.** Definition of done: tests green, analyzer clean,
debug APK builds, UI changes signed off by a human screenshot review, E2E runs real (never
simulated). Prototypes live elsewhere.

---

## 1. Non-Negotiable Rules

- Do not delete, rename, reset, force-push, or rewrite `main`. Merging is human.
- Do not fabricate test results, SHAs, manifest hashes, or validation claims.
- **Never rewrite or re-encode source files.** The pipeline probes, tags metadata into
  its own records, and never transcodes. Loudness is applied at playback edge only
  (SPEC §1.7, §6). Files on disk are the channel's originals, full stop.
- **Files are content-addressed** (sha256 object store). Never build storage paths from
  names or message IDs; identity of a file is its sha, always (SPEC §2.1, §3).
- **MusicBrainz is enrichment, never identity.** Recording identity is a hierarchy
  (SPEC §1.2). An MBID match never by itself makes two files the same track.
- **The quality model is multi-dimensional** (losslessness / efficiency / measured
  bitrate / provenance / authenticity — SPEC §5). The D1–D5 dimensions and the
  spec-mandated example outcome are invariants; only the versioned weight table may
  change, and only with tests.
- **Streaming is first-class** (SPEC §1.8 → M3): the app streams undownloaded tracks
  via tunesd on demand. The app still never talks to Telegram — that boundary is
  absolute (SPEC §2.4, §13).
- **Ban-safety is sacred** (SPEC §4): rate limits, jitter, and daily caps are product
  features. Never "optimize away" delays for speed. Transport errors → stop and report,
  never retry-hot. This was learned the hard way in tg-curator.
- **Dedupe is never destructive by default.** Marking dupes yes. Deleting files only via
  explicit user action in the app.
- Quality model and identity must be deterministic: same input → same manifest hash
  (SPEC §5). Tiebreakers exist; do not invent new ones without a spec change.
- No secrets in the repo: no Telegram session files, no api_id/api_hash, no tokens.
  tunesd's session lives box-side in its config dir, gitignored. The app's endpoint
  address is user-configured at setup, never baked in.
- The app has no analytics, no ads, and no third-party trackers. **It does have an
  account and an authenticated service boundary** — product decision recorded
  2026-09-08 with Dylan and the advisor, superseding the previous "no accounts, no
  cloud, no WAN" rule. The app now reaches exactly two Tunes-operated destinations:
  the auth service, and the media origin behind Cloudflare (SPEC §1.5, §2.4). Adding
  any destination beyond those two still requires an explicit product decision
  recorded with Dylan first.
- **No reusable credential distributed with the APK grants access to the Tunes service
  or media. Every online media authorization is derived from an authenticated device
  session and expires automatically.** This is the invariant the auth implementation is
  held against; a design that cannot satisfy it is wrong regardless of how convenient
  it is. Possession of the APK is not authorization.
- The credential hierarchy, and where each one lives. Do not move any of them
  downward: the refresh token in particular must never land in SharedPreferences,
  the drift database, or a plain file.

  | Credential | Lifetime | Stored |
  | --- | --- | --- |
  | Refresh token | long, revocable server-side | Android keystore (`flutter_secure_storage`) |
  | Access token | ~10 min | memory only |
  | Media grant | ~4 h, one object | not stored |

  Media grants are **single-object capabilities, not short-lived credentials**. Four
  hours is longer than the access token on purpose — see SPEC §2.4 for why the
  client's eager playlist construction forces it, and what bounds the damage instead.
- Offline playback is never gated on authentication. A downloaded track plays with no
  network and no valid token, by construction — `trackUriFor` resolves a local path
  before any URL is built. Treat this as an invariant, not an accident.
- No channel content, message IDs, or filenames in logs or crash output. Log *where*
  something failed, never *what* it was.
- Domain logic (identity, quality, manifest application, dedupe) stays pure Dart in the
  app and pure functions in tunesd — zero Flutter/widget imports in app domain code.
- Schema changes (drift or manifest vN): typed migrations, tested, never destructive
  edits to released migrations.
- No new dependency without agreement first. Prefer removing code over adding a
  package for one small function.
- Do not silence analyzer, lint, or reviewer findings without a clear technical reason.
- Do not "fix" dead/commented code unless the task explicitly targets it.
- **Radio sequencing runs on-device and stays there** (`docs/RADIO.md`). It may
  read the listener's own play history and the local manifest. It must not
  upload a profile, rank by popularity, or reorder an explicit queue. Those
  three are what SPEC §13's old "no recommendation engine" rule was protecting,
  and they survive it.

## 2. Agent Workflow

Before editing:

1. Inspect branch and working tree state.
2. Identify the smallest safe change.
3. Read nearby code and existing patterns before creating abstractions.
4. Note whether the change touches identity/quality model, manifest schema, fetch discipline,
   Android manifest, or spec — those need callouts in your report.
5. One scoped change at a time. Respect milestone order (SPEC §11): don't jump ahead
   to later-phase features while earlier foundations are incomplete.

After editing:

1. `dart format` touched files (app) / `npx prettier` or repo formatter (tunesd).
2. `flutter analyze` / `tsc --noEmit` — zero new findings.
3. Narrowest relevant tests first, then broaden.
4. Report exactly what changed, was tested, was skipped, and why.

### Branching, Commits, Pushes

Agents are trusted to version their own work — you do not need to ask before
committing or pushing your own branch.

- Branch from `main`: `feat/*`, `fix/*`, `docs/*`, `test/*`, `chore/*`.
  Append issue number when one exists.
- Conventional commits (`feat:`, `fix:`, `perf:`, `ui:`, `docs:`, `test:`, `chore:`).
- Every change lands through a PR reviewed by a human. Never commit directly to `main`.
- Force-push only your own unshared branches.

## 3. Final Report Format

Every completed session reports:

```md
## Final Report

### Git State
- Starting branch/SHA:
- Final branch/SHA:
- Working tree status:
- Pushed: yes/no

### Files Changed
- `path`: summary

### Change Type
- Identity/quality model changed: yes/no
- Manifest or DB schema changed: yes/no
- Fetch discipline (limits/caps/state) changed: yes/no
- Android manifest or permissions changed: yes/no
- UI changed: yes/no
- Build config changed: yes/no
- Docs/spec changed: yes/no

### Validation
- Commands run:
- Tests passed / failed:
- E2E run: real/simulated (real required for M-gates)

### Risk Notes
- Remaining risks:
- Follow-up work:
```

Any "yes" must be justified under Risk Notes.

## 4. Architecture

```text
tunes/
├── tunesd/              # box daemon — TypeScript
│   ├── src/             # fetch, probe, identity, enrich, quality, manifest, serve
│   ├── data/            # object store (content-addressed, sha256)
│   ├── scripts/         # e2e-fetch.ts, health probe, one-off tools (tsx)
│   ├── test/            # vitest
│   └── package.json
├── app/                 # Flutter (Android)
│   ├── lib/
│   │   ├── core/        # theme, motion, navigation, database, logging
│   │   ├── features/    # library, search, now_playing, queue, downloads, settings
│   │   └── domain/      # quality display, identity resolution, manifest apply — pure Dart
│   └── test/
├── tools/deploy.sh      # wireless adb install loop (Faye pattern)
└── docs/SPEC.md
```

Dependency shape:

```text
core            ← depends on nothing
domain (app)    ← pure Dart only
data            ← may use domain, core
features        ← may use data, domain, core
tunesd (all)    ← TS, no Flutter anywhere
```

Identity/quality/manifest logic is the correctness core. Keep it pure, deterministic,
inspectable. No business logic inside widgets.

## 5. Fetch Discipline (Sacred — see SPEC §4)

- Defaults live in one config file, never spread across modules: per-channel delay,
  inter-download jitter, daily cap, scan cadence.
- All fetch state persists; restarts resume. A restart must never reproduce a download
  (sha256 + message-id index is the proof).
- Transport errors follow the tg-curator playbook: stop, probe, report. No hot retries.
- E2E fetches against synthetic/test channels only — never against live piracy channels
  from a dev box, and never from CI.

## 6. Testing Policy

Smallest relevant test first, then broaden.

| Category                       | Rule                                            |
| ------------------------------ | ----------------------------------------------- |
| Identity/quality unit tests       | Always run; determinism + tiebreak mandatory    |
| Manifest/migration tests       | Required for every schema step, both directions |
| Fetch state replay tests       | Required (restart-without-dupes is an invariant)|
| Widget tests                  | Required for nontrivial app interactions        |
| Golden tests                   | Library, Now Playing, Album detail              |
| Device/E2E checks              | Reported as manual with output, never as automated proof |

No test depends on network or a specific physical device (except explicit E2E scripts,
which are named `e2e-*` and never run in CI). Never delete or weaken a failing test to
make a run green.

## 7. Build System

tunesd:

```bash
npm install
npm test            # vitest
npx tsc --noEmit
```

App:

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # after touching drift
dart format lib test
flutter analyze
flutter test
```

This repo's dev box has 3.7 GB RAM. APK/AAB builds run on GitHub Actions runners,
not locally. If a local build is unavoidable, cap Gradle memory explicitly and expect
slowness — do not tune CI down to match the laptop.

## 8. Deploy & Release

- Debug APK from CI; `tools/deploy.sh` downloads newest success → `adb install -r` →
  launch. Wireless pairing: `~/dev/platform-tools/platform-tools/adb` (system adb lacks
  mdns auto-connect; port changes each session).
- Signing key: `app/android/app/tunes-debug.keystore`, the key every installed
  Tunes is signed with. Never committed (the repo is public since 2026-10-24):
  CI writes it from the `TUNES_KEYSTORE` secret, a dev box keeps a local copy.
  Without it Gradle signs with Android's stock debug key (installs fresh only).
- Channels: dev → beta → stable. Tags on `main` only, annotated, `v0.x.y`.
- Changelog per release: what changed, why it matters, whether anything needs
  attention. Raw commit logs are not a changelog.