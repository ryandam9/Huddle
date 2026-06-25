# Huddle

Huddle is a cross-platform Flutter app for **sharing messages and photos
directly between devices on the same local network** — no account, no cloud,
no internet required. Everything happens peer-to-peer over your Wi-Fi/LAN.

## What it does

1. **Dashboard of devices** — every device running Huddle on the same network
   is discovered automatically and listed, with a live online/offline
   indicator.
2. **Agreements (pairing)** — before two devices can talk, one sends a pairing
   request and the other explicitly **accepts**. This handshake is the
   "agreement". Only paired devices may exchange content.
3. **Sharing** — once paired, devices can exchange **text messages** and
   **photos** in a familiar chat interface. Conversation history is stored
   locally on each device.

Sharing extras:

- **Batch & folder sending** — pick many photos at once, or (on desktop) a
  whole folder; they send sequentially in the background with a progress strip.
- **Reliable delivery** — each message is acknowledged and retried; outgoing
  bubbles show *sending → delivered → read*, with tap-to-retry on failure.
- **Resumable queue** — a message to an offline peer is queued and delivered
  automatically when the peer reappears, even across an app restart.
- **Background transfers (Android)** — a foreground service keeps a batch going
  while the app is backgrounded.
- **Conversation management** — clear a conversation, delete a message, and
  choose a custom download folder for received files.

## How it works

Huddle is fully decentralised — there is no server.

| Concern        | Mechanism |
| -------------- | --------- |
| **Discovery**  | UDP broadcast beacons on port `48710`. Each device announces its id, name, platform and TCP port every few seconds and listens for others. |
| **Transport**  | TCP with newline-delimited JSON frames. Each message opens a short-lived connection, making the protocol stateless and robust. |
| **Agreement**  | A three-step, code-verified handshake: the initiator shows a one-time 6-digit code, the other device's user types it in (`pair_response`), and the initiator confirms only on a match (`pair_confirm`). Both sides then persist each other as a paired *peer*. |
| **Sharing**    | `text` and `photo` (base64) frames flow only between paired peers. Received photos are written to the app's documents directory. |
| **Persistence**| Identity, paired peers and conversations are stored via `shared_preferences`; photos on disk via `path_provider`. |

The wire protocol lives in [`lib/services/protocol.dart`](lib/services/protocol.dart).

## Project layout

```
lib/
  main.dart                     App entry + theme + provider wiring
  ui_helpers.dart               Small formatting / icon helpers
  models/
    device.dart                 A device seen on the network (transient)
    peer.dart                   A paired device / standing agreement
    chat_message.dart           A text/photo/system message
  services/
    protocol.dart               Shared wire-protocol definitions
    identity.dart               This device's persistent id + display name
    discovery_service.dart      UDP broadcast presence (beacons)
    transport_service.dart      TCP server + one-shot frame sender
    storage_service.dart        Persistence for peers, history and media
  state/
    huddle_controller.dart      ChangeNotifier orchestrating everything
  screens/
    home_screen.dart            Bottom-nav / rail shell + pairing prompts
    dashboard_screen.dart       Devices on the network
    messages_screen.dart        List of paired conversations
    chat_screen.dart            A one-to-one conversation
    settings_screen.dart        Identity, downloads, agreements
    network_settings_screen.dart  Ports, broadcast address, diagnostics
    help_screen.dart            Troubleshooting
```

## Running

```bash
flutter pub get
flutter run        # pick a device; run on two devices on the same Wi-Fi
flutter test       # unit tests for helpers, protocol and models
```

To try it end-to-end, run Huddle on two devices connected to the same
network (e.g. two phones, or a phone and a desktop). They will appear on each
other's **Devices** tab; pair from one, accept on the other, then chat.

## Platform notes

- **Android** — network and `NEARBY_WIFI_DEVICES` permissions are declared,
  and `MainActivity` holds a `MulticastLock` so broadcast beacons are
  received.
- **iOS** — `NSLocalNetworkUsageDescription` and a photo-library usage string
  are set; iOS shows a local-network permission prompt on first launch.
- **macOS** — the client and server network entitlements are enabled for both
  debug and release.
- **Desktop (Linux/Windows/macOS)** — works out of the box on the same LAN.

## Limitations

- **Security** — traffic is **not encrypted**, and frames are trusted by paired
  peer id (there is no shared-secret authentication or replay protection yet).
  Treat Huddle as suitable for networks you trust; anyone able to capture LAN
  packets could read message/photo content. Inbound frames are size-capped and
  acknowledgements are checked against the sending peer, but end-to-end
  encryption and signed frames are not yet implemented.
- Photos are sent inline as base64, which is fine for typical images but not
  intended for very large files (a chunked transfer is planned).
- Discovery relies on UDP broadcast; networks that isolate clients (guest
  Wi-Fi, "AP isolation") will prevent devices from seeing each other.
