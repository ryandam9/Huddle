// Tests for the TCP transport using real loopback sockets. flutter test runs
// on the Dart VM where dart:io sockets work, so we can verify framing and the
// sender-identity round-trip end to end.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:huddle/services/protocol.dart';
import 'package:huddle/services/transport_service.dart';

void main() {
  late TransportService receiver;
  late TransportService sender;

  setUp(() async {
    receiver =
        TransportService(id: 'recv', name: 'Receiver', platform: 'linux');
    sender = TransportService(id: 'send', name: 'Sender', platform: 'macos');
    await receiver.start();
    await sender.start();
  });

  tearDown(() async {
    await receiver.dispose();
    await sender.dispose();
  });

  test('binds to a real, non-zero port', () {
    expect(receiver.port, greaterThan(0));
  });

  test('delivers a frame with decoded type, payload and sender identity',
      () async {
    final received = Completer<IncomingFrame>();
    receiver.onFrame = (frame) {
      if (!received.isCompleted) received.complete(frame);
    };

    final ok = await sender.send('127.0.0.1', receiver.port, FrameType.text, {
      'mid': 'm-1',
      'text': 'hello huddle',
    });
    expect(ok, isTrue);

    final frame = await received.future.timeout(const Duration(seconds: 5));
    expect(frame.type, FrameType.text);
    expect(frame.data['text'], 'hello huddle');
    // Sender identity is stamped into `from` by the transport itself.
    expect(frame.from.id, 'send');
    expect(frame.from.name, 'Sender');
    expect(frame.from.port, sender.port);
    // Host is resolved from the socket's remote (loopback) address.
    expect(frame.from.host, anyOf('127.0.0.1', '::1'));
  });

  test('updating name is reflected in subsequent frames', () async {
    final received = Completer<IncomingFrame>();
    receiver.onFrame = (frame) {
      if (!received.isCompleted) received.complete(frame);
    };

    sender.name = 'Renamed';
    await sender.send('127.0.0.1', receiver.port, FrameType.text, {'text': 'x'});

    final frame = await received.future.timeout(const Duration(seconds: 5));
    expect(frame.from.name, 'Renamed');
  });

  test('send returns false for an unreachable port', () async {
    // Port 1 is privileged/closed in test sandboxes → connection fails fast.
    final ok = await sender.send('127.0.0.1', 1, FrameType.text, {'text': 'x'});
    expect(ok, isFalse);
  });

  test('send returns false for an invalid (zero) port', () async {
    final ok = await sender.send('127.0.0.1', 0, FrameType.text, {'text': 'x'});
    expect(ok, isFalse);
  });
}
