import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_message.dart';
import '../models/device.dart';
import '../models/peer.dart';
import '../services/discovery_service.dart';
import '../services/foreground_service.dart';
import '../services/identity.dart';
import '../services/message_store.dart';
import '../services/pairing.dart';
import '../services/protocol.dart';
import '../services/storage_service.dart';
import '../services/transport_service.dart';

/// Progress of an outgoing pairing the user has started.
enum PairStatus {
  /// Request sent; waiting for the other device to enter our code.
  waiting,

  /// Code matched — both devices are now paired.
  success,

  /// The other device declined the request.
  declined,

  /// The other device typed the wrong code.
  mismatch,

  /// We could not reach the other device.
  unreachable,
}

/// A pairing the local user initiated, surfaced to the UI so it can show the
/// code and react to the outcome.
class OutgoingPairing {
  OutgoingPairing({
    required this.peerId,
    required this.peerName,
    required this.code,
    this.status = PairStatus.waiting,
  });

  final String peerId;
  final String peerName;
  final String code;
  PairStatus status;
}

/// Progress of a background batch photo send, surfaced to the UI so it can show
/// "sending 3 of 10" without the caller having to await the whole batch.
class TransferProgress {
  const TransferProgress({
    required this.peerId,
    required this.total,
    this.sent = 0,
    this.failed = 0,
  });

  /// The peer the batch is being sent to.
  final String peerId;

  /// Number of files in the batch.
  final int total;

  /// Files delivered (flushed to the peer) so far.
  final int sent;

  /// Files that could not be delivered (e.g. the peer is offline).
  final int failed;

  int get completed => sent + failed;
  int get remaining => total - completed;
  bool get isComplete => completed >= total;

  TransferProgress _advance({required bool ok}) => TransferProgress(
        peerId: peerId,
        total: total,
        sent: ok ? sent + 1 : sent,
        failed: ok ? failed : failed + 1,
      );
}

/// Central application state and coordinator.
///
/// Owns discovery, transport, identity, persistence and the in-memory view of
/// devices, peers and conversations. The UI observes this via [ChangeNotifier].
class HuddleController extends ChangeNotifier {
  HuddleController({ForegroundService? foreground, this.databaseFactory})
      : _foreground = foreground ?? AndroidForegroundService();

  /// Keeps the process alive during a batch so it can finish in the background
  /// (Android only; a no-op elsewhere). Injectable for tests.
  final ForegroundService _foreground;

  /// Database factory for the message store; null uses the on-disk default.
  /// Tests inject an in-memory factory.
  @visibleForTesting
  final DatabaseFactory? databaseFactory;

  late final SharedPreferences _prefs;
  late final StorageService _storage;
  Database? _db;
  late final MessageStore _messages;
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

  /// Mids received from each peer that haven't yet been reported as read; sent
  /// in a `read` receipt when the conversation is opened (markRead).
  final Map<String, List<String>> _unackedReceived = {};

  String? wifiIp;
  bool ready = false;

  int _discoveryPort = kDiscoveryPort;
  String? _customBroadcast;

  /// User-chosen folder for received files (null = default app folder).
  String? _customDownloadDir;

  /// Resolved absolute path of the current download folder, cached for the UI.
  String? _downloadLocation;

  /// Whether to surface an in-app notification when content is received.
  bool _notifyOnReceive = true;

  /// The pairing the local user is currently initiating, if any.
  OutgoingPairing? outgoingPairing;

  /// Progress of the current (or most recent) background batch photo send.
  TransferProgress? _transfer;

  /// Serialises batch sends so two batches never interleave on the wire.
  Future<void> _transferChain = Future.value();

  /// Codes we generated and displayed for outgoing pairings, keyed by peer id,
  /// used to verify the code the other device echoes back.
  final Map<String, String> _pendingCodes = {};

  /// Reliable sends awaiting an `ack`, keyed by message id. Records the peer the
  /// message was sent to so a stray/spoofed ack from another device can't
  /// complete it. The completer resolves when the matching ack arrives.
  final Map<String, ({String peerId, Completer<void> completer})> _pendingAcks =
      {};

  /// How long a reliable send waits for an `ack` before resending.
  @visibleForTesting
  Duration ackTimeout = const Duration(seconds: 4);

  /// How many times a reliable send is attempted before giving up.
  @visibleForTesting
  int maxSendAttempts = 3;

  /// Messages currently being delivered (by mid), so a resume pass never
  /// double-sends something that's already in flight.
  final Set<String> _inFlight = {};

  /// Peers whose resume drain is currently running. Per-peer (not a single
  /// global flag) so a drain for one peer never blocks another's.
  final Set<String> _flushingPeers = {};

  /// Peers for which a flush was requested while a drain was already running, so
  /// the drain re-runs once it finishes — closing a lost-wakeup window when a
  /// peer becomes reachable mid-drain.
  final Set<String> _flushAgain = {};

