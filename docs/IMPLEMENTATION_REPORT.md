# Implementation Report

This follows the 9 phases in `MASTER_DEVELOPMENT.docx`. The brief assumes an existing Flutter codebase. The provided APK was a third-party native app, so Phase 1 audited the APK (see `AUDIT.md`), and Phases 2–9 describe the new Flutter app built to replace it.

## Verification status

| Check | Status |
|---|---|
| `flutter pub get` / `flutter analyze` / `flutter test` | **Not run.** No Flutter or Android SDK was available in the build environment, and package downloads were blocked. |
| Static checks performed instead | All relative imports resolve. No unused project imports (scripted check). All 175 string keys exist in en/fa/ps with matching placeholders (scripted check). Manual review of every file for API and null-safety issues. |
| Device testing | Not possible here. |

Nothing in this report claims a measured performance number. Profiling with DevTools in profile mode is the first thing to do after building.

## Phase 2: Architecture & code quality

- Feature-first folders, MVVM (`ChangeNotifier` view-models), repository and service layers, and a composition root in `app/dependencies.dart` using constructor injection.
- Immutable models (`Album`, `VaultItem`, `NewItem`, `AppSettings`).
- Centralised errors: every layer throws `AppException(kind)`. `describeError` maps each kind to a localised message. Global `FlutterError.onError` and `PlatformDispatcher.onError` handlers are in place.
- Centralised logging (`AppLogger`): disabled in release and never given file names, PINs or keys.
- Shared widgets: glass panel, skeletons, empty/error states, feedback, progress dialog, album chooser, item actions. The album grid and the viewer use the same actions.

## Phase 3: Database

- SQLite with versioned, transactional migrations (`AppDatabase._migrations`).
- Composite indexes for each sort order (`album_id, added_at, id`, …) plus a partial index for favourites.
- **Keyset pagination** (no `OFFSET` scans) with an `id` tie-breaker. The tests verify every item appears exactly once for all sorts.
- One query loads albums with counts and covers (no N+1).
- Batched moves and deletes run in transactions. All SQL is parameterised. `LIKE` wildcards are escaped.
- Debounced search (300 ms). A generation counter discards results of stale queries.
- Integrity: `PRAGMA quick_check` and file↔row reconciliation (`VaultService.checkIntegrity`). This runs silently after unlock and on demand in Settings.

## Phase 4: Performance & memory

- All file encryption and decryption runs on background isolates (`Isolate.run`). Thumbnails (~30 KB) are decrypted on the UI isolate to avoid isolate spawn cost, with an LRU cache (400 entries) and in-flight de-duplication.
- Images decode at tile size (`cacheWidth`) in grids and at ≤2× screen size in the viewer. The viewer keeps at most 5 decrypted neighbours.
- Lazy `GridView`/`SliverGrid` builders, `RepaintBoundary` around blur and shimmer, `context.select` to rebuild only on the fields used, `const` widgets throughout.
- Video and audio decrypt only when their page is active. Temp files are deleted on dispose and wiped on lock and start.
- Startup: prefs, paths and the database open in parallel. No SDK initialisers run.
- Release: R8 minify and resource shrinking enabled. No ad or analytics SDKs.

## Phase 5: Design system

`core/design/tokens.dart` holds spacing, radii, icon sizes, motion durations, component sizes, brand gradient and shadows. `app_theme.dart` defines Material 3 light and dark themes from one seed colour, with deeper OLED-friendly dark surfaces and consistent cards, dialogs, sheets, inputs, buttons and snackbars. Theme mode (system/light/dark) persists.

## Phase 6: UI/UX, icons, loading, animation

- Material Symbols (rounded) icon family only, with consistent sizes from `IconSizes`.
- Launcher icon (adaptive, monochrome, round, legacy) and Android 12+ and legacy splash screens.
- Skeleton grids that match the real layouts, shimmer, button-level spinners, progress dialogs with real counts, empty states with actions, error states with retry, pull-to-refresh.
- Animated selection (scale + check), fades, `AnimatedSwitcher` gate transitions, shake on wrong PIN, haptics (can be turned off), and reduced-motion respected (shimmer stops, slideshow jumps).

## Phase 7: Security, accessibility, reliability

- Security: see README §4 and AUDIT §8.
- Accessibility: 48 dp minimum touch targets (PIN keys are 72 dp, tested with `androidTapTargetGuideline`), semantics labels on tiles, keys and albums, live region for PIN entry, hardware keyboard support on the PIN pad, scrollable layouts for large fonts and landscape, RTL layouts for Dari and Pashto.
- Reliability: atomic writes (`.part` then rename), items removed from the vault only after a successful restore, no success message unless the operation succeeded (batch results report real ok/failed counts), duplicate-tap guards (`SingleFlight`, busy flags), and auto-lock suspended during system dialogs so a picker never locks you out mid-task.

## Phase 8: Tests (`test/`)

| File | Covers |
|---|---|
| `crypto/vault_cipher_test.dart` | Round-trips at chunk boundaries, streaming files, tamper detection, truncation detection, wrong key or id, re-encryption, metadata-only reads. |
| `auth/auth_repository_test.dart` | No default PIN, PIN never persisted, unlock, escalating persistent lockout, recovery and credential reset. |
| `data/repositories_test.dart` | Schema and indexes, album counts and covers, keyset pagination for all sorts, LIKE escaping, batch move, cascade delete. |
| `vault/vault_service_test.dart` | Isolate decryption, delete with progress, rotation, integrity repair, foreign-file safety, key zeroing, backup export → import into a different vault (byte-exact, wrong-password rejection). |
| `widgets/widgets_test.dart` | PIN pad behaviour, tap-target guideline, RTL rendering, dark theme. |
| `l10n/strings_test.dart` | Translation completeness and placeholders, RTL flags, settings persistence. |

Not included: integration tests on a device, such as gallery permission and MediaStore delete dialogs. These need a physical phone.

## Phase 9: Release

- `applicationId com.safevault.app`, `minSdk 24`, target/compile SDK from Flutter.
- Release signing via `android/key.properties` (template provided), falling back to the debug key.
- The manifest declares only the permissions in use. `INTERNET` is present only in debug/profile manifests for tooling.
- `allowBackup=false` and data-extraction rules exclude everything.

## Breaking or behavioural differences vs. the reference app

| Change | Reason |
|---|---|
| No default `0000` PIN; setup is mandatory | Security. |
| Locked files are re-encrypted, not just moved | Security. Old Safe Gallery data can't be imported directly. Unhide it there first, then hide it here. |
| No dialer launch, web-image lock, widget or ads | See AUDIT.md, "Features intentionally not carried over". |
