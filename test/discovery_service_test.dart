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

  test('a custom broadcast address is trimmed of surrounding whitespace',
      () async {
    final d = DiscoveryService(
        identity: id(), tcpPort: 1234, customBroadcast: '  10.1.2.255  ');
    final targets = (await d.broadcastTargets()).map((a) => a.address).toList();
    expect(targets, contains('10.1.2.255'));
  });

  test('a blank custom broadcast address adds nothing', () async {
    final d = DiscoveryService(
        identity: id(), tcpPort: 1234, customBroadcast: '   ');
    final targets = (await d.broadcastTargets()).map((a) => a.address).toList();
    expect(targets, contains('255.255.255.255'));
    expect(targets, isNot(contains('')));
  });

  test('the limited broadcast is not duplicated when set as the custom one',
      () async {
    final d = DiscoveryService(
        identity: id(), tcpPort: 1234, customBroadcast: '255.255.255.255');
    final targets = (await d.broadcastTargets()).map((a) => a.address).toList();
    expect(
        targets.where((a) => a == '255.255.255.255').length, 1); // deduplicated
  });

  test('the custom broadcast can be changed after construction', () async {
    final d = DiscoveryService(identity: id(), tcpPort: 1234);
    expect((await d.broadcastTargets()).map((a) => a.address),
        isNot(contains('10.9.9.255')));

    d.customBroadcast = '10.9.9.255';
    expect((await d.broadcastTargets()).map((a) => a.address),
        contains('10.9.9.255'));
  });
}
