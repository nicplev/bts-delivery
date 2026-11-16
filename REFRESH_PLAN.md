# BTS Delivery refresh — implementation plan and checklist

Date: 16 November 2026. Baseline: `d1b2a3d`.

## Ownership and working agreement

- Astra 6 orchestrates, challenges designs, reviews diffs, and checks evidence.
- Sol 6.1 implements changes in bounded workstreams.
- Preserve existing school records, local pending work, and Firebase configuration.
- Work locally on a refresh branch. Production deployment and data migration are separate rollout gates; this checklist must not imply they happened.
- Mark work complete only with implementation and verification evidence. Record blocked validation explicitly.

## Outcomes

1. Staff can record classroom delivery work without waiting for reception.
2. Saved local work survives navigation, app termination, and restart.
3. The UI distinguishes saved on this device, waiting to sync, synced, and action required.
4. Reconnection safely retries work without duplicates or overwriting another person's unrelated changes.
5. Repeat visits and corrections preserve signed evidence and historical records.
6. Daily screens load bounded, relevant data and expose the next useful action.
7. Server permissions enforce roles independently of what the UI displays.

## Evidence from the initial review

- Sign-off uploads a signature before persisting it (`signoff_tab.dart`); its storage path is reused.
- A general Hive queue and a separate completion store exist, but their enqueue APIs are not wired into normal editing paths.
- Photo persistence exists, but completion/retry is owned by a classroom widget and stops after navigation.
- Queue entries marked processing are excluded on restart; failed operations must never be discarded as completed.
- Connectivity reports a network interface as online without checking server acknowledgement.
- Classroom updates submit whole models; summaries and signatures use school-scoped mutable identifiers.
- Delivery calendar reads all deliveries before filtering; several school providers retain subscriptions and aggregate nested collections serially.
- User documents permit self-role changes; staff linking permits broader changes than its comment describes.
- Manager timer stops write admin-only history; timer read-then-write paths can race.
- Flutter tests are currently blocked by local SDK/environment issues. Functions TypeScript builds.

## Phase 0 — reproducible baseline

- [x] Create isolated refresh branch; retain clean baseline (`codex/app-refresh`).
- [x] Establish working Flutter/Dart test environment without upgrading the user's global SDK in place (existing Flutter 3.44.6 / Dart 3.12.2).
- [x] Record baseline test/analyzer failures and distinguish pre-existing failures (17 tests pass; 38 informational analyzer diagnostics, no reported errors/warnings; analyzer then encounters a telemetry-file permission failure).
- [x] Add repeatable local validation instructions and emulator setup.

## Phase 1 — permissions and backend correctness

- [x] Independently trace role escalation, staff linking, school access, calendar access, and timer permissions before edits (separate Astra investigation reconciled with parent review).
- [x] Prevent self-granted privileged roles and unauthorized staff-field changes; preserve legitimate onboarding and admin management.
- [x] Align app queries, assignment identity, and backend access policy; do not deploy restrictive rules that break valid queries.
- [x] Fix unassigned staff calendar exposure and deleted/reassigned delivery metadata updates.
- [x] Make timer transitions concurrency-safe and retry-safe; reconcile manager history permissions.
- [x] Add emulator regression cases for denied escalation and allowed legitimate flows.
- [x] Astra review of permission changes and compatibility; no live rule deployment during implementation.

## Phase 2 — reliable offline work and evidence capture

- [x] Establish one app-owned persistent upload/operation lifecycle instead of widget-owned uploads.
- [x] Persist signatures and photos before networking; retain files until remote metadata is acknowledged.
- [x] Resume pending work after restart, navigation, reconnect, and foreground entry.
- [x] Use stable operation and storage identifiers; retries must not create duplicate evidence.
- [x] Recover interrupted queue entries, retain failed work with errors, and implement bounded retry/backoff.
- [x] Bind pending work to its originating user and prevent cross-account uploads.
- [x] Show reactive pending/error counts and distinguish connectivity from acknowledged synchronization.
- [x] Audit core field edits for local-save feedback, narrow updates and atomic related writes (rename/status, classroom notes, actual consumables, pack-count additions and loading checklist).
- [ ] Complete the separate review of administrative/template forms and unused school-note APIs.
- [x] Test restart, failed metadata write, retry, account change, cancellation, and reconnect behavior.

## Phase 3 — audit history and repeat deliveries

