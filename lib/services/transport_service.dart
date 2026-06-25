import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'protocol.dart';

/// Reliable point-to-point messaging between devices over TCP.
///
/// A [ServerSocket] listens on an OS-assigned port (exposed as [port] and
/// advertised through discovery). Each accepted connection may carry one or
/// more newline-delimited JSON frames which are decoded and handed to
/// [onFrame]. Sending is connectionless from the caller's point of view:
/// [send] opens a short-lived connection, writes a single frame and closes.
class TransportService {
  TransportService({
    required this.id,
    required this.name,
    required this.platform,
  });

  /// This device's identity, stamped into every outbound frame's `from` field
  /// so the receiver knows who we are and how to reply. [name] is mutable so
  /// the advertised display name can change when the user renames the device.
  final String id;
  final String platform;
  String name;

  /// Invoked for every decoded inbound frame.
  void Function(IncomingFrame frame)? onFrame;

  /// Hard ceiling on a single unterminated inbound frame. Bounds the receive
  /// buffer so a peer can't exhaust memory by streaming without a newline; it
  /// also caps the (whole-file) photo frame until a chunked transfer replaces
  /// it. Mutable for tests.
  int maxFrameBytes = 64 * 1024 * 1024;

  ServerSocket? _server;

  int get port => _server?.port ?? 0;

  Future<void> start() async {
    final server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    _server = server;
    server.listen(_handleConnection, onError: (_) {});
  }

  Endpoint get _localEndpoint =>
      Endpoint(id: id, name: name, platform: platform, port: port);

  void _handleConnection(Socket socket) {
    final remoteHost = socket.remoteAddress.address;
    final buffer = StringBuffer();

    socket.cast<List<int>>().transform(utf8.decoder).listen(
      (chunk) {
        buffer.write(chunk);
        _drainLines(buffer, remoteHost);
        // After draining complete frames, an oversized leftover means a single
        // frame is too large (or an endless stream) — drop the connection.
        if (buffer.length > maxFrameBytes) socket.destroy();
      },
      onError: (_) => socket.destroy(),
      onDone: () {
        _drainLines(buffer, remoteHost, flush: true);
        socket.destroy();
      },
      cancelOnError: true,
    );
  }

  /// Extracts complete newline-delimited frames from [buffer] and dispatches
  /// them. When [flush] is true the trailing (un-terminated) content is also
  /// parsed — handy for senders that close without a trailing newline.
  void _drainLines(StringBuffer buffer, String remoteHost,
      {bool flush = false}) {
    final content = buffer.toString();
    final parts = content.split('\n');

    // The last element is either an incomplete line (keep it) or empty.
    final complete = flush ? parts : parts.sublist(0, parts.length - 1);
    final leftover = flush ? '' : parts.last;

    buffer
      ..clear()
      ..write(leftover);

    for (final line in complete) {
      if (line.trim().isEmpty) continue;
      _dispatch(line, remoteHost);
    }
  }

  void _dispatch(String line, String remoteHost) {
    Map<String, dynamic> json;
    try {
      json = jsonDecode(line) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    if (json['app'] != kAppTag) return;

    final type = json['type'] as String?;
    final fromJson = json['from'];
    if (type == null || fromJson is! Map<String, dynamic>) return;

    final endpoint = Endpoint.tryFromJson(fromJson);
    if (endpoint == null) return; // malformed sender — ignore, keep the socket
    final from = endpoint.withHost(remoteHost);
    onFrame?.call(IncomingFrame(type: type, from: from, data: json));
  }

  /// Sends a single [data] frame of [type] to [host]:[port].
  ///
  /// Returns true on success. Failures (peer offline, refused, timeout) are
  /// reported as false rather than thrown so callers can surface them in UI.
  Future<bool> send(
    String host,
    int port,
    String type,
    Map<String, dynamic> data,
  ) async {
    if (port <= 0) return false;
    Socket? socket;
    try {
      socket = await Socket.connect(host, port,
          timeout: const Duration(seconds: 6));
      final frame = <String, dynamic>{
        'app': kAppTag,
        'v': kProtocolVersion,
        'type': type,
        'from': _localEndpoint.toJson(),
        ...data,
      };
      socket.add(utf8.encode('${jsonEncode(frame)}\n'));
      await socket.flush();
      // Give the OS a moment to push bytes before we tear the socket down.
      await socket.close();
      return true;
    } catch (_) {
      socket?.destroy();
      return false;
    }
  }

  Future<void> dispose() async {
    await _server?.close();
    _server = null;
  }
}