  /// Set by the UI to prompt the user when another device requests pairing.
  /// Should return the code the user typed in, or null if they declined.
  Future<String?> Function(Endpoint from)? onPairRequest;

  /// Set by the UI to surface transient pairing notices (e.g. "Paired with X"
  /// or a failed code) that arrive asynchronously.
  void Function(String message)? onNotice;

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

  /// The TCP port the transport server is listening on (0 if not started).
  int get tcpPort => _transport?.port ?? 0;

  /// The UDP port used for discovery beacons.
  int get discoveryPort => _discoveryPort;

  /// Optional user-configured extra broadcast address (null if unset).
  String? get customBroadcast => _customBroadcast;

  /// Absolute path of the folder where received files are saved. Null only
  /// briefly during startup before it has been resolved.
  String? get downloadLocation => _downloadLocation;

  /// True when the user has chosen a custom download folder (vs. the default).
  bool get isCustomDownloadDir => _customDownloadDir != null;

  /// Whether incoming files and messages raise an in-app notification.
  bool get notifyOnReceive => _notifyOnReceive;

  /// Progress of the current (or most recent) background batch photo send, or
  /// null if none has been started. Observe to show a "sending 3 of 10" strip.
  TransferProgress? get transfer => _transfer;

  /// The broadcast addresses discovery is currently sending beacons to.
  Future<List<String>> broadcastTargets() async {
    final targets = await _discovery?.broadcastTargets();
    return targets?.map((a) => a.address).toList() ?? const [];
  }

  /// Injects a discovered device as if a presence beacon had been heard.
  /// Lets tests wire two controllers together without relying on UDP
  /// broadcast delivery.
  @visibleForTesting
  void ingestBeacon(String host, Endpoint endpoint) =>
      _upsertDevice(host, endpoint);

  // --- Lifecycle -----------------------------------------------------------

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _storage = StorageService(_prefs);
    identity = await Identity.loadOrCreate(_prefs);

    await _openMessageStore();

    for (final peer in _storage.loadPeers()) {
      _peers[peer.id] = peer;
      _conversations[peer.id] = await _messages.messagesFor(peer.id);
    }
    // Restore unread counts and pending read-receipt ids.
    (await _messages.loadMeta()).forEach((peerId, m) {
      if (m.unread > 0) _unread[peerId] = m.unread;
      if (m.unacked.isNotEmpty) _unackedReceived[peerId] = List.of(m.unacked);
    });

    _discoveryPort = _storage.loadDiscoveryPort();
    _customBroadcast = _storage.loadCustomBroadcast();
    _customDownloadDir = _storage.loadCustomDownloadDir();
    _notifyOnReceive = _storage.loadNotifyOnReceive();
    // Resolving the default folder touches the platform (path_provider); keep
    // startup resilient on platforms/tests where that's unavailable.
    try {
      _downloadLocation = await _storage.resolveMediaPath();
    } catch (e) {
      debugPrint('Huddle: could not resolve download folder: $e');
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

      _discovery = DiscoveryService(
        identity: identity,
        tcpPort: _transport!.port,
        discoveryPort: _discoveryPort,
        customBroadcast: _customBroadcast,
      );
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

  /// Opens the conversation database and runs the one-time import from the old
  /// `shared_preferences` format. Tests inject an in-memory [DatabaseFactory];
  /// production stores a file in the app documents directory. If no writable
  /// location is available (an unsupported platform, or a restricted test host
  /// with no path_provider) it falls back to an in-memory store so history
  /// still works for the session rather than crashing startup.
  Future<void> _openMessageStore() async {
    final injected = databaseFactory;
    if (injected != null) {
      _db = await injected.openDatabase('huddle.db');
    } else {
      try {
        final dir = await getApplicationDocumentsDirectory();
        _db = await databaseFactoryIo.openDatabase('${dir.path}/huddle.db');
      } catch (e) {
        debugPrint('Huddle: on-disk message store unavailable, using memory: $e');
        _db = await newDatabaseFactoryMemory().openDatabase('huddle.db');
      }
    }
    _messages = MessageStore(_db!);
    await _messages.migrateFromPrefs(_prefs);
  }

  Future<void> _loadNetworkInfo() async {
    try {
      wifiIp = await _detectLocalIp();
      notifyListeners();
    } catch (_) {
      // Unsupported platform / no network — non fatal.
    }
  }

  /// Finds this device's LAN IPv4 address using the platform's network
  /// interfaces (no plugin, no special permissions). Prefers a private
  /// (RFC 1918) address, falling back to the first non-loopback IPv4.
  Future<String?> _detectLocalIp() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    final addresses = [
      for (final iface in interfaces) ...iface.addresses.map((a) => a.address),
    ];
    for (final ip in addresses) {
      if (_isPrivateIp(ip)) return ip;
    }
    return addresses.isEmpty ? null : addresses.first;
  }

