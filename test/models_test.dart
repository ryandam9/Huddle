// Tests for the data models: Device, Peer and ChatMessage.

import 'package:flutter_test/flutter_test.dart';

import 'package:huddle/models/chat_message.dart';
import 'package:huddle/models/device.dart';
import 'package:huddle/models/peer.dart';

void main() {
  group('Device', () {
    Device make(DateTime lastSeen) => Device(
          id: 'd1',
          name: 'Phone',
          host: '10.0.0.2',
          port: 5000,
          platform: 'android',
          lastSeen: lastSeen,
        );

    test('is online when seen within the online window', () {
      expect(make(DateTime.now()).isOnline, isTrue);
    });

    test('is offline once the online window has elapsed', () {
      final stale = DateTime.now()
          .subtract(Device.onlineWindow + const Duration(seconds: 5));
      expect(make(stale).isOnline, isFalse);
    });

    test('copyWith overrides only the given fields', () {
      final original = make(DateTime(2024));
      final updated = original.copyWith(name: 'Renamed', host: '10.0.0.3');
      expect(updated.id, 'd1'); // preserved
      expect(updated.name, 'Renamed');
      expect(updated.host, '10.0.0.3');
      expect(updated.port, 5000); // preserved
    });

    test('copyWith with no arguments preserves every field', () {
      final original = make(DateTime(2024, 5, 6, 7, 8));
      final clone = original.copyWith();
      expect(clone.id, original.id);
      expect(clone.name, original.name);
      expect(clone.host, original.host);
      expect(clone.port, original.port);
      expect(clone.platform, original.platform);
      expect(clone.lastSeen, original.lastSeen);
    });

    test('online status tracks the window boundary', () {
      final justInside = make(DateTime.now()
          .subtract(Device.onlineWindow - const Duration(seconds: 1)));
      expect(justInside.isOnline, isTrue);

      final justOutside = make(DateTime.now()
          .subtract(Device.onlineWindow + const Duration(seconds: 1)));
      expect(justOutside.isOnline, isFalse);
    });
  });

  group('Peer', () {
    test('round-trips through json', () {
      final peer = Peer(
        id: 'p1',
        name: 'Laptop',
        platform: 'macos',
        pairedAt: DateTime.fromMillisecondsSinceEpoch(1000),
      );
      final decoded = Peer.fromJson(peer.toJson());
      expect(decoded.id, 'p1');
      expect(decoded.name, 'Laptop');
      expect(decoded.platform, 'macos');
      expect(decoded.pairedAt.millisecondsSinceEpoch, 1000);
    });

    test('applies defaults for missing fields', () {
      final decoded = Peer.fromJson({'id': 'p2'});
      expect(decoded.id, 'p2');
      expect(decoded.name, 'Unknown');
      expect(decoded.platform, 'unknown');
      expect(decoded.pairedAt.millisecondsSinceEpoch, 0);
    });
  });

  group('ChatMessage', () {
    test('round-trips a text message', () {
      final msg = ChatMessage(
        id: 'm1',
        peerId: 'p1',
        mine: true,
        kind: MessageKind.text,
        sentAt: DateTime.fromMillisecondsSinceEpoch(2000),
        text: 'hello',
      );
      final decoded = ChatMessage.fromJson(msg.toJson());
      expect(decoded.kind, MessageKind.text);
      expect(decoded.mine, isTrue);
      expect(decoded.text, 'hello');
      expect(decoded.sentAt.millisecondsSinceEpoch, 2000);
    });

    test('round-trips a photo message', () {
      final msg = ChatMessage(
        id: 'm2',
        peerId: 'p1',
        mine: false,
        kind: MessageKind.photo,
        sentAt: DateTime.fromMillisecondsSinceEpoch(3000),
        fileName: 'cat.jpg',
        filePath: '/tmp/cat.jpg',
      );
      final decoded = ChatMessage.fromJson(msg.toJson());
      expect(decoded.kind, MessageKind.photo);
      expect(decoded.mine, isFalse);
      expect(decoded.fileName, 'cat.jpg');
      expect(decoded.filePath, '/tmp/cat.jpg');
    });

    test('falls back to text for an unknown kind', () {
      final decoded = ChatMessage.fromJson({
        'id': 'm3',
        'peerId': 'p1',
        'kind': 'totally-unknown',
        'sentAt': 0,
      });
      expect(decoded.kind, MessageKind.text);
    });

    test('round-trips a system message and keeps media fields null', () {
      final msg = ChatMessage(
        id: 'm4',
        peerId: 'p1',
        mine: false,
        kind: MessageKind.system,
        sentAt: DateTime.fromMillisecondsSinceEpoch(4000),
        text: 'You are now connected.',
      );
      final decoded = ChatMessage.fromJson(msg.toJson());
      expect(decoded.kind, MessageKind.system);
      expect(decoded.text, 'You are now connected.');
      expect(decoded.filePath, isNull);
      expect(decoded.fileName, isNull);
    });

    test('defaults mine to false when the field is absent', () {
      final decoded = ChatMessage.fromJson({
        'id': 'm5',
        'peerId': 'p1',
        'kind': 'text',
        'sentAt': 0,
      });
      expect(decoded.mine, isFalse);
    });
  });
}
