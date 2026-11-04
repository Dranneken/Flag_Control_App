# Flag Control

A CSP Lua app for Assetto Corsa that provides field-flag broadcasting (Green, Yellow, Red) and real-time **Blue Flag Control** with per-driver ignore management and multiplayer synchronization.

See the [FlagControlApp knowledge graph](./KNOWLEDGE_GRAPH.md) for module relationships, runtime flows, network events, state ownership, and test coverage.

## Install

Copy the `FlagControlApp` folder into:

```text
assettocorsa/apps/lua/FlagControlApp
```

Enable Flag Control in Content Manager / CSP's Lua app settings, then open **Flag Control** from the in-game app list.
The **Flag Notice** companion window keeps the current field-flag state visible until the next flag update, including a persistent clearing notice after undeploying. Active flags are shown with a small animated waving flag. The **Penalty Notice** companion window displays each newly issued penalty for 15 seconds.
Both companion windows have no native title bar; right-click anywhere inside either window to pin or unpin it. The lock state is saved locally.

Every player who should receive synced flags and ignore commands needs a compatible CSP installation and this app enabled. The app uses CSP `OnlineEvent` messages for zero-configuration multiplayer networking.

## Features

### 1. Field Flags
- Controls session-wide flags: **Green**, **Yellow**, **Red**.
- **DEPLOY FLAG**, **REDEPLOY FLAG**, and **UNDEPLOY FLAG** actions with live status and last-sender tracking. Selecting a different flag while one is active redeploys it directly without an intermediate undeploy.
- The **Flag Notice** companion window keeps a deployment visible until the next flag update; undeploying replaces it with a persistent clearing notice.
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
  - Always-visible section listing all drivers in the session with their position, car, and current blue flag status (`Normal`, `Active Blue`, `Ignored`).
  - Allows Race Control to pre-emptively waive or ignore blue flags for any driver before they even reach lapping traffic.
- **Manual Blue Alert**:
  - Deploy manual blue flag warnings to a specific class group or field-wide.

### 3. HUD Integrations
- Preserves the CMRT Complete HUD shared-memory interface (`app.FlagControlApp.cmrtOverride.v3`).
- Also mirrors app-controlled flag, ignore, and manual-alert state to the FCA-owned key (`app.FlagControlApp.fcaOverride.v3`) for the planned custom HUD. It reads the local class from FCA first, then falls back to CMRT.
- When a driver is ignored, CMRT continues to silence blue-flag visual, audio, and track-map alerts. The FCA key is ready for the custom HUD to implement its own alerts.

### 4. Penalty Feed
- The **Flag Control** window has two side-by-side columns with independent tab groups: field/blue-flag controls on the left and the penalty feed on the right.
- The penalty column contains **Feed**, **Issue Penalty**, and **Policies** tabs. Drivers can read the feed without unlocking Admin Mode; issuing penalties and changing policies require local admin access.
- The **Penalty Notice** companion window splits into **You** and **Other Players** columns. Each column has its own queue and displays newly issued penalties for 15 seconds; old records loaded at startup do not generate notices.
- Drivers see the cause, requirement, issuer, and status. Stewards can approve recommendations, cancel penalties, and mark serviceable penalties as served.
- Per-source policy settings support off, manual, recommendation/approval, recommendation/delay, and immediate or delayed automatic issue. Delays can use seconds or the driver's lap count.
- This first client-only version does not yet connect automatic incident detectors or enforce pit service / server removal. DQ kick support requires a trusted server-side integration; server credentials must never be stored in this Lua client.

## Important Notes
- Local race-control access requires both an allowlisted Content Manager Steam profile and a Flag Control password. The same gate applies online and offline.
- The app reads the local Steam profile ID from Content Manager's `Values.data`. It does not display or log that ID.
- When a client joins or its presence heartbeat resumes after a disconnect, an unlocked admin client sends its current field-flag state, including an explicit no-flag state, so reconnecting players do not retain stale state even if the online-race indicator never changed. At least one admin app instance must be online and unlocked for this snapshot to be available.
- On first run, Flag Control creates `FlagControlApp_admin_steam_ids.ini` in the CSP Lua app config folder. The full path is shown on the blocked-access screen. Add your 17-digit Steam profile ID on its own line, then reload the app. Existing `admin_steam_ids.ini` files in the per-script config folder continue to work. Blank lines and lines beginning with `#` are allowed; duplicate IDs and inline comments are rejected. Keep the populated file local and do not commit it.
- On the first run with an allowlisted profile, log in with the initial password `adminpass`. Use **CHANGE PASSWORD** in the app header to choose your own password. Passwords must be 9–128 bytes. A changed password is stored only as a salted PBKDF2-HMAC-SHA256 verifier in local CSP storage; later sessions require logging in again.
- `adminpass` is a shared default and is not suitable as a lasting password. Change it after first login. The local Steam profile allowlist remains required for setup, login, reset, and local race-control access.
- To recover a forgotten password, use **RESET LOCAL PASSWORD** on the login screen and press the confirmation button again within five seconds. Reset restores `adminpass`; the current profile must still be allowlisted. If the identity or allowlist is unavailable, fix that configuration first; there is no bypass.
- This is a local UI gate, not multiplayer authentication. CSP `OnlineEvent` messages are exchanged between clients, and receivers currently accept messages from any app client, so this client-side check cannot prevent another client from publishing forged changes.
- Flag commands and ignores are broadcast to other clients running the app via CSP `OnlineEvent`.
- Penalty feed records are synchronized through CSP `OnlineEvent`; policy settings remain local to each steward. As with other client messages, the feed is not server-authoritative and can be spoofed by another client.
