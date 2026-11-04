# Content Manager release packages

Ready-to-install archives belong here, named `FlagControlApp-v<version>.zip`.
The current package is `FlagControlApp-v0.5.0.zip`.

The archive should have this layout at its root:

```text
apps/
  lua/
    FlagControlApp/
      manifest.ini
      FlagControlApp.lua
      modules/
      icon.png
```

Include the runtime files and the example allowlist only. Never include a populated local allowlist, CSP storage, `.git`, tests, or development files.

The temporary CMRT integration is local-only and is not included in release
archives. See [CMRT-local-bridge.md](./CMRT-local-bridge.md) for its scope and
multiplayer test setup.
