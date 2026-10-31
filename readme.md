# light

A small macOS menu bar light for your VPN. Requires macOS 13 or later, on Apple silicon or Intel.

[Download and setup](https://metalnakls.github.io/light/) · [Privacy](https://metalnakls.github.io/light/privacy.html)

- **⌃⌥⌘V** toggles the selected VPN profile.
- **⌃⌥⇧⌘V** opens Shadowrocket.
- Click the dot to disconnect; right-click or reopen Light for settings.
- Yellow means connected; a hollow dot means transitioning. Red warns of unavailable VPN status or three consecutive failed tunnel-check rounds.
- White is available manually. Optional adaptive white-on-yellow coloring needs Screen Recording permission and macOS 14 or later.
- Signed automatic updates are enabled by default, with controls in Settings → About.

Install and configure Shadowrocket before choosing its profile in Light. No Raycast or Shortcut is required. Health checks are not a privacy guarantee; if macOS does not expose the selected tunnel interface, health remains inconclusive.

## Install

Unzip the release into **/Applications/Utilities/Light.app**, or use the [installer](https://metalnakls.github.io/light/install.sh). The installer retains no backups. Releases follow Glass and Yina’s non-notarized distribution; see the setup guide for Gatekeeper instructions.

The bundled helper works from that location:

```sh
/Applications/Utilities/Light.app/Contents/MacOS/lightctl toggle
```

It also supports `on`, `off`, `settings`, and `shadowrocket`. Portable URL equivalents include `open 'light://toggle'`. Version 1 automation must remove its separate VPN action, because Light 2 controls the VPN itself.

## Develop

```sh
./scripts/check.sh
LIGHT_CODESIGN_IDENTITY='<your Apple Development identity>' ./scripts/install.sh
```

The install command builds a universal app, verifies it, and installs into Utilities. Stop an existing Light process before replacement. This does not disconnect the VPN.

See [release workflow](docs/releases.md) for versioning and publication.
