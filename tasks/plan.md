# Implementation Plan: Flag Control Local Admin

## Overview

Refactor Flag Control into focused Lua modules, add a per-install Steam UID allowlist sourced from Content Manager's local data, and gate all local flag-control actions behind an allowlisted UID plus a locally configured password. Existing `OnlineEvent` payloads and peer behavior remain unchanged; this feature is not remote-client authorization.

## Architecture Decisions

- Keep the feature standalone in FlagControlApp; do not connect it to RaceCore or add a server process.
- Store the manually maintained allowlist under CSP's per-script configuration directory, with a tracked example file and no personal IDs in Git.
- Read the current UID from Content Manager's local `Values.data`; accept exactly one SteamID64-shaped value and fail closed otherwise. This file format is undocumented, so compatibility must be checked in-game.
- Store only a salted PBKDF2-HMAC-SHA256 verifier in local CSP storage. Measure verification time in CSP; do not silently reduce the work factor if it causes a stall.
- Preserve existing network event keys, payload layouts, and message handling. The local gate does not stop remote clients from forging events.

## Task List

### Phase 1: Lua Module Foundation
- [x] Task 1: Extract app bootstrap and network transport
- [x] Task 2: Extract field and blue-flag behavior
- [x] Task 3: Extract the app UI into focused modules

### Checkpoint: Existing Behavior
- [ ] App loads in CSP without Lua errors
- [ ] Field flags, blue flags, peer presence, and existing `OnlineEvent` messages behave as before

### Phase 2: Identity and Credentials
- [ ] Task 4: Add the local Steam UID allowlist and CM identity reader
- [ ] Task 5: Add and verify PBKDF2-HMAC-SHA256 password storage
- [ ] Task 6: Add first-run setup, login, and action gating

### Checkpoint: Local Admin Gate
- [ ] Allowlisted UID plus correct password unlocks controls
- [ ] Unlisted UID and invalid identity/configuration fail closed
- [ ] App remains responsive during password verification
- [ ] Online and offline flows are verified in CSP

### Phase 3: Documentation and Final Verification
- [ ] Task 7: Document local setup, limitations, and recovery

### Checkpoint: Complete
- [ ] All spec success criteria pass
- [ ] No UID or password verifier is included in source or staged files
- [ ] Existing multiplayer event behavior is unchanged

## Task Details

### Task 1: Extract app bootstrap and network transport

**Description:** Establish module boundaries and move online peer state and `OnlineEvent` declarations/handlers out of the main file, keeping event layouts unchanged.

**Acceptance criteria:**
- [ ] `FlagControlApp.lua` remains the CSP entry point and loads the extracted modules.
- [ ] Event keys, field types, protocol values, and send semantics are byte-for-byte compatible.
- [ ] Peer discovery remains functional.

**Verification:** `npx --yes --package=fengari-node-cli fengari tests/network_test.lua`; syntax-check the entry point and module; CSP reload and verify peer discovery with a second app client.

**Dependencies:** None.

**Files likely touched:** `FlagControlApp.lua`, `modules/network.lua`, `tests/network_test.lua`.

**Estimated scope:** Medium.

### Task 2: Extract field and blue-flag behavior

**Description:** Move field flag state/actions and blue-flag detection/ignore/class-rule behavior into focused modules without changing their public behavior.

**Acceptance criteria:**
- [ ] All existing field-flag and blue-flag actions continue to use the same event payloads.
- [ ] Ignore, restore, class-rule, and manual-alert behavior remains unchanged.
- [ ] No mutating path is lost during extraction.

**Verification:** `npx --yes --package=fengari-node-cli fengari tests/field_flags_test.lua` and `tests/blue_flags_test.lua`; CSP two-client smoke test remains part of the existing-behavior checkpoint.

**Dependencies:** Task 1.

**Files likely touched:** `FlagControlApp.lua`, `modules/field_flags.lua`, `modules/blue_flags.lua`, and focused tests.

**Estimated scope:** Medium.

### Task 3: Extract the app UI into focused modules

**Description:** Move the current window and tab rendering into UI modules while keeping the main file as a small bootstrap.

**Acceptance criteria:**
- [ ] Existing tabs, controls, status text, and layout remain available.
- [ ] UI callbacks call the same behavior functions as before.
- [ ] CSP reload reports no missing-module or Lua errors.

