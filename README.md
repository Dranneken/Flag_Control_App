# Flag Control

A CSP Lua app for selecting and broadcasting a field-flag state to other Flag Control clients in the same Assetto Corsa multiplayer session.

## Install

Copy the `FlagControlApp` folder into:

```text
assettocorsa/apps/lua/FlagControlApp
```

Enable Flag Control in Content Manager/CSP's Lua app settings, then open **Flag Control Admin Mode** from the in-game app list.

Every player who should receive the app flag needs a compatible CSP installation and this app enabled. The app uses CSP `OnlineEvent` messages. Availability and delivery depend on the multiplayer server's messaging support; standard AC compatibility messaging may be rate-limited.

## Use

The window shows the current app flag, the last sender, lobby messaging status, and discovered Flag Control clients.

Select one of these flags, then press **DEPLOY FLAG**:

- Green
- Yellow
- Blue
- Black
- Penalty
- Red
- White
- Checkered
- Pit lane
- Pit box

While a flag is deployed, the action button changes to **UNDEPLOY FLAG**. Press it to clear the app flag.

## Important Limits

- Admin Mode is not authenticated. Any player with the app can currently deploy or clear flags. Do not treat this prototype as admin-only race control.
- Flags are app-level state sent to Flag Control clients. They do not change Assetto Corsa's native server or simulator flag.
- CMRT integration is not included in this repository. It requires a separate local CMRT patch that reads Flag Control's shared state; that patch is currently for testing only.
- Message delivery should be tested in the target lobby. A server may not support or may restrict CSP client messaging.
