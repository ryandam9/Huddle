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
const int kProtocolVersion = 1;

/// UDP port used for presence beacons. Fixed so every device listens on the
/// same port.
const int kDiscoveryPort = 48710;

/// How often a presence beacon is broadcast.
const Duration kBeaconInterval = Duration(seconds: 3);

/// Frame types exchanged over the TCP transport.
class FrameType {
  static const String pairRequest = 'pair_request';
  static const String pairResponse = 'pair_response';
  static const String text = 'text';
  static const String photo = 'photo';
  static const String unpair = 'unpair';
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
