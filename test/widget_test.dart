// Tests for Huddle. These cover pure helpers and the wire-protocol
// (de)serialisation, which can run without platform plugins or a network.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:huddle/models/chat_message.dart';
import 'package:huddle/models/peer.dart';
import 'package:huddle/services/protocol.dart';
import 'package:huddle/ui_helpers.dart';

void main() {
  group('ui helpers', () {
    test('formatTime zero-pads hours and minutes', () {
      final t = DateTime(2024, 1, 1, 9, 5);
      expect(formatTime(t), '09:05');
    });

    test('formatRelative reports recent times as "just now"', () {
      expect(formatRelative(DateTime.now()), 'just now');
    });

    test('platformIcon maps known platforms', () {
      expect(platformIcon('android'), Icons.android);
      expect(platformIcon('macos'), Icons.apple);
      expect(platformIcon('something-else'), Icons.devices_other);
    });

    test('colorForId is deterministic', () {
      expect(colorForId('abc'), colorForId('abc'));
    });
  });

  group('protocol', () {
    test('Endpoint round-trips through json and keeps host on the receiver',
        () {
      final endpoint = Endpoint(
        id: 'id-1',
        name: 'Phone',
        platform: 'android',
        port: 5000,
      );
      final decoded = Endpoint.fromJson(endpoint.toJson()).withHost('10.0.0.5');
      expect(decoded.id, 'id-1');
      expect(decoded.name, 'Phone');
      expect(decoded.port, 5000);
      expect(decoded.host, '10.0.0.5');
    });
  });

  group('models', () {
    test('Peer round-trips through json', () {
      final peer = Peer(
        id: 'p1',
        name: 'Laptop',
        platform: 'macos',
        pairedAt: DateTime.fromMillisecondsSinceEpoch(1000),
      );
      final decoded = Peer.fromJson(peer.toJson());
      expect(decoded.id, 'p1');
      expect(decoded.name, 'Laptop');
      expect(decoded.pairedAt.millisecondsSinceEpoch, 1000);
    });

    test('ChatMessage round-trips through json', () {
      final msg = ChatMessage(
        id: 'm1',
        peerId: 'p1',
        mine: true,
        kind: MessageKind.photo,
        sentAt: DateTime.fromMillisecondsSinceEpoch(2000),
        fileName: 'cat.jpg',
        filePath: '/tmp/cat.jpg',
      );
      final decoded = ChatMessage.fromJson(msg.toJson());
      expect(decoded.kind, MessageKind.photo);
      expect(decoded.mine, true);
      expect(decoded.fileName, 'cat.jpg');
    });
  });
}
