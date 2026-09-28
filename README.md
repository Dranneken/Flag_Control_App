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
  - If the ignored driver is running `FlagControlApp`, their client receives the command over `OnlineEvent` and suppresses native AC flag and CMRT HUD alerts.
  - Ignored drivers can be restored at any time by pressing **RESTORE**.
  - **IGNORE ALL ACTIVE** and **RESTORE ALL** quick action buttons are available at the top.
- **All Session Drivers View**:
  - Expandable section listing all drivers in the session with their position, car, and current blue flag status (`Normal`, `Active Blue`, `Ignored`).
  - Allows Race Control to pre-emptively waive or ignore blue flags for any driver before they even reach lapping traffic.
- **Manual Blue Alert**:
  - Deploy manual blue flag warnings to a specific class group or field-wide.

### 3. CMRT Complete HUD Integration
- Seamlessly communicates with `CMRT-Complete-HUD` via shared memory (`app.FlagControlApp.cmrtOverride.v3`).
- When a driver is ignored by Flag Control, CMRT silences the blue flag visual warning, audio alert, and track map indicator.

## Important Notes
- Admin Mode is currently unauthenticated; any player with the app can view and manage flags in this version.
- Flag commands and ignores are broadcast to other clients running the app via CSP `OnlineEvent`.
