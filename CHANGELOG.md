# Changelog

## 0.5.0 - 2026-11-05

### Added
- Add a client-side penalty feed with manual issuance, policy configuration, and multiplayer synchronization.
- Add separate Flag Notice and Penalty Notice companion windows; flag changes stay visible until the next update, while penalty notices use independent 15-second queues for you and other players.
- Add right-click pinning for companion windows, with each window's lock state saved locally.

### Changed
- Allow deploying a different field flag directly with **REDEPLOY FLAG**, without an intermediate undeploy.
- Refresh the app icon using the existing tower-and-flag silhouette in a three-color palette.

## 0.4.3 - 2026-11-03

### Fixed
- Send the current field-flag snapshot when a new peer appears or a peer's presence heartbeat resumes after a disconnect, even if the local online-race state never transitioned.

## 0.4.2 - 2026-11-03

### Fixed
- Request the current field-flag state when entering or rejoining an online race, so active flags are restored and cleared flags do not leave stale state.
- Rate-limit each client's field-flag sync requests.

## 0.4.1 - 2026-11-03

### Fixed
- Avoid password-derivation work during app initialization so the login UI can render before cryptographic setup.
- Report unavailable Windows crypto support cleanly when creating a changed-password verifier.

## 0.4.0 - 2026-11-03

### Added
- Provision the shared initial password `adminpass` for allowlisted fresh installs.
- Add an in-app password-change flow.

### Changed
- Resetting a forgotten password restores `adminpass`.
- Passwords may be 9–128 bytes to support the initial password.

## 0.3.1 - 2026-11-03

### Fixed
- Read the Content Manager Steam profile ID when `Values.data` also contains unrelated long numeric values.

## 0.3 - 2026-11-02

### Added
- Automatically create the local admin allowlist on first launch when no existing per-script allowlist is present.
- Continue to support existing per-script allowlist files.