- User decision: **each visit has separate quantities and completion**, confirmed during implementation. School contacts/maps and reusable expectations remain separate from visit work.
- Visit workspace contract: `deliveries/{deliveryId}/workspace/{schoolId}`; server preparation copies expectations and resets progress, excluding historical notes/photos/signatures/timers. A ready manifest gates access. A separate device preparation check must verify local availability.
- New route family: `/deliveries/:deliveryId/schools/:schoolId/...` with immutable repository/provider scope; no global mutable active-visit state.
- [x] Implement idempotent server preparation and manifest, plus scoped rules.
- [x] Route all operational reads/writes, photos, notes, timers, and sign-off snapshots to the selected visit.
- [x] Verify two visits at the same school cannot alter one another's progress or evidence.
- [x] Preserve each signature at a unique path and append signed snapshots instead of overwriting previous evidence.
- [x] Make snapshot failures explicit; incomplete summaries cannot silently become authoritative signed records.
- [x] Associate new evidence with a delivery/visit identifier where context is available; retain legacy school records.
- [x] Define correction/re-sign workflow and preserve prior versions.
- [ ] Specify and implement compatible reads and a dry-run migration/report for historical school-only records; never guess which visit owns ambiguous history.
- [x] Add regression coverage for two visits to the same school and signing while data changes.

## Phase 4 — daily UI/UX

- [x] Make today's deliveries the default with calendar access retained.
- [x] Provide clear empty, error, stale/offline, and retry states; remove endless error spinners.
- [x] Put sync state at school/classroom points of work, not just home/profile.
- [ ] Reduce navigation friction for classroom status, counts, photos, notes, and next classroom.
- [x] Preserve drafts and pending work in common classroom delivery forms when navigating away.
- [ ] Extend draft preservation to remaining setup/administrative forms.
- [ ] Keep role-appropriate actions, accessible labels, touch targets, and readable status text.
- [x] Verify common field forms at 320 px / 1.8× text with keyboard in widget tests, and native visit/media/recovery flows on iPhone 17 Pro.
- [ ] Complete exhaustive phone layouts, long content, accessibility and physical-device keyboard checks.

## Phase 5 — performance and maintainability

- [x] Bound calendar/date queries and history; avoid downloading all seasons for daily work.
- [x] Scope school access/query subscriptions and dispose unused detail listeners.
- [x] Reduce serial aggregation reads while preserving accurate error reporting.
- [x] Review export date filtering and incomplete-data behavior.
- [ ] Add crash/error reporting with no signatures, tokens, or sensitive payloads in logs.
- [x] Update dependencies deliberately after a passing baseline; document any deferred breaking upgrades.
- [ ] Record measurable performance baseline and budgets on representative data rather than claiming unmeasured speedups.

## Phase 6 — integration and rollout gates

- [x] Run focused unit/widget tests and Firebase emulator rules/backend tests.
- [x] Run analyzer and Functions build; review final diff for regressions and unwanted generated files/secrets.
- [ ] Exercise two-device concurrent classroom edits and timer transitions.
- [ ] Exercise airplane mode, connected Wi-Fi without internet, reconnect flapping, process kill, and reopening offline.
- [ ] Verify no acknowledged local work disappears and no operation is applied twice after retry.
- [x] Document completed work, remaining limitations, migration prerequisites, and deployment sequence.
- [ ] Production rollout only after rules/client compatibility and data migration have been reviewed; record deployed versions separately.

## Acceptance targets (to measure, not assumed achieved)

- Local delivery action shows saved/pending feedback within 250 ms on the test device, excluding camera capture/compression.
- Cached daily/school view remains usable offline without a blocking network spinner.
- Connected peer sees acknowledged classroom updates within 2 seconds on a healthy connection.
- Pending work survives restart and retries automatically when the app can execute and the backend is reachable.
- All critical permission, offline recovery, duplicate retry, and historical-evidence regression cases pass before release.

## Implementation journal

- Planning: completed code-path review and created this checklist before implementation. No production changes made.
- Baseline: resolved dependencies with the existing Flutter 3.44.6 SDK. Only SDK-pinned transitive `meta` and `test_api` versions changed. Flutter's existing 17 tests pass. The baseline analyzer reports 38 information-level diagnostics, then fails to write its telemetry file; this is not a successful analyzer exit or clean-lint claim. Final analysis will run with appropriate cache access.
- Environment: Firebase default database is Standard edition, Native mode, region `nam5`, confirmed read-only. Use current database compatibility; do not provision a replacement database.
- In progress: Sol 6.1 offline evidence lifecycle, daily workflow/query scope, and backend permissions/correctness. Astra reviews boundaries and integration.
- First offline slice: five focused tests passed covering reopen/reconnect, failed metadata persistence, account-switch cancellation, pause/resume, and preservation/migration of legacy pending photos. Final integration is still pending.
- First daily workflow slice: ten focused tests passed, including 360 px width and 1.7× text, regular/admin/manager workflows, scoped date queries, listener cancellation, aggregation failures, and mismatched quantity units. Removed an obsolete icon dependency that failed to compile with the working SDK.
- Backend compatibility decision: new server-owned `staff_access` documents establish trusted links. Existing client-editable roles/links cannot be blindly trusted. A reviewed access migration and newly issued calendar subscriptions are rollout prerequisites; neither has been applied to production.

