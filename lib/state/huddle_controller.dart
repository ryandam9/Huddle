import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_message.dart';
import '../models/device.dart';
import '../models/peer.dart';
import '../services/discovery_service.dart';
import '../services/identity.dart';
import '../services/protocol.dart';
import '../services/storage_service.dart';
import '../services/transport_service.dart';

/// Result of attempting to start a new pairing with a device.
enum PairOutcome { sent, alreadyPaired, unreachable }

/// Central application state and coordinator.
///
/// Owns discovery, transport, identity, persistence and the in-memory view of
/// devices, peers and conversations. The UI observes this via [ChangeNotifier].
class HuddleController extends ChangeNotifier {
  HuddleController();

  late final SharedPreferences _prefs;
  late final StorageService _storage;
  late final Identity identity;

  DiscoveryService? _discovery;
  TransportService? _transport;
  Timer? _pruneTimer;

  final _uuid = const Uuid();

  /// Devices currently visible on the network, keyed by device id.
  final Map<String, Device> _devices = {};

  /// Peers we have a standing agreement with, keyed by id.
  final Map<String, Peer> _peers = {};

  /// Conversation history keyed by peer id.
  final Map<String, List<ChatMessage>> _conversations = {};

  /// Unread message counts keyed by peer id.
  final Map<String, int> _unread = {};

  String? wifiIp;
  bool ready = false;

  /// Set by the UI to prompt the user about incoming pairing requests.
  /// Returns true to accept the agreement.
  Future<bool> Function(Endpoint from)? onPairRequest;

  // --- Read-only views -----------------------------------------------------

  List<Device> get devices {
    final list = _devices.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  List<Peer> get peers {
    final list = _peers.values.toList()
      ..sort((a, b) => b.pairedAt.compareTo(a.pairedAt));
    return list;
  }

  bool isPaired(String id) => _peers.containsKey(id);

  Device? deviceFor(String id) => _devices[id];

  bool isOnline(String id) => _devices[id]?.isOnline ?? false;

  List<ChatMessage> conversation(String peerId) =>
      List.unmodifiable(_conversations[peerId] ?? const []);

  int unreadFor(String peerId) => _unread[peerId] ?? 0;

  int get totalUnread => _unread.values.fold(0, (a, b) => a + b);

  // --- Lifecycle -----------------------------------------------------------

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _storage = StorageService(_prefs);
    identity = await Identity.loadOrCreate(_prefs);

    for (final peer in _storage.loadPeers()) {
      _peers[peer.id] = peer;
      _conversations[peer.id] = _storage.loadMessages(peer.id);
    }

    // Networking may fail to start in restricted environments; keep the app
    // usable (history is still visible) rather than blocking on the spinner.
    try {
      _transport = TransportService(
        id: identity.id,
        name: identity.name,
        platform: identity.platform,
      );
      _transport!.onFrame = _handleFrame;
      await _transport!.start();

      _discovery =
          DiscoveryService(identity: identity, tcpPort: _transport!.port);
      _discovery!.onBeacon = _handleBeacon;
      await _discovery!.start();

      _pruneTimer =
          Timer.periodic(const Duration(seconds: 4), (_) => _pruneDevices());
    } catch (e) {
      debugPrint('Huddle networking failed to start: $e');
    }

    _loadNetworkInfo();

    ready = true;
    notifyListeners();
  }

  Future<void> _loadNetworkInfo() async {
    try {
      wifiIp = await NetworkInfo().getWifiIP();
      notifyListeners();
    } catch (_) {
      // Permission denied or unsupported platform — non fatal.
    }
  }

  Future<void> renameSelf(String newName) async {
    await identity.rename(_prefs, newName);
    // Refresh the name used in outbound frames and beacons.
    _transport?.name = identity.name;
    notifyListeners();
  }

  // --- Discovery -----------------------------------------------------------

  void _handleBeacon(String host, Endpoint endpoint) {
    _upsertDevice(host, endpoint);
  }

