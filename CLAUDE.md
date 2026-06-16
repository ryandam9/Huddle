# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Always do this first

This environment does **not** come with the Flutter SDK preinstalled. At the
start of **every** session, before making or verifying changes:

1. **Install Flutter** (if `flutter` is not already on `PATH`):
   ```bash
   git clone --depth 1 -b stable https://github.com/flutter/flutter.git "$HOME/flutter"
   export PATH="$HOME/flutter/bin:$PATH"
   flutter --version
   ```
2. **Fetch dependencies:**
   ```bash
   flutter pub get
   ```
3. **Run the tests:**
   ```bash
   flutter test
   ```

Do this every time, even for small changes, so work is validated against a
real toolchain. Also run `flutter analyze` before committing.

> Note: network access is governed by the environment's policy. If the clone
> or `pub get` fails because the network is restricted, say so explicitly
> rather than skipping validation silently.

## What this project is

**Huddle** is a cross-platform Flutter app for sharing messages and photos
directly between devices on the same local network — no server, no internet.
It has three pillars: a **dashboard** of devices on the network, an explicit
**pairing agreement** (handshake) between two devices, and **message/photo
sharing** between paired peers.

## Architecture

Fully decentralised peer-to-peer over the LAN:

- **Discovery** — UDP broadcast beacons on port `48710`
  (`lib/services/discovery_service.dart`) announce each device and build the
  dashboard.
- **Transport** — TCP, newline-delimited JSON frames; each send opens a
  short-lived connection (`lib/services/transport_service.dart`).
- **Agreement** — `pair_request` / `pair_response` handshake; only paired
  peers may exchange content (enforced in `HuddleController`).
- **State** — `lib/state/huddle_controller.dart` is a provider/`ChangeNotifier`
  orchestrating discovery, transport, identity and persistence.
- **Persistence** — `shared_preferences` for identity/peers/history,
  `path_provider` for received photos (`lib/services/storage_service.dart`).
- **Wire protocol** — defined in `lib/services/protocol.dart`.

### Layout

```
lib/
  main.dart                  App entry, theme, provider wiring
  ui_helpers.dart            Formatting / icon helpers
  models/                    device.dart, peer.dart, chat_message.dart
  services/                  protocol, identity, discovery, transport, storage
  state/huddle_controller.dart
  screens/                   home, dashboard, huddles, chat, settings
test/widget_test.dart        Unit tests (helpers, protocol, models)
```

## Conventions

- State changes flow through `HuddleController`; UI observes via `provider`.
- Keep the wire protocol in `protocol.dart`; bump `kProtocolVersion` on
  incompatible changes.
- Match the existing comment density and naming style of surrounding code.
- Platform config that must stay in sync with networking: Android permissions
  + `MulticastLock` (`android/`), iOS local-network usage string (`ios/`),
  macOS client/server entitlements (`macos/`).