  bool _isPrivateIp(String ip) =>
      ip.startsWith('10.') ||
      ip.startsWith('192.168.') ||
      RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip);

  Future<void> renameSelf(String newName) async {
    await identity.rename(_prefs, newName);
    // Refresh the name used in outbound frames and beacons.
    _transport?.name = identity.name;
    notifyListeners();
  }

  /// Triggers an on-demand scan: asks other devices to announce now.
  void refreshDiscovery() => _discovery?.refresh();

  /// Sets (or clears, when null/blank) an extra broadcast address for unusual
  /// networks. Applied immediately; no restart needed.
  Future<void> setCustomBroadcast(String? address) async {
    final v = address?.trim();
    _customBroadcast = (v == null || v.isEmpty) ? null : v;
    await _storage.saveCustomBroadcast(_customBroadcast);
    _discovery?.customBroadcast = _customBroadcast;
    notifyListeners();
  }

  /// Changes the discovery (UDP) port and restarts discovery on it. The port
  /// must match on every device, so callers should warn the user.
  Future<void> setDiscoveryPort(int port) async {
    if (port == _discoveryPort) return;
    final previous = _discoveryPort;
    await _discovery?.dispose();

    // Restart first and only persist the new port if it actually came up;
    // otherwise roll back to the previous (working) one so a bad port can't be
    // saved and break discovery on the next launch.
    if (await _startDiscoveryOn(port)) {
      _discoveryPort = port;
      await _storage.saveDiscoveryPort(port);
    } else {
      _discoveryPort = previous;
      await _startDiscoveryOn(previous);
    }
    notifyListeners();
  }

  Future<bool> _startDiscoveryOn(int port) async {
    try {
      _discovery = DiscoveryService(
        identity: identity,
        tcpPort: tcpPort,
        discoveryPort: port,
        customBroadcast: _customBroadcast,
      );
      _discovery!.onBeacon = _handleBeacon;
      await _discovery!.start();
      return true;
    } catch (e) {
      debugPrint('Huddle: failed to start discovery on port $port: $e');
      return false;
    }
  }

  /// Changes the folder where received files are saved. Pass null to restore
  /// the default app folder. Returns false (without changing anything) if the
  /// folder can't be created or written to. Existing files are left in place.
  Future<bool> setDownloadDirectory(String? path) async {
    final v = path?.trim();
    if (v != null && v.isNotEmpty) {
      final ok = await _storage.canUseDownloadDir(v);
      if (!ok) return false;
    }
    _customDownloadDir = (v == null || v.isEmpty) ? null : v;
    _storage.customDownloadDir = _customDownloadDir;
    await _storage.saveCustomDownloadDir(_customDownloadDir);
    _downloadLocation = await _storage.resolveMediaPath();
    notifyListeners();
    return true;
  }

  /// Turns the in-app "received" notifications on or off.
  Future<void> setNotifyOnReceive(bool enabled) async {
    if (enabled == _notifyOnReceive) return;
    _notifyOnReceive = enabled;
    await _storage.saveNotifyOnReceive(enabled);
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
    // The peer is reachable now — flush anything queued for it (including
    // transfers interrupted by an app restart).
    _flushPending(endpoint.id);
  }

  void _pruneDevices() {
    final now = DateTime.now();
    final onlineBefore = {
      for (final e in _devices.entries) e.key: e.value.isOnline,
    };
    final countBefore = _devices.length;
    _devices.removeWhere(
      (_, d) => now.difference(d.lastSeen) > const Duration(seconds: 30),
    );
    // Only rebuild the UI when something visible actually changed — a device
    // dropped, or an online flag flipped — rather than every 4 seconds.
    final changed = _devices.length != countBefore ||
        _devices.entries.any((e) => onlineBefore[e.key] != e.value.isOnline);
    if (changed) notifyListeners();
  }

  // --- Outbound actions ----------------------------------------------------

  /// Sends a frame if the transport is available; false otherwise.
  Future<bool> _send(
          String host, int port, String type, Map<String, dynamic> data) =>
      _transport?.send(host, port, type, data) ?? Future.value(false);

  /// Sends a frame and waits for the receiver's `ack` (keyed by [mid]),
  /// resending up to [maxSendAttempts] times if no acknowledgement arrives
  /// within [ackTimeout]. Returns true once acknowledged, false if every
  /// attempt is exhausted. Used for background batches where silent loss
  /// would be worst (the user isn't watching each file).
  Future<bool> _sendReliably(String peerId, String host, int port, String type,
      Map<String, dynamic> data, String mid) async {
    for (var attempt = 0; attempt < maxSendAttempts; attempt++) {
      final completer = Completer<void>();
      _pendingAcks[mid] = (peerId: peerId, completer: completer);
      final flushed = await _send(host, port, type, data);
      if (flushed) {
        try {
          await completer.future.timeout(ackTimeout);
          _pendingAcks.remove(mid);
          return true;
        } on TimeoutException {
          // No acknowledgement in time — fall through and resend.
        }
      }
      _pendingAcks.remove(mid);
    }
    return false;
  }

  /// Confirms receipt of [mid] back to [to] so a reliable sender stops
  /// retrying. Fire-and-forget; the sender tolerates a lost ack by resending.
  void _ackTo(Endpoint to, String mid) {
    _send(to.host, to.port, FrameType.ack, {'mid': mid});
  }

  /// Initiates a pairing agreement with [device]. Generates a one-time code,
  /// surfaces it via [outgoingPairing] for the UI to display, and sends the
  /// request. The other device's user must type this code to complete the
  /// handshake. Returns the generated code.
  String startPairing(Device device) {
    final code = generatePairingCode();
    _pendingCodes[device.id] = code;
    outgoingPairing = OutgoingPairing(
      peerId: device.id,
      peerName: device.name,
      code: code,
    );
    notifyListeners();

    _send(device.host, device.port, FrameType.pairRequest, const {}).then((ok) {
      // Only react if this is still the active pairing for that device.
      if (!ok && outgoingPairing?.peerId == device.id) {
        _pendingCodes.remove(device.id);
        outgoingPairing!.status = PairStatus.unreachable;
        notifyListeners();
      }
    });
    return code;
  }

  /// Clears the active outgoing pairing (e.g. the user dismissed the dialog).
  void cancelPairing() {
    final pending = outgoingPairing;
    if (pending != null) _pendingCodes.remove(pending.peerId);
    outgoingPairing = null;
    notifyListeners();
  }

  /// Sends a text message. It's stored and shown immediately (optimistically)
  /// with a `sending` status, then delivered in the background with
  /// acknowledgement + retry. While the peer is unreachable the message stays
  /// queued (`sending`) and is delivered automatically once the peer is seen
  /// again — even across an app restart. Returns true if accepted (paired and
  /// non-empty).
  Future<bool> sendText(String peerId, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || !isPaired(peerId)) return false;

    await _appendMessage(
      peerId,
      ChatMessage(
        id: _uuid.v4(),
        peerId: peerId,
        mine: true,
        kind: MessageKind.text,
        sentAt: DateTime.now(),
        text: trimmed,
        status: MessageStatus.sending,
      ),
    );
    _flushPending(peerId); // deliver now if reachable, else it stays queued
    return true;
  }

  /// Advances the delivery [status] of message [mid] in [peerId]'s conversation
  /// (e.g. when its acknowledgement arrives) and persists the change.
  Future<void> _setMessageStatus(
      String peerId, String mid, MessageStatus status) async {
    final list = _conversations[peerId];
    if (list == null) return;
    for (final m in list) {
      if (m.id == mid) {
        if (m.status != status) {
          m.status = status;
          notifyListeners();
          await _messages.updateStatus(mid, status);
        }
        return;
      }
    }
  }

  /// Re-attempts a previously `failed` outgoing message: resets it to `sending`
  /// and re-runs the queue (delivering now if the peer is reachable, otherwise
  /// staying queued). Returns true if a retry was started — i.e. the message
  /// exists, is ours, and had failed; false otherwise.
  bool retryMessage(String peerId, String mid) {
    final list = _conversations[peerId];
    if (list == null) return false;
    for (final m in list) {
      if (m.id == mid) {
        if (!m.mine || m.status != MessageStatus.failed) return false;
        m.status = MessageStatus.sending;
        unawaited(_messages.updateStatus(mid, MessageStatus.sending));
        notifyListeners();
        _flushPending(peerId);
        return true;
      }
    }
    return false;
  }

  /// Re-delivers any of [peerId]'s own messages still `sending` — freshly
  /// queued, or left over from a transfer interrupted (even by an app restart)
  /// — one at a time. Skipped while an active batch is driving delivery itself,
  /// and serialised so a burst of beacons can't spawn parallel drains.
  void _flushPending(String peerId) {
    final t = _transfer;
    if (t != null && t.peerId == peerId && !t.isComplete) return; // batch owns it
    if (_flushingPeers.contains(peerId)) {
      // A drain is already running. Note that another pass is wanted: the peer
      // may have become reachable (this very request) just as a device-less
      // pass was giving up, and we must not lose that wakeup.
      _flushAgain.add(peerId);
      return;
    }
    _flushingPeers.add(peerId);
    unawaited(_drainPending(peerId));
  }

  Future<void> _drainPending(String peerId) async {
    try {
      while (true) {
        final next = _nextPending(peerId);
        if (next == null) break;
        final result = await _deliverStored(peerId, next);
        if (result == null) break; // peer unreachable now — retry on its return
      }
    } finally {
      _flushingPeers.remove(peerId);
    }
    // If a flush was requested mid-drain (e.g. the peer appeared just as a
    // device-less pass was giving up), run another pass now that the guard is
    // released so the request isn't lost.
    if (_flushAgain.remove(peerId)) _flushPending(peerId);
  }

  ChatMessage? _nextPending(String peerId) {
    for (final m in _conversations[peerId] ?? const <ChatMessage>[]) {
      if (m.mine &&
          m.status == MessageStatus.sending &&
          !_inFlight.contains(m.id)) {
        return m;
      }
    }
    return null;
  }

  /// Sends a single photo. Stores it (shown immediately), then delivers
  /// reliably; returns true once the peer acknowledges receipt.
  Future<bool> sendPhoto(String peerId, String sourcePath) async {
    if (!isPaired(peerId)) return false;
    final message = await _enqueuePhoto(peerId, sourcePath);
    if (message == null) return false;
    return (await _deliverStored(peerId, message)) ?? false;
  }

  /// Reads [sourcePath], keeps a durable local copy (so the bubble renders and
  /// the send can be resumed later) and appends a `sending` photo message.
  /// Returns the stored message, or null if the source can't be read.
  Future<ChatMessage?> _enqueuePhoto(String peerId, String sourcePath) async {
    final file = File(sourcePath);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    final name = sourcePath.split(Platform.pathSeparator).last;
    final storedPath = await _storage.saveIncomingPhoto(name, bytes);
    final message = ChatMessage(
      id: _uuid.v4(),
      peerId: peerId,
      mine: true,
      kind: MessageKind.photo,
      sentAt: DateTime.now(),
      filePath: storedPath,
      fileName: name,
      status: MessageStatus.sending,
    );
    await _appendMessage(peerId, message);
    return message;
  }

  /// Delivers a stored outgoing [message] reliably and records the outcome on
  /// it. Returns true if delivered (acknowledged), false if it failed (the peer
  /// was reachable but didn't confirm, or the file is gone), or null if it
  /// couldn't be attempted now (peer unreachable, or already in flight) — in
  /// which case it stays `sending` and is retried when the peer reappears.
  Future<bool?> _deliverStored(String peerId, ChatMessage message) async {
    if (message.status == MessageStatus.delivered) return true;
    if (_inFlight.contains(message.id)) return null;
    final device = _devices[peerId];
    if (device == null) return null;

    _inFlight.add(message.id);
    try {
      final data = await _frameFor(message);
      if (data == null) {
        await _setMessageStatus(peerId, message.id, MessageStatus.failed);
        return false;
      }
      final type =
          message.kind == MessageKind.photo ? FrameType.photo : FrameType.text;
      final ok = await _sendReliably(
          peerId, device.host, device.port, type, data, message.id);
      await _setMessageStatus(peerId, message.id,
          ok ? MessageStatus.delivered : MessageStatus.failed);
      return ok;
    } finally {
      _inFlight.remove(message.id);
    }
  }

  /// Builds the wire payload for [message], or null if its file has gone.
  Future<Map<String, dynamic>?> _frameFor(ChatMessage message) async {
    final ts = message.sentAt.millisecondsSinceEpoch;
    if (message.kind == MessageKind.photo) {
      final path = message.filePath;
      if (path == null) return null;
      final file = File(path);
      if (!await file.exists()) return null;
      final name = message.fileName ?? 'photo';
      return {
        'mid': message.id,
        'name': name,
        'mime': _mimeForName(name),
        'data': base64Encode(await file.readAsBytes()),
        'ts': ts,
      };
    }
    return {'mid': message.id, 'text': message.text ?? '', 'ts': ts};
  }

  /// Sends every photo in [paths] to [peerId], one after another, in the
  /// background. Returns immediately to the caller (fire-and-forget); progress
  /// is published via [transfer] for the UI to observe. Successive calls are
  /// queued so two batches never interleave their frames on the wire.
  Future<void> sendPhotos(String peerId, List<String> paths) {
    _transferChain = _transferChain
        .then((_) => _runBatch(peerId, paths))
        .catchError((Object e) {
      // Never let one failed batch poison the chain for every future send.
      debugPrint('Huddle: batch send failed: $e');
      _transfer = null;
      notifyListeners();
    });
    return _transferChain;
  }

  Future<void> _runBatch(String peerId, List<String> paths) async {
    if (!isPaired(peerId)) return;
    final items = paths.where((p) => p.trim().isNotEmpty).toList();
    if (items.isEmpty) return;

    // Persist the whole batch upfront (as `sending` messages with durable local
    // copies) so an interruption leaves the remainder queued to resume later.
    final pending = <ChatMessage>[];
    for (final path in items) {
      final message = await _enqueuePhoto(peerId, path);
      if (message != null) pending.add(message);
    }
    if (pending.isEmpty) return;

    _transfer = TransferProgress(peerId: peerId, total: pending.length);
    notifyListeners();

    // Keep the process alive so the batch can finish even if the app is
    // backgrounded (Android foreground service; a no-op on other platforms).
    final noun = pending.length == 1 ? 'photo' : 'photos';
    await _foreground.start('Sending ${pending.length} $noun…');
    try {
      for (final message in pending) {
        final result = await _deliverStored(peerId, message);
        if (result == null) {
          // Peer became unreachable — the rest stay queued and resume on its
          // next appearance. Stop showing active progress.
          _transfer = null;
          notifyListeners();
          return;
        }
        _transfer = _transfer!._advance(ok: result);
        notifyListeners();
      }
    } finally {
      await _foreground.stop();
    }
  }

  /// Ends the agreement with [peerId] and notifies the other device.
  Future<void> unpair(String peerId) async {
    final device = _devices[peerId];
    if (device != null) {
      await _send(device.host, device.port, FrameType.unpair, const {});
    }
    final removed = _conversations.remove(peerId) ?? const <ChatMessage>[];
    _peers.remove(peerId);
    _unread.remove(peerId);
    _unackedReceived.remove(peerId);
    await _storage.savePeers(_peers.values.toList());
    await _messages.deleteConversation(peerId);
    await _deleteMediaFor(removed);
    notifyListeners();
  }

  /// Clears the message history with [peerId] while keeping the agreement
  /// (unlike [unpair], which removes the peer entirely).
  Future<void> clearConversation(String peerId) async {
    final removed = _conversations[peerId] ?? const <ChatMessage>[];
    _conversations[peerId] = [];
    _unread.remove(peerId);
    _unackedReceived.remove(peerId);
    await _messages.deleteConversation(peerId);
    await _deleteMediaFor(removed);
    notifyListeners();
  }

  /// Deletes a single message from [peerId]'s conversation. Returns true if a
  /// message was removed.
  Future<bool> deleteMessage(String peerId, String mid) async {
    final list = _conversations[peerId];
    if (list == null) return false;
    final index = list.indexWhere((m) => m.id == mid);
    if (index < 0) return false;
    final removed = list.removeAt(index);
    await _messages.deleteMessage(mid);
    await _deleteMediaFor([removed]);
    notifyListeners();
    return true;
  }

  void markRead(String peerId) {
    final clearedReceipts = _sendReadReceipt(peerId);
    final hadUnread = (_unread[peerId] ?? 0) != 0;
    if (hadUnread) _unread[peerId] = 0;
    if (clearedReceipts || hadUnread) {
      unawaited(_persistMeta(peerId));
      notifyListeners();
    }
  }

  /// Tells [peerId] which of its messages we've now read, so it can show read
  /// receipts. Best-effort: if the peer is unreachable the ids are kept and
  /// retried the next time the conversation is marked read. Returns true if the
  /// pending ids were sent and cleared (so the caller persists the change).
  bool _sendReadReceipt(String peerId) {
    final mids = _unackedReceived[peerId];
    if (mids == null || mids.isEmpty) return false;
    final device = _devices[peerId];
    if (device == null) return false; // offline — keep the ids for next time
    _send(device.host, device.port, FrameType.read, {'mids': List.of(mids)});
    _unackedReceived.remove(peerId);
    return true;
  }

  /// A peer reported reading our messages — upgrade their delivery status to
  /// `read`. A receipt is the strongest confirmation of receipt, so it's
  /// accepted regardless of what we currently believe.
  Future<void> _onRead(IncomingFrame frame) async {
    final mids = (frame.data['mids'] as List?)?.cast<String>();
    if (mids == null || mids.isEmpty) return;
    final list = _conversations[frame.from.id];
    if (list == null) return;
    final readMids = mids.toSet();
    var changed = false;
    for (final m in list) {
      if (m.mine && m.status != MessageStatus.read && readMids.contains(m.id)) {
        m.status = MessageStatus.read;
        await _messages.updateStatus(m.id, MessageStatus.read);
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  // --- Inbound frames ------------------------------------------------------

  Future<void> _handleFrame(IncomingFrame frame) async {
    // Trust before bookkeeping: only a peer we already have an agreement with
    // may refresh its device-table entry from a frame. An unpaired device has
    // to announce itself through discovery (a beacon) to appear on the
    // dashboard — it can't inject or redirect a device entry just by sending a
    // frame (finding #15). The pairing handlers learn the peer's address
    // themselves once the code is verified.
    if (isPaired(frame.from.id)) {
      _upsertDevice(frame.from.host, frame.from);
    }

    switch (frame.type) {
      case FrameType.pairRequest:
        await _onPairRequest(frame.from);
        break;
      case FrameType.pairResponse:
        _onPairResponse(frame);
        break;
      case FrameType.pairConfirm:
        _onPairConfirm(frame);
        break;
      case FrameType.text:
        await _onText(frame);
        break;
      case FrameType.photo:
        await _onPhoto(frame);
        break;
      case FrameType.unpair:
        _onUnpair(frame.from);
        break;
      case FrameType.ack:
        _onAck(frame);
        break;
      case FrameType.read:
        await _onRead(frame);
        break;
    }
  }

  /// A reliable send was confirmed received — resolve its pending completer so
  /// the sender stops retrying. The ack must come from the peer the message was
  /// actually sent to, so a stray or spoofed ack from another device can't mark
  /// it delivered. Unknown acks are harmless no-ops.
  void _onAck(IncomingFrame frame) {
    final mid = frame.data['mid'] as String?;
    if (mid == null) return;
    final pending = _pendingAcks[mid];
    if (pending == null || pending.peerId != frame.from.id) return;
    _pendingAcks.remove(mid);
    pending.completer.complete();
  }

  /// Step 2 (receiver): prompt the user to type the code shown on the
  /// initiator's screen, then echo it back. We do *not* add the peer yet —
  /// that waits for the initiator's `pair_confirm` once it has verified the
  /// code.
  Future<void> _onPairRequest(Endpoint from) async {
    final code = await onPairRequest?.call(from);
    final accepted = code != null && code.trim().isNotEmpty;
    await _send(from.host, from.port, FrameType.pairResponse, {
      'accepted': accepted,
      if (accepted) 'code': code.trim(),
    });
  }

  /// Step 3a (initiator): verify the code the receiver echoed back against the
  /// one we displayed. On a match we pair and confirm; otherwise we reject.
  void _onPairResponse(IncomingFrame frame) {
    final expected = _pendingCodes.remove(frame.from.id);
    final pending = outgoingPairing;
    final isActive = pending != null && pending.peerId == frame.from.id;

    final accepted = (frame.data['accepted'] as bool?) ?? false;
    if (!accepted) {
      if (isActive) pending.status = PairStatus.declined;
      notifyListeners();
      return;
    }

    final code = frame.data['code'] as String?;
    if (pairingCodeMatches(expected, code)) {
      _addPeer(frame.from,
          system: 'You are now connected with ${frame.from.name}.');
      // Verified pairing → trust this endpoint so we can reach them at once.
      _upsertDevice(frame.from.host, frame.from);
      _send(frame.from.host, frame.from.port, FrameType.pairConfirm,
          {'accepted': true});
      if (isActive) pending.status = PairStatus.success;
      _buzz(); // celebrate a successful pairing
    } else {
      _send(frame.from.host, frame.from.port, FrameType.pairConfirm,
          {'accepted': false});
      if (isActive) pending.status = PairStatus.mismatch;
    }
    notifyListeners();
  }

  /// Step 3b (receiver): the initiator verified the code. Commit the agreement
  /// on a positive confirmation; otherwise let the user know it failed.
  void _onPairConfirm(IncomingFrame frame) {
    final accepted = (frame.data['accepted'] as bool?) ?? false;
    if (accepted) {
      _addPeer(frame.from,
          system: 'You are now connected with ${frame.from.name}.');
      // Verified pairing → trust this endpoint so we can reach them at once.
      _upsertDevice(frame.from.host, frame.from);
      onNotice?.call('Paired with ${frame.from.name}.');
      _buzz(); // celebrate a successful pairing
    } else {
      onNotice?.call("Pairing failed — the code didn't match.");
    }
  }

  /// A medium pulse for milestone events (pairing), a light tick for ambient
  /// ones (incoming messages). No-op / harmless on platforms without haptics.
  void _buzz() {
    HapticFeedback.mediumImpact().catchError((_) {});
  }

  void _tick() {
    HapticFeedback.lightImpact().catchError((_) {});
  }

  Future<void> _onText(IncomingFrame frame) async {
    if (!isPaired(frame.from.id)) return; // No agreement → ignore.
    final text = frame.data['text'] as String?;
    if (text == null) return;
    final mid = (frame.data['mid'] as String?) ?? _uuid.v4();
    if (_isDuplicate(frame.from.id, mid)) {
      _ackTo(frame.from, mid); // already stored — re-confirm so sender stops retrying
      return;
    }

    await _appendMessage(
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
    _recordReceived(frame.from.id, mid);
    await _persistMeta(frame.from.id);
    _ackTo(frame.from, mid); // confirm receipt for the reliable sender
    _tick(); // felt a new message arrive
    _notifyReceived('New message from ${frame.from.name}');
  }

  Future<void> _onPhoto(IncomingFrame frame) async {
    if (!isPaired(frame.from.id)) return;
    final data = frame.data['data'] as String?;
    if (data == null) return;
    final mid = (frame.data['mid'] as String?) ?? _uuid.v4();
    if (_isDuplicate(frame.from.id, mid)) {
      // Already stored (a retry whose earlier ack was lost) — re-confirm so the
      // sender stops resending, but don't store or notify twice.
      _ackTo(frame.from, mid);
      return;
    }

    final name = (frame.data['name'] as String?) ?? 'photo';
    List<int> bytes;
    try {
      bytes = base64Decode(data);
    } catch (_) {
      return;
    }
    final path = await _storage.saveIncomingPhoto(name, bytes);

    await _appendMessage(
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
    _recordReceived(frame.from.id, mid);
    await _persistMeta(frame.from.id);
    _ackTo(frame.from, mid); // confirm receipt for reliable senders
    _tick(); // felt a new photo arrive
    _notifyPhotoReceived(frame.from.name);
  }

  /// Notes that [mid] was received from [peerId] but not yet reported as read.
  void _recordReceived(String peerId, String mid) {
    (_unackedReceived[peerId] ??= <String>[]).add(mid);
  }

  /// Persists the per-peer unread count and pending read-receipt ids so they
  /// survive a restart.
  Future<void> _persistMeta(String peerId) => _messages.saveMeta(
        peerId,
        unread: _unread[peerId] ?? 0,
        unacked: _unackedReceived[peerId] ?? const [],
      );

  /// Deletes the on-disk files backing any photo messages in [messages] that
  /// Huddle stored in its own media folder, so removing a message or
  /// conversation doesn't leave orphaned files behind. Files the user
  /// redirected to a custom folder, or already gone, are left alone.
  Future<void> _deleteMediaFor(Iterable<ChatMessage> messages) async {
    for (final m in messages) {
      final path = m.filePath;
      if (m.kind == MessageKind.photo && path != null) {
        await _storage.deleteManagedMedia(path);
      }
    }
  }

  /// Raises a transient in-app notice for received content, when the user has
  /// notifications enabled. Reuses the same channel as pairing notices.
  void _notifyReceived(String message) {
    if (_notifyOnReceive) onNotice?.call(message);
  }

  // Coalesces a burst of received photos (a batch send) into a single notice
  // rather than firing one notification per file.
  int _photoNoticeCount = 0;
  String? _photoNoticeFrom;
  Timer? _photoNoticeTimer;

  void _notifyPhotoReceived(String fromName) {
    if (!_notifyOnReceive) return;
    _photoNoticeCount++;
    _photoNoticeFrom = fromName;
    _photoNoticeTimer?.cancel();
    _photoNoticeTimer = Timer(const Duration(milliseconds: 1200), () {
      final count = _photoNoticeCount;
      final from = _photoNoticeFrom ?? 'a device';
      _photoNoticeCount = 0;
      _photoNoticeFrom = null;
      onNotice?.call(count == 1
          ? 'Saved a photo from $from'
          : 'Saved $count photos from $from');
    });
  }

  void _onUnpair(Endpoint from) {
    if (!isPaired(from.id)) return;
    // Mirror local unpair cleanup so the peer ending the huddle doesn't leave
    // stale history, unread counts, read-receipt tracking, or photo files behind.
    final removed = _conversations.remove(from.id) ?? const <ChatMessage>[];
    _peers.remove(from.id);
    _unread.remove(from.id);
    _unackedReceived.remove(from.id);
    _storage.savePeers(_peers.values.toList());
    unawaited(_messages.deleteConversation(from.id));
    unawaited(_deleteMediaFor(removed));
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
      unawaited(_appendMessage(
        from.id,
        ChatMessage(
          id: _uuid.v4(),
          peerId: from.id,
          mine: false,
          kind: MessageKind.system,
          sentAt: DateTime.now(),
          text: system,
        ),
      ));
    } else {
      notifyListeners();
    }
  }

  Future<void> _appendMessage(String peerId, ChatMessage message,
      {bool bumpUnread = false}) async {
    final list = _conversations.putIfAbsent(peerId, () => []);
    list.add(message);
    if (bumpUnread) {
      _unread[peerId] = (_unread[peerId] ?? 0) + 1;
    }
    notifyListeners();
    await _messages.append(message);
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
    _photoNoticeTimer?.cancel();
    _discovery?.dispose();
    _transport?.dispose();
    // Close only a database we own (the on-disk/fallback store). An injected
    // factory (tests) is left open so a "restart" controller can reopen it.
    if (databaseFactory == null) {
      final db = _db;
      if (db != null) unawaited(db.close());
    }
    super.dispose();
  }
}