## Validation commands and environment

Run from the repository root with enough free disk space. Never substitute the production project ID in emulator tests.

```sh
/Users/nicplev/Library/development/flutter-3.44.6/bin/flutter pub get --offline
/Users/nicplev/Library/development/flutter-3.44.6/bin/flutter test --no-pub --concurrency=1
/Users/nicplev/Library/development/flutter-3.44.6/bin/flutter analyze --no-pub
npm --prefix functions test
JAVA_HOME=/opt/homebrew/opt/openjdk@21 PATH=/opt/homebrew/opt/openjdk@21/bin:$PATH npm --prefix functions run test:emulators
git diff --check
```

The emulator suite uses synthetic `demo-bts-delivery` data on Auth 9099, Firestore 8080, Storage 9199 and Functions 5001. It refuses non-local service hosts. Java 21 is required by the installed Firebase CLI. Start all four services, rather than the Functions-only development script, when manually exercising the app.

Debug builds select the synthetic project using `--dart-define=BTS_FIREBASE_EMULATOR_HOST=127.0.0.1`; iOS also requires the native demo flag and isolated bundle identifier listed in the reproduction section below. Use a separate demo installation with no production queue. The Dart define is rejected outside debug mode. Local `.env` and generated platform configuration are still required to build; do not commit real credentials or generated Firebase configuration.

## Baseline checkpoint evidence and practical limits (bfa5ed6)

This records the first refresh checkpoint. The continuation below supersedes its native-build, ordinary-edit recovery, draft and media limitations; remaining release gates still apply.

- Combined Flutter suite: **46 tests passed**, including photo-retention integration, connectivity/assignment gate behaviour and two account-switch stream tests. Includes a real router flow through two separate visits at one school, and blocking an unprepared offline visit before its work repository opens.
- Final whole-repository analyzer: **zero errors, zero warnings, 26 informational diagnostics** (three existing application lints and 23 print notices in the legacy migration script). The default analyzer exit is 1 because informational diagnostics remain. Focused changed-code analysis passed. This is not a zero-diagnostic claim.
- Focused offline tests cover retained upload checkpoints, retry after metadata failure, account-switch cancellation, preserved legacy evidence, duplicate signature IDs across restart, immutable capture data, and export handling of cached/corrupt snapshots.
- Snapshot immutability tests freeze client capture content. They do not establish a simultaneous database snapshot while other devices edit source documents. The UI deliberately describes a source read, not independent verification.
- Fresh Astra postpatch review found photo delete/recreate could change media behind a signed snapshot, and staff could still mutate reusable school expectations. Sol fixed both, added emulator regressions, and Astra independently confirmed both findings closed. Removing a classroom photo now removes live metadata while retaining its immutable image for earlier signed evidence.
- Native simulator build/run could not complete: MobileBuild connection closed during build, and the startup volume reached approximately 100 MiB free. Only this task's generated temporary build/cache files were removed. No native visual pass or device performance claim is made.
- Re-entry currently refreshes the visit's nested records before confirming preparation; latency and read cost must be measured with representative school sizes. Templates over 499 copied child documents are explicitly rejected by atomic preparation; they require a larger-school preparation design before rollout to such schools.
- Classroom rename/status uses narrow fields and local/remote acknowledgement. Rejected-edit notices survive navigation within a running session, but their recovery state is not durable across process termination. Other ordinary notes/count forms still need a complete offline interaction and draft-preservation pass.
- Evidence queue state is durable. It is not a universal sync acknowledgement for Firestore writes. Map/photo binary downloads are not included in visit readiness. iOS background suspension may defer uploads until the app runs again.
- Larger dependency upgrades, crash reporting, persistent rejected-edit recovery, general form drafts, archive/cancel flows, exhaustive phone/keyboard layouts, and measured performance remain open checklist work.

## Rollout prerequisites — no production changes performed