**Verification:** Fengari UI tests and Lua syntax checks pass; open each app tab in CSP and exercise representative controls (pending).

**Dependencies:** Task 2.

**Files likely touched:** `FlagControlApp.lua`, `modules/ui.lua`, `modules/race_control_ui.lua`, and focused tests.

**Estimated scope:** Medium.

### Task 4: Add the local Steam UID allowlist and CM identity reader

**Description:** Add a sample allowlist config and a reader for the local Content Manager data file. Resolve local app-data paths through CSP APIs; do not hardcode a user profile path.

**Acceptance criteria:**
- [ ] The user config accepts one or more strictly validated SteamID64 values.
- [ ] The reader accepts exactly one SteamID64-shaped value from `Values.data`.
- [ ] Missing, unreadable, malformed, or ambiguous identity/config data denies setup and login without printing IDs.

**Verification:** Test valid, empty, malformed, duplicate, missing-file, and unreadable-file cases with fixtures and CSP.

**Dependencies:** Task 3.

**Files likely touched:** `modules/admin_config.lua`, `modules/steam_identity.lua`, `admin_steam_ids.example.ini`, `README.md`.

**Estimated scope:** Medium.

### Task 5: Add and verify PBKDF2-HMAC-SHA256 password storage

**Description:** Implement password derivation in a separate module, store only salt and verifier in local CSP storage, and verify against independent reference vectors.

**Acceptance criteria:**
- [ ] No plaintext password is persisted or logged.
- [ ] Correct passwords verify and incorrect passwords do not.
- [ ] Work factor and latency are measured in the target CSP runtime; no silent reduction of the work factor.

**Verification:** Compare known test vectors with Python's standard-library PBKDF2-HMAC-SHA256 and measure the in-game verification flow.

**Dependencies:** Task 3.

**Files likely touched:** `modules/password_kdf.lua`, `tests/password_kdf.lua`.

**Estimated scope:** Medium.

### Task 6: Add first-run setup, login, and action gating

**Description:** Require an allowlisted local UID before password setup or login, then gate all local flag-control actions behind the password check for online and offline sessions.

**Acceptance criteria:**
- [ ] An allowlisted UID can create the local password once and log in on later runs.
- [ ] An unlisted UID cannot create or use the credential; a UID/config read failure remains locked.
- [ ] All local field-flag, ignore, class-rule, and manual-alert actions are gated; remote event receive behavior is unchanged.

**Verification:** Run first-use, valid login, wrong password, unlisted UID, restart, offline, and online cases in CSP.

**Dependencies:** Tasks 4 and 5.

**Files likely touched:** `modules/admin_auth.lua`, `modules/ui.lua`, `modules/flags.lua`, `FlagControlApp.lua`.

**Estimated scope:** Medium.

### Task 7: Document local setup, limitations, and recovery

**Description:** Document how to copy/edit the local UID allowlist, set and use the password, and recover if the local credential is lost.

**Acceptance criteria:**
- [ ] Documentation does not include real UIDs, passwords, or password verifiers.
- [ ] It clearly states that the local gate does not authenticate remote messages.
- [ ] Recovery steps do not silently bypass the UID allowlist.

**Verification:** Review documentation against the implemented setup and recovery flows.

**Dependencies:** Task 6.

**Files likely touched:** `README.md`, `admin_steam_ids.example.ini`.

**Estimated scope:** Small.

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Content Manager changes the undocumented `Values.data` format | High: legitimate admin is locked out | Strict parsing, fail closed, clear non-sensitive error, validate against the installed version |
| Pure Lua PBKDF2 causes an in-game stall | Medium | Measure in CSP and keep UI responsive; stop and ask before changing the work factor |
| A local client-side gate is mistaken for lobby-wide authorization | High | Keep the limitation explicit in UI/docs; do not change event receiver trust |
| Module extraction changes event behavior | High | Extract in small steps and verify event layouts and two-client behavior after each step |

## Open Questions

- The exact Content Manager data serialization is undocumented; implementation must confirm the currently observed value can be read consistently and must fail closed on format changes.
- PBKDF2 performance has not yet been measured in the target CSP runtime.
