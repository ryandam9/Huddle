/// A device discovered on the local network via UDP beacons.
///
/// A [Device] is *transient* — it only exists while we keep hearing the
/// other device's presence beacons. Once a device stops broadcasting it is
/// considered offline and eventually dropped from the dashboard. Pairing
/// information lives in [Peer] instead, so an agreement survives even when a
/// device temporarily disappears.
class Device {
  Device({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.platform,
    required this.lastSeen,
  });

  /// Stable unique id of the remote device.
  final String id;

  /// Human friendly name the remote device advertises for itself.
  String name;

  /// IP address the device was last reached at.
  String host;

  /// TCP port the device's transport server is listening on.
  int port;

  /// Reported platform (android, ios, macos, linux, windows, ...).
  String platform;

  /// Last time we heard from this device (beacon or direct frame).
  DateTime lastSeen;

  /// How long a device may stay silent before we treat it as offline.
  static const Duration onlineWindow = Duration(seconds: 12);

  bool get isOnline => DateTime.now().difference(lastSeen) <= onlineWindow;

  Device copyWith({
    String? name,
    String? host,
    int? port,
    String? platform,
    DateTime? lastSeen,
  }) {
    return Device(
      id: id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      platform: platform ?? this.platform,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}