1. Snapshot/backup existing data and inventory client versions. Run the read-only `node functions/scripts/staff-access-dry-run.cjs <projectId>` report separately against the intended project only when performing the rollout review.
2. Independently verify each Auth UID-to-staff pairing, role, and school assignment against the real roster. Legacy client-editable role/link fields cannot authorize the migration. Seed reviewed reciprocal `staff_access` mappings, including at least one administrator, using a controlled administrative procedure.
3. Rehearse a coordinated maintenance-window release: stop legacy writes, apply compatible restrictive rules and indexes, verify Storage-to-Firestore permission setup, provision reviewed access mappings, deploy Functions, and distribute the refreshed client. Old clients are incompatible with the new permission model. Do not stage this as an unattended rules-only deployment.
4. Retire exposed legacy staff PINs/calendar tokens and issue new protected calendar subscriptions. Existing exported Storage bearer URLs require separate review/rotation if they were exposed.
5. Keep historical school summaries separate; do not infer which repeat visit owns ambiguous historical records. Prepared visits cannot be hard-deleted or reassigned to another school. Archive/cancel remains a separate workflow to implement.
6. Run the physical-device and two-device acceptance matrix before broad release. Record actual deployment versions and date separately from this local checklist.

The new access rules are prototype release candidates. They enforce server-owned staff links, role and school scope, validated visit work, and protected evidence, but still require release verification with the real reviewed access roster and native clients before broad use.

- Backend final checkpoint: 10/10 synthetic Firebase emulator tests and 3/3 Functions unit tests passed, with a successful TypeScript build. Emulator cases exercise reciprocal links, role/assignment scope, prepared visit isolation, template protection, immutable files including retained photos after live metadata removal, sign-off rules, calendar rotation/scope, and atomic timer/auto-stop history. The scheduled Pub/Sub wrapper was not run; its transaction helper was exercised directly.


## Remaining implementation and release sequence

1. Complete administrative/template form review, remaining navigation/accessibility improvements, archive/cancel and privacy-conscious crash reporting.
2. Benchmark first/repeat visit preparation and local-save feedback using representative school data. Expand atomic preparation beyond 499 child documents if real school sizes require it; retain the no-partial-ready invariant.
3. Complete historical school-only record inventory/migration reporting and workbook visual verification. Review larger dependency upgrades separately.
4. Run two-device and physical-phone reception, camera, low-storage, restart and reconnection-flapping tests. Simulator outage evidence below covers only the tested subset.
5. Rehearse the reviewed identity/access migration and coordinated release above. Keep unchecked items open until their evidence exists.

## Continuation — offline recovery and deliberate media downloads

Baseline for this increment: `bfa5ed6` on `codex/app-refresh`. Requested 16 November 2026. Astra orchestrates/reviews; Sol 6.1 implements. Disk availability at restart is approximately 5.3 GiB; native verification will be retried after implementation.

Design constraints:
- Preserve a durable, account-bound copy of ordinary edit intent before submitting it. Firestore remains responsible for its native pending writes. A recovered intent with uncertain acknowledgement must not silently replay over newer team changes; expose comparison/review and an explicit retry where needed.
- Bound form save waits and distinguish saved locally, acknowledged, rejected, and unconfirmed. Stable document IDs and atomic related writes prevent duplicate note/count creation or partial classroom metadata updates.
- Preserve practical field-form drafts by account and visit, including notes and recorded counts. Explicit discard is separate from navigation/dismissal; a failed local save must remain visible.
- Offline media is deliberate, separately reported from classroom-record readiness, scoped to the signed-in account and visit, and limited in disk use. Download with bounded concurrency into temporary files, publish only complete verified files, and retain interrupted/failing status for retry.
- Prefer authenticated Firebase Storage references for the configured bucket. Do not turn stored arbitrary URLs into unrestricted download requests. Cache keys distinguish mutable map versions; downloaded media must never mix between accounts or visits.
- Removing downloaded copies cannot remove pending uploads or remote signed evidence. Offline image/PDF viewers must use verified local files without first fetching a download URL.

Checklist for this increment:
- [x] Persistent ordinary-edit recovery store, restart reconciliation, account isolation, and review/retry UI.
- [x] Local acknowledgement and atomic saves for core field notes/count/checklist operations; preserve unrelated fields.
- [x] Durable drafts for common delivery forms with restore/discard behaviour.
- [x] Per-visit media inventory, download progress/retry/cancellation, and bounded local cache.
- [x] Classroom photos and school map/PDF views use downloaded media offline.
- [x] Regression tests for uncertain acknowledgement, newer remote edits, crash/restart, account changes, interrupted downloads, stale map versions, missing files, and cache limits.
- [x] Independent Astra review of recovery and media paths; resolve actionable findings.
- [x] Full Flutter tests, analyzer, relevant backend checks, and native demo verification if tooling permits.
- [x] Update operator/offline documentation and save a reviewed local checkpoint.


