// Tests for the discovery broadcast target computation (no sockets needed).

import 'package:flutter_test/flutter_test.dart';

import 'package:huddle/services/discovery_service.dart';
import 'package:huddle/services/identity.dart';

void main() {
  Identity id() => Identity(id: 'x', name: 'n', platform: 'linux');

  test('targets always include the limited broadcast', () async {
    final d = DiscoveryService(identity: id(), tcpPort: 1234);
    final targets = (await d.broadcastTargets()).map((a) => a.address).toList();
    expect(targets, contains('255.255.255.255'));
  });

  test('a valid custom broadcast address is included', () async {
    final d = DiscoveryService(
        identity: id(), tcpPort: 1234, customBroadcast: '10.1.2.255');
    final targets = (await d.broadcastTargets()).map((a) => a.address).toList();
    expect(targets, contains('10.1.2.255'));
  });

  test('an invalid custom broadcast address is ignored', () async {
    final d = DiscoveryService(
        identity: id(), tcpPort: 1234, customBroadcast: 'not-an-ip');
    final targets = (await d.broadcastTargets()).map((a) => a.address).toList();
    expect(targets, contains('255.255.255.255'));
    expect(targets, isNot(contains('not-an-ip')));
  });
}
