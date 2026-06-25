/// Shared definitions for the Huddle peer-to-peer wire protocol.
///
/// Two channels are used:
///  * **Discovery** — UDP broadcast beacons announcing presence.
///  * **Transport** — TCP, newline-delimited JSON ("NDJSON") frames. Each
///    outbound frame opens a short-lived connection, writes one line and
///    closes. This keeps the protocol completely stateless and robust.
library;

/// Well known application tag so we ignore unrelated traffic on our ports.
const String kAppTag = 'huddle';

/// Protocol version, bumped on incompatible changes.
///
/// v2 introduced the pairing-code handshake (`pair_confirm` + a `code` carried
/// on `pair_response`).
/// v3 added the `ack` frame so a sender can confirm delivery and retry — older
/// peers simply ignore unknown frames, so this stays backward tolerant.
/// v4 added the `read` frame (read receipts) — likewise ignored by older peers.
const int kProtocolVersion = 4;

/// UDP port used for presence beacons. Fixed so every device listens on the
/// same port.
const int kDiscoveryPort = 48710;

/// How often a presence beacon is broadcast.
const Duration kBeaconInterval = Duration(seconds: 3);

/// UDP discovery message types.
/// A [kBeaconType] announces presence; a [kProbeType] asks everyone who hears
/// it to announce immediately (used for on-demand "Discover devices").
const String kBeaconType = 'beacon';
const String kProbeType = 'probe';

/// Frame types exchanged over the TCP transport.
///
/// Pairing is a three-step handshake guarded by a one-time code:
///  1. initiator → `pair_request`
///  2. receiver  → `pair_response` (carries the code the user typed in)
///  3. initiator → `pair_confirm`  (accepts only if the code matched the one
///     it displayed)
class FrameType {
  static const String pairRequest = 'pair_request';
  static const String pairResponse = 'pair_response';
  static const String pairConfirm = 'pair_confirm';
  static const String text = 'text';
  static const String photo = 'photo';
  static const String unpair = 'unpair';

  /// Sent back by the receiver to confirm it stored a frame (carries the
  /// original `mid`), so a reliable sender knows to stop retrying.
  static const String ack = 'ack';

  /// Sent when a peer opens a conversation, carrying the `mids` of messages it
  /// has now read, so the sender can show read receipts.
  static const String read = 'read';
}

/// Identifies the sender of a frame and how to reach it for a reply.
///
/// The host is filled in by the receiver from the socket's remote address
/// (it is not trusted from the wire), while [port] lets us open a reply
/// connection back to the sender's transport server.
class Endpoint {
  Endpoint({
    required this.id,
    required this.name,
    required this.platform,
    required this.port,
    this.host = '',
  });

  final String id;
  final String name;
  final String platform;
  final int port;
  final String host;

  factory Endpoint.fromJson(Map<String, dynamic> json) {
    return Endpoint(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? 'Unknown',
      platform: (json['platform'] as String?) ?? 'unknown',
      port: (json['port'] as int?) ?? 0,
    );
  }

  /// Defensive decode for data off the wire: returns null instead of throwing
  /// when `id` is missing/not a string, so a malformed packet can't crash the
  /// socket listeners. Optional fields fall back to sensible defaults.
  static Endpoint? tryFromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;
    final port = json['port'];
    return Endpoint(
      id: id,
      name: json['name'] is String ? json['name'] as String : 'Unknown',
      platform:
          json['platform'] is String ? json['platform'] as String : 'unknown',
      port: port is int ? port : 0,
    );
  }

  Endpoint withHost(String host) => Endpoint(
        id: id,
        name: name,
        platform: platform,
        port: port,
        host: host,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'platform': platform,
        'port': port,
      };
}

/// A decoded transport frame plus the resolved sender endpoint.
class IncomingFrame {
  IncomingFrame({required this.type, required this.from, required this.data});

  final String type;
  final Endpoint from;
  final Map<String, dynamic> data;
}