Continuation journal (verified local checkpoint):
- Core recovery covers classroom rename/status, classroom note create/edit/delete, actual consumable counts, pack-count append and loading-checklist marks. Expected/configured consumable editing and unused school-note APIs remain outside this slice.
- Drafts are persisted separately from submitted edits, with revision-scoped removal and stable operation IDs. Unsaved keystrokes during the visible “Saving draft…” interval are not claimed durable.
- Media cache limits: 25 MiB/file, 200 MiB across accounts on the device, one native writer, bounded inventory reads. Earlier map copies remain accessible with explicit older-copy labels. Clearing downloaded media is separate from pending uploads and retained edits.
- First combined run exposed seven deterministic media-test failures caused by macOS file timestamp precision differences; using the same stat representation corrected them, followed by a passing focused run. Final combined verification passed all 76 Flutter tests.
- Native build now compiles, installs and launches the isolated demo on iPhone 17 Pro / iOS 26.5. Fixed native Firebase demo initialization/key format and app-only bundle identifier overrides. Debug/simulator builds skip crash-symbol upload; production configuration is unchanged.
- Native dashboard navigation exposed a scope bug masked by earlier declarative-route tests. The actual Open school action must retain visit scope through classroom navigation and dialogs. The fix gates and scopes every visit page directly; the regression now taps the real Today card and verifies two visits remain isolated. Native retesting confirmed the route and scope fix before any delivery writes.

- Final verification: **76/76 Flutter tests**, **11/11 Firebase emulator cases**, and **3/3 Functions unit tests** passed; TypeScript build passed. Whole-repository analyzer reports zero errors/warnings and the same 26 baseline informational diagnostics (default exit 1). Diff whitespace check passed.
- Fresh Astra review closed the identified recovery durability/admission race, media integrity/removal/earlier-map issues, review-sheet navigation and visit-route scope findings. Sol 6.1 implemented the fixes.
- Native evidence: isolated demo on iPhone 17 Pro / iOS 26.5 signed in as synthetic field staff, opened the actual Today card and downloaded **2/2** media files (PDF map and JPEG classroom photo). With only this demo's backend processes paused, a force-stop/relaunch opened both downloaded files locally and restored an unfinished **12 packs** draft. Saving returned a local pending state. A second force-stop/relaunch retained the saved-edit review. On backend recovery, server comparison matched the intended values, and Open classroom dismissed both review layers correctly.
- Independent emulator read after reconnect confirmed first visit `incomplete / actualPacks: 12`; second visit remained `notAttended / actualPacks: null`. This demonstrates this tested operation's restart/reconnect and visit isolation; it is not a universal exactly-once guarantee for every operation.
- Remaining acceptance: physical airplane/radio changes, connection flapping, camera capture, low storage, simultaneous phones, representative school latency/read costs, and remaining setup/admin forms. No production deploy, real-account migration or GitHub push is included in this increment.

### Reproducing the isolated native demo

Start the four local emulators for `demo-bts-delivery`, then seed the synthetic fixture:

```sh
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 \
FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
FIREBASE_STORAGE_EMULATOR_HOST=127.0.0.1:9199 \
node functions/scripts/seed-offline-demo.cjs
```

The seed uses only fixed localhost emulator endpoints and synthetic accounts; existing fixture edits and delivery dates are preserved. Its output supplies the fake sign-in accounts. It refuses missing emulator hosts or a conflicting project setting. Syntax, refusal paths and a repeat run against the existing demo were checked; both visit records and update times stayed unchanged (first count 12, second null). Fresh creation was checked against the preparation schema but has not been rerun against an empty emulator.

For the iOS Debug build, set all three together:

- Dart define `BTS_FIREBASE_EMULATOR_HOST=127.0.0.1` (Xcode `DART_DEFINES=QlRTX0ZJUkVCQVNFX0VNVUxBVE9SX0hPU1Q9MTI3LjAuMC4x`).
- Xcode `SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG BTS_FIREBASE_DEMO` so native Firebase initializes the same synthetic project before plugin registration.
- Xcode `BTS_APP_BUNDLE_IDENTIFIER=com.nicplev.btsdeliveryapp.refreshdemo` for a separate demo installation. Do not override `PRODUCT_BUNDLE_IDENTIFIER` globally, which also changes Pod framework identifiers.

Keep production and demo queues separate. Never pause or reset another project's services while simulating an outage. Debug demo analytics is disabled, and debug/simulator builds skip crash-symbol publishing. Release configuration remains unchanged.