  void _upsertDevice(String host, Endpoint endpoint) {
    final existing = _devices[endpoint.id];
    if (existing == null) {
      _devices[endpoint.id] = Device(
        id: endpoint.id,
        name: endpoint.name,
        host: host,
        port: endpoint.port,
        platform: endpoint.platform,
        lastSeen: DateTime.now(),
      );
    } else {
      existing
        ..name = endpoint.name
        ..host = host
        ..port = endpoint.port
        ..platform = endpoint.platform
        ..lastSeen = DateTime.now();
    }
    notifyListeners();
  }

  void _pruneDevices() {
    final now = DateTime.now();
    _devices.removeWhere(
      (_, d) => now.difference(d.lastSeen) > const Duration(seconds: 30),
    );
    // Even without removals, online flags may have flipped — refresh the UI.
    notifyListeners();
  }

  // --- Outbound actions ----------------------------------------------------

  /// Sends a frame if the transport is available; false otherwise.
  Future<bool> _send(
          String host, int port, String type, Map<String, dynamic> data) =>
      _transport?.send(host, port, type, data) ?? Future.value(false);

  /// Initiates a pairing agreement with [device].
  Future<PairOutcome> requestPairing(Device device) async {
    if (isPaired(device.id)) return PairOutcome.alreadyPaired;
    final ok =
        await _send(device.host, device.port, FrameType.pairRequest, const {});
    return ok ? PairOutcome.sent : PairOutcome.unreachable;
  }

  Future<bool> sendText(String peerId, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || !isPaired(peerId)) return false;

    final mid = _uuid.v4();
    final message = ChatMessage(
      id: mid,
      peerId: peerId,
      mine: true,
      kind: MessageKind.text,
      sentAt: DateTime.now(),
      text: trimmed,
    );
    _appendMessage(peerId, message);

