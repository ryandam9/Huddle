// Robustness tests for the TCP transport's frame decoder, driven with raw
// loopback sockets so we control the exact bytes on the wire: multiple frames
// per connection, frames split across packets, a frame with no trailing
// newline, and assorted junk that must be skipped without taking down the
// connection.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:huddle/services/protocol.dart';
import 'package:huddle/services/transport_service.dart';

void main() {
  late TransportService receiver;
  final received = <IncomingFrame>[];

  setUp(() async {
    received.clear();
    receiver = TransportService(id: 'recv', name: 'Receiver', platform: 'linux');
    receiver.onFrame = received.add;
    await receiver.start();
  });

  tearDown(() async => receiver.dispose());

  /// Builds one wire line the way a peer's transport would.
  String line(String type, Map<String, dynamic> extra) => jsonEncode({
        'app': kAppTag,
        'v': kProtocolVersion,
        'type': type,
        'from': {
          'id': 'peer',
          'name': 'Peer',
          'platform': 'android',
          'port': 6000,
        },
        ...extra,
      });

  /// Opens a connection, writes [bytes] and closes it.
  Future<void> writeRaw(List<int> bytes) async {
    final sock = await Socket.connect('127.0.0.1', receiver.port);
    sock.add(bytes);
    await sock.flush();
    await sock.close();
  }

  test('two newline-delimited frames in one connection are both delivered',
      () async {
    await writeRaw(utf8.encode(
        '${line(FrameType.text, {'text': 'one'})}\n${line(FrameType.text, {'text': 'two'})}\n'));

    await _waitFor(() => received.length >= 2);
    expect(received.map((f) => f.data['text']), containsAll(['one', 'two']));
  });

  test('a frame split across two packets is reassembled', () async {
    final full = '${line(FrameType.text, {'text': 'split'})}\n';
    final cut = full.length ~/ 2;

    final sock = await Socket.connect('127.0.0.1', receiver.port);
    sock.add(utf8.encode(full.substring(0, cut)));
    await sock.flush();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    sock.add(utf8.encode(full.substring(cut)));
    await sock.flush();
    await sock.close();

    await _waitFor(() => received.isNotEmpty);
    expect(received.single.data['text'], 'split');
  });

  test('a frame with no trailing newline is delivered when the socket closes',
      () async {
    await writeRaw(utf8.encode(line(FrameType.text, {'text': 'no-newline'})));

    await _waitFor(() => received.isNotEmpty);
    expect(received.single.data['text'], 'no-newline');
  });

  test('a malformed line is skipped and a following frame still parses',
      () async {
    await writeRaw(utf8.encode(
        'this is not json\n${line(FrameType.text, {'text': 'good'})}\n'));

    await _waitFor(() => received.isNotEmpty);
    expect(received.single.data['text'], 'good');
  });

  test('a frame with the wrong app tag is ignored', () async {
    final bad = jsonEncode({
      'app': 'not-huddle',
      'type': FrameType.text,
      'from': {'id': 'x', 'port': 1},
      'text': 'nope',
    });
    await writeRaw(utf8.encode('$bad\n${line(FrameType.text, {'text': 'yes'})}\n'));

    await _waitFor(() => received.isNotEmpty);
    expect(received.single.data['text'], 'yes');
  });

  test('frames missing the type or the sender are ignored', () async {
    final noType = jsonEncode({
      'app': kAppTag,
      'from': {'id': 'x', 'port': 1},
    });
    final noFrom = jsonEncode({'app': kAppTag, 'type': FrameType.text});
    await writeRaw(utf8.encode(
        '$noType\n$noFrom\n${line(FrameType.text, {'text': 'ok'})}\n'));

    await _waitFor(() => received.isNotEmpty);
    expect(received.single.type, FrameType.text);
    expect(received.single.data['text'], 'ok');
  });

  test('blank lines between frames are ignored', () async {
    await writeRaw(
        utf8.encode('\n\n${line(FrameType.text, {'text': 'hi'})}\n\n'));

    await _waitFor(() => received.isNotEmpty);
    expect(received.single.data['text'], 'hi');
  });
}

Future<void> _waitFor(bool Function() cond,
    {Duration timeout = const Duration(seconds: 5)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('Timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
