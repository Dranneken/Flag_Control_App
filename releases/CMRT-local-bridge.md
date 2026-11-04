# Temporary CMRT bridge

This documents the local CMRT adapter used while FlagControlApp is tested with
other players. It is not a CMRT release or a distributable CMRT patch. Once
multiplayer behavior is proven, the intended integration target is RaceCore,
so this adapter can be retired.

## Compatibility

- FlagControlApp: 0.3
- Local CMRT installation inspected for this prototype: 2.1.3, extension marker
  `2.1.3-ext-190`

The CMRT adapter reads the CSP shared state
`app.FlagControlApp.cmrtOverride.v3`, including the active field flag, class,
blue-flag filtering, ignored-driver, and manual-blue state. The CMRT integration
points in the inspected installation are:

- `CMRT-Complete-HUD.lua`
- `common/flag_control.lua`
- `flags/first.lua`
- `leaderboard/first.lua`
- `map/first.lua`
- `progress/first.lua`

These are references to the local CMRT installation only. Do not copy CMRT-owned
source files into FlagControlApp releases.

## Multiplayer test setup

1. Install FlagControlApp on each participant's Assetto Corsa installation.
   The CMRT bridge is only needed on a participant's own machine to show the
   integration in that local CMRT HUD.
2. The local race-control operator must configure their own allowlisted Steam
   profile and password. Other participants do not need admin access just to
   receive FlagControlApp updates.
3. Test peer discovery and field/blue-flag updates with at least two clients.
4. Treat the current online messages as unauthenticated; use trusted testers.

The bridge is a temporary presentation adapter. Multiplayer transport and
RaceCore integration are separate concerns.
