# Tasks: Flag Control Local Admin

## Phase 1: Lua Module Foundation

- [x] Task 1: Extract app bootstrap and network transport
  - Acceptance: Keep `FlagControlApp.lua` as entry point; preserve event keys, layouts, protocol values, send semantics, and peer discovery.
  - Verify: Reload in CSP and confirm another app client appears in the peer list.
  - Files: `FlagControlApp.lua`, `modules/network.lua`, `tests/network_test.lua`
  - Dependencies: None
- [x] Task 2: Extract field and blue-flag behavior
  - Acceptance: Preserve field flags, blue detection, ignore/restore, class rules, and manual alerts.
  - Verify: Fengari field/blue module tests passed; CSP two-client smoke test remains pending.
  - Files: `FlagControlApp.lua`, `modules/field_flags.lua`, `modules/blue_flags.lua`, focused tests
  - Dependencies: Task 1
- [x] Task 3: Extract the app UI into focused modules
  - Acceptance: Preserve all tabs, controls, status text, and callbacks.
  - Verify: Fengari UI module tests and Lua syntax checks passed; CSP tab interaction remains pending.
  - Files: `FlagControlApp.lua`, `modules/ui.lua`, `modules/race_control_ui.lua`, focused tests
  - Dependencies: Task 2

## Checkpoint: Existing Behavior

- [ ] CSP reload has no Lua errors.
- [ ] Existing flag and peer behavior works with two clients.

## Phase 2: Identity and Credentials

- [x] Task 4: Add the local Steam UID allowlist and CM identity reader
  - Acceptance: Parse one or more valid configured IDs; require exactly one local ID; fail closed on all missing/invalid/ambiguous inputs.
  - Verify: Fengari fixture tests pass; in-game CSP validation remains pending; never print UID values.
  - Files: `modules/admin_config.lua`, `modules/steam_identity.lua`, `admin_steam_ids.example.ini`, focused tests
  - Dependencies: Task 3
- [ ] Task 5: Add and verify PBKDF2-HMAC-SHA256 password storage
  - Acceptance: Store only salt and verifier locally; correct password passes, incorrect password fails.
  - Verify: SHA-256/HMAC/PBKDF2 tests pass against Python reference vectors; measure time-budgeted work in target CSP.
  - Files: `modules/sha256.lua`, `modules/pbkdf2.lua`, `modules/password_kdf.lua`, `modules/windows_crypto.lua`, focused tests
  - Dependencies: Task 3
- [ ] Task 6: Add first-run setup, login, and action gating
  - Acceptance: Require allowlisted UID before setup/login and gate all local flag actions online and offline.
  - Verify: First-run, login, bad password, unlisted UID, restart, online, and offline CSP tests.
  - Files: `modules/admin_auth.lua`, `modules/ui.lua`, `modules/flags.lua`, `FlagControlApp.lua`
  - Dependencies: Tasks 4 and 5

## Checkpoint: Local Admin Gate

- [ ] Allowed UID and correct password unlock local actions.
- [ ] Invalid identity/config/password remains locked.
- [ ] Existing remote event receive behavior is unchanged.

## Phase 3: Documentation and Final Verification

- [ ] Task 7: Document local setup, limitations, and recovery
  - Acceptance: Explain UID allowlist setup, local password flow, recovery, and client-side authorization limitation without exposing credentials.
  - Verify: Check documentation against actual implementation.
  - Files: `README.md`, `admin_steam_ids.example.ini`
  - Dependencies: Task 6

## Checkpoint: Complete

- [ ] All spec success criteria pass.
- [ ] No user UID or password verifier is staged.
- [ ] Existing multiplayer behavior is preserved.
