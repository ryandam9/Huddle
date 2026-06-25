import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'identity.dart';
import 'protocol.dart';

/// Broadcasts this device's presence and listens for other devices' beacons
/// on the local network using UDP broadcast.
///
/// Beacons go to the limited broadcast address (255.255.255.255), to each
/// interface's subnet-directed broadcast (e.g. 192.168.0.255), and to an
/// optional user-supplied [customBroadcast] address for unusual networks.
/// A [kProbeType] message can be sent on demand to ask every other device to
/// announce itself immediately (powering the "Discover devices" button).
class DiscoveryService {
  DiscoveryService({
    required this.identity,
    required this.tcpPort,
    this.discoveryPort = kDiscoveryPort,
    this.customBroadcast,
  });

  final Identity identity;

  /// The TCP port advertised to peers so they know where to reach us.
  final int tcpPort;

  /// UDP port presence beacons are sent to / listened on. Must match across
  /// devices to discover each other.
  final int discoveryPort;

  /// Optional extra broadcast address for non-standard subnets (mutable so the
  /// user can change it without restarting discovery).
  String? customBroadcast;

  /// Called for every beacon/probe heard from *another* device.
  void Function(String host, Endpoint endpoint)? onBeacon;

  RawDatagramSocket? _socket;
  Timer? _timer;

  Future<void> start() async {
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      discoveryPort,
      reuseAddress: true,
      reusePort: _supportsReusePort,
    );
    socket.broadcastEnabled = true;
    _socket = socket;

    socket.listen(_onEvent);

    _broadcast();
    _timer = Timer.periodic(kBeaconInterval, (_) => _broadcast());
  }

  /// Sends an on-demand probe so other devices announce themselves now, and
  /// announces ourselves too.
  void refresh() {
    _broadcast(type: kProbeType);
    _broadcast(type: kBeaconType);
  }

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = _socket?.receive();
    if (datagram == null) return;

    Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;
    } catch (_) {
      return; // Not one of ours / malformed.
    }

    if (json['app'] != kAppTag) return;
    final type = json['type'];
    if (type != kBeaconType && type != kProbeType) return;

    final endpoint = Endpoint.tryFromJson(json);
    if (endpoint == null) return; // malformed beacon — ignore
    // Ignore our own messages (they come back on broadcast).
    if (endpoint.id == identity.id) return;

    // Both beacons and probes carry full sender info, so either way we learn
    // about the device.
    onBeacon?.call(datagram.address.address, endpoint);

    // A probe is a request to announce — answer it immediately.
    if (type == kProbeType) {
      _broadcast(type: kBeaconType);
    }
  }

  Future<void> _broadcast({String type = kBeaconType}) async {
    final socket = _socket;
    if (socket == null) return;

    final payload = utf8.encode(jsonEncode({
      'app': kAppTag,
      'v': kProtocolVersion,
      'type': type,
      'id': identity.id,
      'name': identity.name,
      'platform': identity.platform,
      'port': tcpPort,
    }));

    for (final target in await broadcastTargets()) {
      try {
        socket.send(payload, target, discoveryPort);
      } catch (_) {
        // A transient failure on one interface shouldn't stop the others.
      }
    }
  }

  /// The addresses beacons are sent to: the limited broadcast, each active
  /// IPv4 interface's subnet broadcast (assuming a /24), and the optional
  /// user-supplied custom address.
  Future<List<InternetAddress>> broadcastTargets() async {
    final targets = <String>{'255.255.255.255'};

    final custom = customBroadcast?.trim();
    if (custom != null && custom.isNotEmpty) {
      targets.add(custom);
    }

    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final parts = addr.address.split('.');
          if (parts.length == 4) {
            targets.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
          }
        }
      }
    } catch (_) {
      // Fall back to whatever we have.
    }

    return targets
        .map(InternetAddress.tryParse)
        .whereType<InternetAddress>()
        .toList();
  }

  /// reusePort is unsupported on Windows; enabling it there throws.
  bool get _supportsReusePort => !Platform.isWindows;

  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    _socket?.close();
    _socket = null;
  }
}