    final device = _devices[peerId];
    if (device == null) return false;
    return _send(device.host, device.port, FrameType.text, {
      'mid': mid,
      'text': trimmed,
      'ts': message.sentAt.millisecondsSinceEpoch,
    });
  }

  Future<bool> sendPhoto(String peerId, String sourcePath) async {
    if (!isPaired(peerId)) return false;

    final file = File(sourcePath);
    if (!await file.exists()) return false;
    final bytes = await file.readAsBytes();
    final name = sourcePath.split(Platform.pathSeparator).last;
    final mime = _mimeForName(name);

    // Keep a durable local copy so the bubble still renders later.
    final storedPath = await _storage.saveIncomingPhoto(name, bytes);

    final mid = _uuid.v4();
    final message = ChatMessage(
      id: mid,
      peerId: peerId,
      mine: true,
      kind: MessageKind.photo,
      sentAt: DateTime.now(),
      filePath: storedPath,
      fileName: name,
    );
    _appendMessage(peerId, message);

    final device = _devices[peerId];
    if (device == null) return false;
    return _send(device.host, device.port, FrameType.photo, {
      'mid': mid,
      'name': name,
      'mime': mime,
      'data': base64Encode(bytes),
      'ts': message.sentAt.millisecondsSinceEpoch,
    });
  }

  /// Ends the agreement with [peerId] and notifies the other device.
  Future<void> unpair(String peerId) async {
    final device = _devices[peerId];
    if (device != null) {
      await _send(device.host, device.port, FrameType.unpair, const {});
    }
    _peers.remove(peerId);
    _conversations.remove(peerId);
    _unread.remove(peerId);
    await _storage.savePeers(_peers.values.toList());
    await _storage.deleteConversation(peerId);
    notifyListeners();
  }

  void markRead(String peerId) {
    if ((_unread[peerId] ?? 0) != 0) {
      _unread[peerId] = 0;
      notifyListeners();
    }
  }

  // --- Inbound frames ------------------------------------------------------

  Future<void> _handleFrame(IncomingFrame frame) async {
    // Any contact refreshes our knowledge of where the peer lives.
    _upsertDevice(frame.from.host, frame.from);

    switch (frame.type) {
      case FrameType.pairRequest:
        await _onPairRequest(frame.from);
        break;
      case FrameType.pairResponse:
        _onPairResponse(frame);
        break;
      case FrameType.text:
        _onText(frame);
        break;
      case FrameType.photo:
        await _onPhoto(frame);
        break;
      case FrameType.unpair:
        _onUnpair(frame.from);
        break;
    }
  }

  Future<void> _onPairRequest(Endpoint from) async {
    // Re-pairing with a known peer needs no prompt.
    final accept = isPaired(from.id)
        ? true
        : (await onPairRequest?.call(from) ?? false);

    if (accept) {
      _addPeer(from, system: 'You are now connected with ${from.name}.');
    }
    await _send(from.host, from.port, FrameType.pairResponse, {
      'accepted': accept,
    });
  }

  void _onPairResponse(IncomingFrame frame) {
    final accepted = (frame.data['accepted'] as bool?) ?? false;
    if (accepted) {
      _addPeer(frame.from,
          system: '${frame.from.name} accepted your request.');
    } else {
      // Surface the rejection in any existing conversation context only if we
      // already know them; otherwise nothing to show.
    }
  }

  void _onText(IncomingFrame frame) {
    if (!isPaired(frame.from.id)) return; // No agreement → ignore.
    final text = frame.data['text'] as String?;
    if (text == null) return;
    final mid = (frame.data['mid'] as String?) ?? _uuid.v4();
    if (_isDuplicate(frame.from.id, mid)) return;

    _appendMessage(
      frame.from.id,
      ChatMessage(
        id: mid,
        peerId: frame.from.id,
        mine: false,
        kind: MessageKind.text,
        sentAt: _tsFrom(frame.data),
        text: text,
      ),
      bumpUnread: true,
    );
  }

  Future<void> _onPhoto(IncomingFrame frame) async {
    if (!isPaired(frame.from.id)) return;
    final data = frame.data['data'] as String?;
    if (data == null) return;
    final mid = (frame.data['mid'] as String?) ?? _uuid.v4();
    if (_isDuplicate(frame.from.id, mid)) return;

    final name = (frame.data['name'] as String?) ?? 'photo';
    List<int> bytes;
    try {
      bytes = base64Decode(data);
    } catch (_) {
      return;
    }
    final path = await _storage.saveIncomingPhoto(name, bytes);

    _appendMessage(
      frame.from.id,
      ChatMessage(
        id: mid,
        peerId: frame.from.id,
        mine: false,
        kind: MessageKind.photo,
        sentAt: _tsFrom(frame.data),
        filePath: path,
        fileName: name,
      ),
      bumpUnread: true,
    );
  }

  void _onUnpair(Endpoint from) {
    if (!isPaired(from.id)) return;
    _peers.remove(from.id);
    _storage.savePeers(_peers.values.toList());
    notifyListeners();
  }

  // --- Helpers -------------------------------------------------------------

  void _addPeer(Endpoint from, {String? system}) {
    _peers[from.id] = Peer(
      id: from.id,
      name: from.name,
      platform: from.platform,
      pairedAt: DateTime.now(),
    );
    _storage.savePeers(_peers.values.toList());

    _conversations.putIfAbsent(from.id, () => []);
    if (system != null) {
      _appendMessage(
        from.id,
        ChatMessage(
          id: _uuid.v4(),
          peerId: from.id,
          mine: false,
          kind: MessageKind.system,
          sentAt: DateTime.now(),
          text: system,
        ),
      );
    } else {
      notifyListeners();
    }
  }

  void _appendMessage(String peerId, ChatMessage message,
      {bool bumpUnread = false}) {
    final list = _conversations.putIfAbsent(peerId, () => []);
    list.add(message);
    _storage.saveMessages(peerId, list);
    if (bumpUnread) {
      _unread[peerId] = (_unread[peerId] ?? 0) + 1;
    }
    notifyListeners();
  }

  bool _isDuplicate(String peerId, String mid) {
    final list = _conversations[peerId];
    if (list == null) return false;
    return list.any((m) => m.id == mid);
  }

  DateTime _tsFrom(Map<String, dynamic> data) {
    final ts = data['ts'] as int?;
    return ts != null
        ? DateTime.fromMillisecondsSinceEpoch(ts)
        : DateTime.now();
  }

  String _mimeForName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
  }

  @override
  void dispose() {
    _pruneTimer?.cancel();
    _discovery?.dispose();
    _transport?.dispose();
    super.dispose();
  }
}
