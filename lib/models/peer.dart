/// A device this device has a standing *agreement* (pairing) with.
///
/// Only paired peers are allowed to exchange messages and photos. A peer is
/// persisted to disk so the agreement is remembered across restarts, even
/// while the peer is offline.
class Peer {
  Peer({
    required this.id,
    required this.name,
    required this.platform,
    required this.pairedAt,
  });

  final String id;
  String name;
  String platform;
  final DateTime pairedAt;

  factory Peer.fromJson(Map<String, dynamic> json) {
    return Peer(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? 'Unknown',
      platform: (json['platform'] as String?) ?? 'unknown',
      pairedAt: DateTime.fromMillisecondsSinceEpoch(
        (json['pairedAt'] as int?) ?? 0,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'platform': platform,
        'pairedAt': pairedAt.millisecondsSinceEpoch,
      };
}
