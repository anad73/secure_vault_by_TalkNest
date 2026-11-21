# Safe Vault

An original, offline Flutter app that hides photos, videos and audio in an **encrypted** vault on Android. It has a feature set comparable to *Safe Gallery (Gallery Lock)*, rebuilt from scratch to the standards in `MASTER_DEVELOPMENT.docx`. It contains no ads, no trackers and no network permission.

> **Status:** source-complete, but **not yet compiled**. The workspace this was written in had no Flutter or Android SDK, so `flutter analyze`, `flutter test` and a device build could not be run here. Follow the steps below on your machine. If anything fails, the error output tells you exactly which line to fix.

---

## 1. Build & run

Requirements: Flutter **3.27 or newer** (stable), Android SDK, JDK 17.

```bash
cd safe_vault
flutter pub get
dart format .
flutter analyze
flutter test
flutter run                 # debug on a connected phone
flutter build apk --release # → build/app/outputs/flutter-apk/app-release.apk
flutter build appbundle     # → build/app/outputs/bundle/release/app-release.aab
```

If the Android folder doesn't match your Flutter version (Gradle or AGP errors), you can regenerate the template files. Existing files are never overwritten:

```bash
flutter create --platforms=android --org com.safevault --project-name safe_vault .
```

**Release signing:** copy `android/key.properties.example` to `android/key.properties` and fill it in. Without it, release builds are signed with the debug key so they still install for testing.

**Tests on Linux** need the system SQLite library for `sqflite_common_ffi`:
`sudo apt install libsqlite3-dev`. It's already present on macOS and Windows.

## 2. Features

| Area | What's included |
|---|---|
| Lock | PIN (4–12 digits) or 3×3 pattern. **No default PIN.** Fingerprint unlock (optional). Escalating lockout after 5 failures (30 s → 1 h) that survives restarts. |
| Recovery | Optional security question. The answer re-wraps the same key, so you can reset the PIN **without losing files**. |
| Hiding | Multi-select picker over the device gallery (albums, paging). Files are encrypted, then the originals are removed through Android's own delete dialog. Audio files can be imported through the system file picker. |
| Albums | Create, rename, delete, move items between albums, album covers and counts. |
| Browsing | Paged grid (keyset pagination), sort by added/taken/name, debounced search, multi-select, select all, 2–5 columns, optional hidden thumbnails. |
| Viewer | Swipe, pinch-zoom, non-destructive rotate, favourite, details, slideshow, built-in video/audio player. |
| Unhide | Photos and videos go back to the gallery. Audio is saved via the system "Save as" dialog. Items leave the vault only after the restored copy was saved. |
| Backup | One encrypted `.svbk` file protected by a backup password. Restore works into any Safe Vault, including on a new phone. |
| Self-repair | *Vault integrity* re-registers encrypted files that lost their database row, removes broken rows and cleans half-written files. It also runs silently after each unlock. |
| Privacy | Screenshot and recent-apps blocking (`FLAG_SECURE`), auto-lock (immediately/30 s/1 min/5 min), decrypted temp files wiped on lock, no `INTERNET` permission in release, cloud backup and device transfer excluded. |
| UI | Material 3, light/dark/system themes, brand gradient, selective glass panels, skeleton shimmer, empty/error/retry states, progress dialogs, haptics, reduced-motion support. |
| Languages | English, Dari (`fa`) and Pashto (`ps`) with full RTL. Language can be switched in Settings. |

## 3. Architecture

Feature-first, MVVM with `ChangeNotifier` view-models and `provider` for dependency injection. Business logic lives in services and repositories, never in widgets.

```text
lib/
  main.dart                    bootstrap, global error handlers, splash/retry
  app/                         composition root (dependencies.dart), MaterialApp, lock gate, lifecycle auto-lock
  core/
    design/                    tokens (spacing, radii, motion, sizes), Material 3 theme
    l10n/                      en/fa/ps tables + generated typed AppStrings
    widgets/                   glass panel, skeleton/shimmer, empty/error states, feedback, progress dialog
    errors/ logging/ utils/ platform/
  data/
    crypto/                    VaultCipher (file format), KeyWrapper (PBKDF2 + AES-GCM), isolate workers
    db/                        SQLite schema + versioned migrations
    storage/                   app-private paths, temp wiping
  features/
    auth/                      repository, biometrics, session, lock/setup/recovery screens, PIN & pattern pads
    vault/                     models, repositories, VaultService, home/album screens & view-models
    picker/                    device gallery picker
    viewer/                    image pager, video/audio player
    backup/                    backup format + screen
    settings/                  settings controller + screen
android/                       Gradle (Kotlin DSL), manifest, MainActivity (FLAG_SECURE channel), icons, splash
test/                          crypto, auth, repository, service, backup round-trip, widget, l10n tests
docs/AUDIT.md                  Phase 1 audit of the reference APK
docs/IMPLEMENTATION_REPORT.md  what was done per phase, decisions, verification status
```

## 4. Security model

- **Master key:** a random 256-bit key. It's stored only *wrapped* with AES-256-GCM under a key derived from your PIN/pattern via PBKDF2-HMAC-SHA256 (210,000 iterations, random 128-bit salt). Nothing is stored that could verify a PIN offline: a wrong PIN simply fails the GCM tag check.
- **Files:** each file is split into 1 MiB records. Every record is AES-256-GCM encrypted with its own random nonce. The associated data binds the file's random id, the record index and a final-record flag, so swapping, reordering or truncating records is detected. The first record holds encrypted metadata, which makes database recovery possible.
- **Storage:** encrypted files and the database live in app-private storage. Names are random hex, and the database contains only metadata.
- **Biometrics:** when enabled, a copy of the master key is kept in Android Keystore-backed secure storage and read only after a successful fingerprint prompt.
- **In memory:** the key is copied out to operations and zeroed in the session on lock. Thumbnails are decrypted in memory only and cleared on lock.

**Known limits:**
- Crypto runs in pure Dart on background isolates. Very large videos take longer to hide than with native crypto (the UI stays responsive and shows progress).
- Biometric unlock is as strong as the device's Keystore and lock-screen protection.

## 5. Translations

Dari and Pashto strings are careful translations but **haven't been reviewed by a native speaker**. Please have them proofread before publishing. Edit `lib/core/l10n/strings_fa.dart` and `strings_ps.dart`, and if you add keys to `strings_en.dart`, regenerate the typed accessor:

```bash
python3 tools/gen_strings.py lib/core/l10n/strings_en.dart lib/core/l10n/app_strings.dart
```

`test/l10n/strings_test.dart` fails if a language is missing a key or a placeholder.

## 6. Icons & splash

The launcher icon (adaptive, round, legacy and Android 13 monochrome), the Android 12+ splash icon and the pre-12 splash logo are generated by `tools/gen_icons.py` into `android/app/src/main/res`. `docs/store_icon_512.png` is the Play Store icon.
