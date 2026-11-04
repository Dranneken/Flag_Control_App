# Capability Map: Flag Control Local Admin

| Module ID | Responsibility | Depends on |
|---|---|---|
| `lua-modules` | Split the current app into focused Lua modules without changing existing flag behavior | — |
| `steam-identity` | Load a local allowlist of admin Steam UIDs and read the local UID from Content Manager data | `lua-modules` |
| `local-admin-gate` | Require an allowlisted UID and a local password before enabling flag-control actions | `steam-identity` |

Build order: `lua-modules` → `steam-identity` → `local-admin-gate`.

# Spec: Flag Control Local Admin Gate

## Objective

Add one local Flag Control admin account, usable by one or more manually allowlisted Steam UIDs. On first setup and every later login, the current Windows/Content Manager Steam UID must be allowlisted before a password can be created or accepted. The app must remain locked when identity data is absent, malformed, ambiguous, or not allowlisted.

The local gate replaces the current Assetto Corsa server-admin login as the gate for this app's controls, and applies both online and offline. It is only a local UI/action gate: it does not authenticate remote `OnlineEvent` messages or prevent a modified client from publishing them.

## Technical Context

- Runtime: Assetto Corsa + Custom Shaders Patch Lua app, LuaJIT.
- Existing entry point: `FlagControlApp.lua`; current multiplayer transport remains CSP `ac.OnlineEvent`.
- Content Manager currently stores a Steam profile ID in its local `Values.data` file under `%LOCALAPPDATA%\AcTools Content Manager`.
- Password verifier: salted PBKDF2-HMAC-SHA256; never store the plaintext password.
- Fresh installs accept the shared initial password `adminpass` only after the current Steam UID is allowlisted. The user can change it after login; this shared default must be disclosed as temporary. Do not run password derivation during app initialization.
- Password hashing guidance: OWASP recommends Argon2id by default and PBKDF2-HMAC-SHA256 with 600,000 or more iterations when PBKDF2 is required for FIPS compliance. See [OWASP Password Storage Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html).

## Commands

- Lua tests: `npx --yes --package=fengari-node-cli fengari tests/network_test.lua`, `tests/blue_flags_test.lua`, and `tests/field_flags_test.lua`
- Lua syntax validation: `npx --yes --package=fengari-node-cli fengari -e "assert(loadfile('FlagControlApp.lua')); assert(loadfile('modules/network.lua')); assert(loadfile('modules/blue_flags.lua')); assert(loadfile('modules/field_flags.lua'))"`
- In-game runtime validation: load or reload Flag Control in CSP and inspect the app log.
- PBKDF2 validation: compare module outputs against Python's standard-library `hashlib.pbkdf2_hmac('sha256', ...)` known vectors.
- Configuration validation: exercise missing, malformed, duplicate, and valid UID entries through the app's config parser.

Fengari provides an isolated Lua test/runtime check; acceptance still requires an in-game CSP check because Fengari is not the shipped CSP runtime.

## Project Structure

- `FlagControlApp.lua`: app bootstrap and window registration.
- `modules/network.lua`: CSP `OnlineEvent` declarations, peer presence, and message dispatch.
- `modules/field_flags.lua`: field-flag validation, state, and publish/apply behavior.
- `modules/blue_flags.lua`: blue detection, ignore state, class rules, and manual alerts.
- `modules/admin_config.lua`: parse the local admin UID allowlist.
- `modules/steam_identity.lua`: read and validate the local Steam UID from Content Manager data.
- `modules/password_kdf.lua`: salted PBKDF2-HMAC-SHA256 implementation and verifier helpers.
- `modules/admin_auth.lua`: first-run password setup, login state, and lockout/cooldown behavior.
- `modules/ui.lua`: app tabs and control rendering.
- `admin_steam_ids.example.ini`: tracked example with no personal IDs. If no legacy per-script allowlist exists, the app creates a local `FlagControlApp_admin_steam_ids.ini` in the shared CSP Lua app config folder.

Keep the existing public event keys, payload layouts, and field/blue-flag behavior unchanged.

## Code Style

Follow the existing Lua style: local module state, camelCase functions, early returns for invalid input, and explicit guards before side effects.

```lua
local function isAllowedSteamID(steamID, allowlist)
  if type(steamID) ~= 'string' or steamID == '' then return false end
  return allowlist[steamID] == true
end
```

## Testing Strategy

- Verify PBKDF2 against published/reference vectors and reject wrong passwords.
- Verify the UID parser accepts exactly one SteamID64-shaped value and fails closed on zero or multiple matches.
- Verify allowlist parsing accepts one or more valid IDs and fails closed on malformed or empty configuration.
- In CSP, verify an allowlisted UID can set up and log in; an unlisted UID cannot set up or log in; wrong passwords remain locked; restart requires login again.
- Verify all local flag, ignore, class-rule, and manual-alert actions remain unavailable until the local gate succeeds, online and offline.
- Verify the existing `OnlineEvent` payloads and peer discovery behavior remain unchanged.
- Never print passwords or Steam UIDs in logs or UI errors.

## Boundaries

- Always fail closed if the allowlist or Content Manager identity cannot be read and validated.
- Always keep the local allowlist and password verifier out of Git; do not include personal UIDs in source, examples, logs, or reports.
- Always describe this as a local convenience gate, not server-side or lobby-wide authorization.
- Ask first before adding a host service, Assetto Corsa server plugin, or external dependency.
- Never store the password in plaintext or claim that a Steam UID is a secret.

## Success Criteria

1. A local Steam UID must match an entry in `admin_steam_ids.ini` before default-password provisioning, password login, password reset, or local admin actions are permitted.
2. The password verifier is stored locally as a salted PBKDF2-HMAC-SHA256 verifier; the password itself is never persisted.
3. Missing, unreadable, malformed, ambiguous, or unlisted identity data leaves controls locked with a clear, non-sensitive message.
4. Every local action that changes flags, ignores, class rules, or manual alerts is gated in both online and offline sessions.
5. The app is split into focused Lua modules and preserves existing UI and multiplayer behavior except for the new local gate.
6. No claim is made that the local gate authenticates remote clients or prevents forged lobby messages.

## Open Questions

- The Content Manager `Values.data` format is undocumented. The current file contains one SteamID64-shaped value, but compatibility must be validated and the reader must fail closed if the format changes.
- PBKDF2 work factor and in-game login latency must be measured on the target CSP runtime; if the secure work factor causes an unacceptable UI stall, stop and review the design rather than silently lowering it.
