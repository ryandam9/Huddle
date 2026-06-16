// Tests for the wire-protocol Endpoint (de)serialisation.

import 'package:flutter_test/flutter_test.dart';

import 'package:huddle/services/protocol.dart';

void main() {
  group('Endpoint', () {
    test('round-trips through json', () {
      final endpoint = Endpoint(
        id: 'id-1',
        name: 'Phone',
        platform: 'android',
        port: 5000,
      );
      final decoded = Endpoint.fromJson(endpoint.toJson());
      expect(decoded.id, 'id-1');
      expect(decoded.name, 'Phone');
      expect(decoded.platform, 'android');
      expect(decoded.port, 5000);
    });

    test('toJson does not leak the host field', () {
      final json = Endpoint(
        id: 'x',
        name: 'n',
        platform: 'linux',
        port: 1,
        host: '10.0.0.9',
      ).toJson();
      // Host is resolved by the receiver from the socket, never trusted from
      // the wire, so it must not be serialised.
      expect(json.containsKey('host'), isFalse);
    });

    test('withHost attaches the resolved sender address', () {
      final decoded = Endpoint.fromJson({
        'id': 'id-2',
        'name': 'Laptop',
        'platform': 'macos',
        'port': 6000,
      }).withHost('192.168.1.20');
      expect(decoded.host, '192.168.1.20');
      expect(decoded.port, 6000);
    });

    test('tolerates missing optional fields with defaults', () {
      final decoded = Endpoint.fromJson({'id': 'only-id'});
      expect(decoded.id, 'only-id');
      expect(decoded.name, 'Unknown');
      expect(decoded.platform, 'unknown');
      expect(decoded.port, 0);
    });
  });
}
