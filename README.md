# Flag Control

A CSP Lua app for Assetto Corsa that provides field-flag broadcasting (Green, Yellow, Red) and real-time **Blue Flag Control** with per-driver ignore management and multiplayer synchronization.

## Install

Copy the `FlagControlApp` folder into:

```text
assettocorsa/apps/lua/FlagControlApp
```

Enable Flag Control in Content Manager / CSP's Lua app settings, then open **Flag Control Admin Mode** from the in-game app list.

Every player who should receive synced flags and ignore commands needs a compatible CSP installation and this app enabled. The app uses CSP `OnlineEvent` messages for zero-configuration multiplayer networking.

## Features

### 1. Field Flags
- Controls session-wide flags: **Green**, **Yellow**, **Red**.
- **DEPLOY FLAG** / **UNDEPLOY FLAG** toggling with live status and last-sender tracking.
- Automatic peer discovery displaying all connected lobby members running the app.

### 2. Blue Flags Tab (Reworked)
- **Live Detection**: Shows a real-time list of all drivers currently under blue flag.
  - Automatically identifies cars being lapped on track using live position and spline distance.
  - Receives direct blue flag states from other `FlagControlApp` clients in multiplayer.
  - Identifies the approaching faster car, position, and time gap (e.g. `Lapped by M. Verstappen (P1) [0.8s]`).
- **Ignore Button**:
  - Each driver under blue flag has an **IGNORE** action button.
  - When ignored, the driver's status changes to `[IGNORED]` and the blue flag is suppressed.
  - If the ignored driver is running `FlagControlApp`, their client receives the command over `OnlineEvent` and suppresses the native AC blue flag locally; CMRT HUD alerts continue to work through the existing shared-memory integration.
  - Ignored drivers can be restored at any time by pressing **RESTORE**.
  - **IGNORE ALL ACTIVE** and **RESTORE ALL** quick action buttons are available at the top.
- **All Session Drivers View**:
  - Expandable section listing all drivers in the session with their position, car, and current blue flag status (`Normal`, `Active Blue`, `Ignored`).
  - Allows Race Control to pre-emptively waive or ignore blue flags for any driver before they even reach lapping traffic.
- **Manual Blue Alert**:
  - Deploy manual blue flag warnings to a specific class group or field-wide.

### 3. HUD Integrations
- Preserves the CMRT Complete HUD shared-memory interface (`app.FlagControlApp.cmrtOverride.v3`).
- Also mirrors app-controlled flag, ignore, and manual-alert state to the FCA-owned key (`app.FlagControlApp.fcaOverride.v3`) for the planned custom HUD. It reads the local class from FCA first, then falls back to CMRT.
- When a driver is ignored, CMRT continues to silence blue-flag visual, audio, and track-map alerts. The FCA key is ready for the custom HUD to implement its own alerts.

## Important Notes
- Local race-control access requires both an allowlisted Content Manager Steam profile and a Flag Control password. The same gate applies online and offline.
- The app reads the local Steam profile ID from Content Manager's `Values.data`. It does not display or log that ID.
- The CSP Script Config folder path is shown on Flag Control's blocked-access screen. Copy `admin_steam_ids.example.ini` there as `admin_steam_ids.ini`, then add your 17-digit Steam profile ID on its own line. Blank lines and lines beginning with `#` are allowed; duplicate IDs and inline comments are rejected. Keep the populated file local and do not commit it.
- On the first run with an allowlisted profile, set a 12–128-byte password in the app. The password itself is not saved; only a salted PBKDF2-HMAC-SHA256 verifier is stored in local CSP storage. Later sessions require logging in again.
- To recover a forgotten password, use **RESET LOCAL PASSWORD** on the login screen and press the confirmation button again within five seconds. The current profile must still be allowlisted. If the identity or allowlist is unavailable, fix that configuration first; there is no bypass.
- This is a local UI gate, not multiplayer authentication. CSP `OnlineEvent` messages are exchanged between clients, and receivers currently accept messages from any app client, so this client-side check cannot prevent another client from publishing forged changes.
- Flag commands and ignores are broadcast to other clients running the app via CSP `OnlineEvent`.
