# Phase 1 — Technical Audit of the Reference App

**Subject:** `Safe_Gallery.apk` (package `ukzzang.android.gallerylocklite`, "Safe Gallery / Gallery Lock").
**Method:** static inspection of the APK (manifest, resources, DEX string tables, native libraries). No source code was available, and the app is not a Flutter project.

> Your MASTER_DEVELOPMENT brief is written for improving an *existing Flutter project*. The APK is a third-party native Android (Java/Kotlin) app whose source isn't included in the APK. So the work is a **clean-room, original Flutter app** with comparable features, built to the brief's standards. No code, assets, or branding from the reference app were reused.

---

## 1. Existing architecture

| Area | Finding |
|---|---|
| Stack | Native Android (Java/Kotlin, AndroidX), 3 DEX files, Room database, WorkManager, Picasso image loader, `pl.droidsonroids.gif`. |
| Screens | `AuthAct`, `AuthMainAct`, `MainAct`, `SettingsAct`, `LockImageViewerAct`, `CameraImageViewerAct`, `WebImageLockActivity`, `LockShareMediaAct`, `LockShareAudioAct`, `WidgetQuickRunAct`. Activity-per-screen architecture. |
| Background | `LockMediaImportService`, `LockMediaRecoveryService`, `LockMediaExpertService`, `LockMediaMigrationService`, plus boot, locale, dialer and promotion broadcast receivers. |
| Features (from release notes in the resources) | PIN / pattern / fingerprint lock; lock photos, videos and audio; lock web images; slideshow; rotate; mini-gallery in viewer; export/import of locked media; "recovery of unregistered locked media"; hide thumbnails; select internal/external video player; launch from the phone dialer; 1×1 home-screen widget; share-to-lock. |

## 2. Performance problems

- **About 10 ad and analytics SDKs** run in the same process: AppLovin MAX, Google Mobile Ads, Meta Audience Network, Pangle/ByteDance (`openadsdk`, `apminsight`, `Pglmetasec`), Mintegral, Unity Ads, InMobi, AdColony, Verve/PubNative, Firebase Analytics, Crashlytics and Remote Config. Each adds startup initialisers (content providers in the manifest), memory use, background network traffic and battery drain.
- The APK is **~19 MB**, and most of that is ad-SDK code and native libraries for 5 ABIs. Media-vault logic is a small fraction.
- Receivers for `CONNECTIVITY_CHANGE`, power, battery and storage events wake the process often (mostly from the ad SDKs).

## 3. Database problems

- Room is used, but "recovery of unregistered locked media" exists as a separate feature and service. That suggests the database and the files on disk can fall out of sync, so users need a manual rescan to get their media back.
- No evidence of an integrity check at startup.

## 4. UI/UX problems

- Help texts are built from HTML strings with hard-coded `<font color=#ffffff>` tags, so they don't adapt to light or dark themes.
- The default PIN is **`0000`**, and the reset flow says "Questions and Answers to initialize PINs 0000". New users start with a guessable credential.
- There's no Material 3 design system, no Dari or Pashto localisation, and no RTL-aware layouts (the locales present are mainly en/ko/ja/id/ms/pt/es/hu).
- Full-screen ads and promotion notifications (`ShowPromotionReceiver`) interrupt the private-media flow.

## 5. Security weaknesses

| # | Weakness | Evidence |
|---|---|---|
| S1 | **Default credential `0000`**, with reset to `0000` via a security question. | Resource strings. |
| S2 | **Legacy crypto primitives.** `AES/CBC/PKCS5Padding` (no authentication) and `MD5`/`MessageDigest` usage appear in the DEX. CBC without a MAC lets ciphertext be tampered with undetected. | DEX string table. |
| S3 | **Broad storage access.** `MANAGE_EXTERNAL_STORAGE` plus legacy `READ`/`WRITE_EXTERNAL_STORAGE`. "Recover unregistered media" and "media in external SD card might not be locked" suggest locked files stay on shared storage. | Manifest, strings. |
| S4 | **Large third-party attack surface.** Ad SDKs with WebView/MRAID renderers (`mraid3.js`, `android_bridge.js`, `ad.html`) run inside a privacy app with access to its process. `com.google.android.gms.permission.AD_ID` is requested. | Assets, manifest. |
| S5 | `android.permission.DUMP` and `NEW_OUTGOING_CALL` are requested. The latter is deprecated and highly sensitive. | Manifest. |
| S6 | Only 5 failed attempts, then a message. No escalating lockout was observed. | Strings. |

Static inspection can't prove whether media bytes are encrypted at rest. The release notes and recovery flow are consistent with files being *moved/hidden* rather than strongly encrypted.

## 6. Code duplication

Not measurable without source. The four overlapping "LockMedia*Service" classes and two viewer activities (`LockImageViewerAct`, `CameraImageViewerAct`) suggest duplicated pipelines.

## 7. Outdated or unnecessary dependencies

- Every ad and analytics SDK listed above is unnecessary for an offline vault.
- `android.support` (`com.android.support_exifinterface`) alongside AndroidX.
- The GIF library and Picasso can be replaced by the platform image pipeline.

## 8. Recommended improvements (implemented in Safe Vault)

| Problem | Safe Vault approach |
|---|---|
| S1 default PIN | Mandatory setup on first launch. No default credential. PIN (4–12 digits) or pattern (≥4 dots). |
| S2 weak crypto | **AES-256-GCM** authenticated encryption, chunked in 1 MiB records. Per-file random IDs are bound into AAD, and an explicit final-record flag detects truncation. A random 256-bit master key is wrapped by a **PBKDF2-HMAC-SHA256** key derived from the PIN/pattern. Nothing that could verify the PIN offline (like a hash) is stored. |
| S3 shared storage | Encrypted files live in **app-private storage**. Originals are removed from the gallery through the system delete dialog (MediaStore), so no all-files access is needed. |
| S4 ads / trackers | **No ads, analytics or network calls.** The release manifest declares no `INTERNET` permission. |
| S6 brute force | 5 failures trigger an escalating lockout (30 s, doubling, max 1 h) that survives restarts. |
| DB/file drift | Every encrypted file embeds its own encrypted metadata record. *Settings → Vault integrity* re-registers orphaned files and removes rows whose files are missing. |
| Startup bloat | One process, no SDK initialisers. Heavy crypto runs in background isolates. |
| UI | Material 3 design tokens, light/dark/system themes, glass panels, skeleton loading, empty/error states, English/Dari/Pashto with RTL. |
| Privacy | Optional screenshot and recent-apps blocking (`FLAG_SECURE`) and auto-lock when the app goes to the background. |

### Features intentionally not carried over

| Feature | Reason |
|---|---|
| Ads, promotions, analytics | Contrary to the privacy goal and the brief's "no unnecessary network communication". |
| Launch from phone dialer | Relies on the deprecated `NEW_OUTGOING_CALL` broadcast. Google Play restricts it. |
| Lock web images | Needs `INTERNET`. You can lock images saved to the gallery instead. |
| 1×1 home-screen widget | Low value for a vault (the launcher icon does the same). It can be added later with `home_widget`. |
| External video player | Handing decrypted video to another app leaks it outside the vault. A built-in player is used instead. |
