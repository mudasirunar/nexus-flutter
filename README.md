# NEXUS – Smart Business Management App

Offline-first, multi-branch business management mobile application built with **Flutter**, **Riverpod**, **SQLite (`sqflite`)**, and **Firebase** (Auth, Cloud Firestore, FCM).

## Architecture
- **Feature-First Clean Architecture** under `lib/`:
  - `core/` — Theme (`System`/`Light`/`Dark` persisted locally), connectivity monitor, biometric unlock, local & FCM notification service.
  - `data/` — SQLite schema (`app_database.dart`), DAO (`nexus_dao.dart`), Firestore wrapper (`firestore_service.dart`), and bi-directional `SyncEngine`.
  - `features/` — `auth`, `branches`, `inventory`, `transactions`, `analytics`.
  - `shared/` — Responsive `AppShell` (`NavigationBar` / `NavigationRail`), `OfflineBanner`, `SyncStatusBadge`, and state views.

## Offline-First & Sync Strategy
- **Single Local Source of Truth:** All core screens read and write directly to local SQLite (`nexus.db`) so the app remains fully usable offline.
- **Bi-Directional Sync (`SyncEngine`):**
  - Pulls remote Firestore updates since `last_pull_timestamp`, then pushes local `pending`/`failed` records.
  - **Idempotency:** Every record uses a client-generated UUID as its Firestore document ID, preventing duplicates on retries or interrupted syncs.
  - **Delete Always Wins:** Soft-deletes (`isDeleted = true`) always override concurrent updates regardless of timestamp.
  - **Last-Write-Wins (LWW):** Non-delete concurrent updates resolve by latest `updatedAt` epoch timestamp.

## Security & RBAC
- **Firebase Email/Password Authentication** with cached local session for offline startup, **Mock Forgot Password** flow, **Biometric Unlock** (`local_auth`), and **Inactivity Auto-Logout**.
- **Role-Based Access Control (`Admin`, `Manager`, `Employee`)** enforced in UI/providers and [firestore.rules](firestore.rules).

## Setup & Running
1. Place `google-services.json` in `android/app/` and `GoogleService-Info.plist` in `ios/Runner/` (both gitignored).
2. Publish [firestore.rules](firestore.rules) to Cloud Firestore.
3. Optional one-time Firestore seed:
   ```bash
   npm --prefix scripts install firebase-admin --no-save
   node scripts/seed_firestore.mjs
   ```
4. Run static analysis & tests:
   ```bash
   flutter analyze
   flutter test
   ```
5. Build release APK:
   ```bash
   flutter build apk --release
   ```
