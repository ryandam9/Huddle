import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'identity.dart';
import 'protocol.dart';

/// Broadcasts this device's presence and listens for other devices' beacons
/// on the local network using UDP broadcast.
///
/// Every [kBeaconInterval] a small JSON beacon is sent advertising this
/// device's id, name, platform and the TCP port its transport server listens
/// on. Beacons go to the limited broadcast address (255.255.255.255) *and* to
/// each interface's subnet-directed broadcast (e.g. 192.168.0.255). The latter
/// matters on machines with several interfaces (Ethernet + Wi-Fi, a VPN, or
/// VM/Docker adapters): a packet to 255.255.255.255 only leaves the default
/// interface, so without the directed broadcast the beacon may never reach the
/// Wi-Fi other devices are on.
class DiscoveryService {
  DiscoveryService({required this.identity, required this.tcpPort});

  final Identity identity;

  /// The TCP port advertised to peers so they know where to reach us.
  final int tcpPort;

  /// Called for every beacon heard from *another* device.
  void Function(String host, Endpoint endpoint)? onBeacon;

  RawDatagramSocket? _socket;
  Timer? _timer;

  Future<void> start() async {
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      kDiscoveryPort,
      reuseAddress: true,
      reusePort: _supportsReusePort,
    );
    socket.broadcastEnabled = true;
    _socket = socket;

    socket.listen(_onEvent);

    // Send an immediate beacon, then on a fixed cadence.
    _broadcast();
    _timer = Timer.periodic(kBeaconInterval, (_) => _broadcast());
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

    if (json['app'] != kAppTag || json['type'] != 'beacon') return;

    final endpoint = Endpoint.fromJson(json);
    // Ignore our own beacons (they come back on broadcast).
    if (endpoint.id == identity.id) return;

    onBeacon?.call(datagram.address.address, endpoint);
  }

  Future<void> _broadcast() async {
    final socket = _socket;
    if (socket == null) return;

    final payload = utf8.encode(jsonEncode({
      'app': kAppTag,
      'v': kProtocolVersion,
      'type': 'beacon',
      'id': identity.id,
      'name': identity.name,
      'platform': identity.platform,
      'port': tcpPort,
    }));

    for (final target in await _broadcastTargets()) {
      try {
        socket.send(payload, target, kDiscoveryPort);
      } catch (_) {
        // A transient failure on one interface shouldn't stop the others.
      }
    }
  }

  /// The set of addresses to beacon to: the limited broadcast plus each active
  /// IPv4 interface's subnet broadcast (assuming a /24, which covers typical
  /// home networks — dart:io does not expose interface netmasks).
  Future<List<InternetAddress>> _broadcastTargets() async {
    final targets = <String>{'255.255.255.255'};
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
      // Fall back to the limited broadcast only.
    }
    return targets.map(InternetAddress.new).toList();
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
