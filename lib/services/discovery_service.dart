import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'identity.dart';
import 'protocol.dart';

/// Broadcasts this device's presence and listens for other devices' beacons
/// on the local network using UDP broadcast.
///
/// Every [kBeaconInterval] a small JSON beacon is sent to the broadcast
/// address advertising this device's id, name, platform and the TCP port its
/// transport server listens on. Incoming beacons are surfaced via [onBeacon]
/// together with the sender's IP address.
class DiscoveryService {
  DiscoveryService({required this.identity, required this.tcpPort});

  final Identity identity;

  /// The TCP port advertised to peers so they know where to reach us.
  final int tcpPort;

  /// Called for every beacon heard from *another* device.
  ///
  /// [host] is the sender's IP; [endpoint] carries its advertised details.
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

  void _broadcast() {
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

    try {
      socket.send(payload, InternetAddress('255.255.255.255'), kDiscoveryPort);
    } catch (_) {
      // Broadcast can transiently fail (e.g. network change); ignore.
    }
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
