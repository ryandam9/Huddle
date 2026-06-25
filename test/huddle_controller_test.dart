// State and persistence tests for HuddleController. These exercise the public
// API against a real controller backed by mocked SharedPreferences. The
// transport/discovery sockets bind on loopback but are not relied upon here.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:huddle/models/chat_message.dart';
import 'package:huddle/models/peer.dart';
import 'package:huddle/services/protocol.dart';
import 'package:huddle/services/storage_service.dart';
import 'package:huddle/state/huddle_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final controllers = <HuddleController>[];

  Future<HuddleController> start() async {
    final c = HuddleController();
    await c.init();
    controllers.add(c);
    return c;
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));

  tearDown(() {
    for (final c in controllers) {
      c.dispose();
    }
    controllers.clear();
  });

  test('starts ready with a generated identity and no peers', () async {
    final c = await start();
    expect(c.ready, isTrue);
    expect(c.identity.id, isNotEmpty);
    expect(c.peers, isEmpty);
    expect(c.totalUnread, 0);
  });

  test('loads persisted peers and their conversations on init', () async {
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    await storage.savePeers([
      Peer(
          id: 'p1',
          name: 'Laptop',
          platform: 'macos',
          pairedAt: DateTime.fromMillisecondsSinceEpoch(5)),
    ]);
    await storage.saveMessages('p1', [
      ChatMessage(
        id: 'm1',
        peerId: 'p1',
        mine: false,
        kind: MessageKind.text,
        sentAt: DateTime.fromMillisecondsSinceEpoch(10),
        text: 'welcome back',
      ),
    ]);

    final c = await start();
    expect(c.peers.map((p) => p.id), ['p1']);
    expect(c.isPaired('p1'), isTrue);
    expect(c.conversation('p1').single.text, 'welcome back');
  });

  test('sendText to an unpaired id is rejected and stores nothing', () async {
    final c = await start();
    final ok = await c.sendText('stranger', 'hi');
    expect(ok, isFalse);
    expect(c.conversation('stranger'), isEmpty);
  });

  test('sendText to a paired but offline peer queues it locally', () async {
    final prefs = await SharedPreferences.getInstance();
    await StorageService(prefs).savePeers([
      Peer(id: 'p1', name: 'Phone', platform: 'android', pairedAt: DateTime(2026)),
    ]);
    final c = await start();

    final ok = await c.sendText('p1', 'are you there?');
    expect(ok, isTrue); // accepted and stored optimistically
    final convo = c.conversation('p1');
    expect(convo.single.text, 'are you there?');
    expect(convo.single.mine, isTrue);

    // No endpoint yet → it stays queued (sending), to be delivered when the
    // peer reappears (even across a restart).
    expect(convo.single.status, MessageStatus.sending);

    // Persisted for next launch.
    expect(StorageService(prefs).loadMessages('p1').single.text,
        'are you there?');
  });

  test('blank text is ignored', () async {
    final prefs = await SharedPreferences.getInstance();
    await StorageService(prefs).savePeers([
      Peer(id: 'p1', name: 'Phone', platform: 'android', pairedAt: DateTime(2026)),
    ]);
    final c = await start();
    expect(await c.sendText('p1', '   '), isFalse);
    expect(c.conversation('p1'), isEmpty);
  });

  test('unpair removes the peer, its history and persists the change',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    await storage.savePeers([
      Peer(id: 'p1', name: 'Phone', platform: 'android', pairedAt: DateTime(2026)),
    ]);
    await storage.saveMessages('p1', [
      ChatMessage(
          id: 'm',
          peerId: 'p1',
          mine: true,
          kind: MessageKind.text,
          sentAt: DateTime(2026),
          text: 'hi'),
    ]);
    final c = await start();
    expect(c.isPaired('p1'), isTrue);

    await c.unpair('p1');
    expect(c.isPaired('p1'), isFalse);
    expect(c.conversation('p1'), isEmpty);
    expect(storage.loadPeers(), isEmpty);
    expect(storage.loadMessages('p1'), isEmpty);
  });

  test('renameSelf updates and persists the display name', () async {
    final c = await start();
    await c.renameSelf('Workshop Pi');
    expect(c.identity.name, 'Workshop Pi');

    // A fresh controller (same mocked store) reuses the saved name.
    final c2 = await start();
    expect(c2.identity.name, 'Workshop Pi');
  });

  test('ingestBeacon makes a device visible and online', () async {
    final c = await start();
    expect(c.devices, isEmpty);

    c.ingestBeacon(
      '192.168.1.50',
      Endpoint(id: 'd1', name: 'Tablet', platform: 'android', port: 5001),
    );

    expect(c.devices.single.id, 'd1');
    expect(c.deviceFor('d1')!.host, '192.168.1.50');
    expect(c.isOnline('d1'), isTrue);
  });

  group('network settings', () {
    test('defaults to the standard port and automatic broadcast', () async {
      final c = await start();
      expect(c.discoveryPort, kDiscoveryPort);
      expect(c.customBroadcast, isNull);
    });

    test('broadcast targets always include the limited broadcast', () async {
      final c = await start();
      expect(await c.broadcastTargets(), contains('255.255.255.255'));
    });

    test('setting a custom broadcast persists and is broadcast to', () async {
      final c = await start();
      await c.setCustomBroadcast('192.168.5.255');
      expect(c.customBroadcast, '192.168.5.255');
      expect(await c.broadcastTargets(), contains('192.168.5.255'));

      final reloaded = await start();
      expect(reloaded.customBroadcast, '192.168.5.255');
    });

    test('setting the discovery port persists and restarts discovery',
        () async {
      final c = await start();
      await c.setDiscoveryPort(50777);
      expect(c.discoveryPort, 50777);
      // Discovery still works (limited broadcast still computed).
      expect(await c.broadcastTargets(), contains('255.255.255.255'));

      final reloaded = await start();
      expect(reloaded.discoveryPort, 50777);
    });

    test('refreshDiscovery does not throw', () async {
      final c = await start();
      expect(c.refreshDiscovery, returnsNormally);
    });
  });

  group('download settings', () {
    test('notify-on-receive defaults on and persists when toggled', () async {
      final c = await start();
      expect(c.notifyOnReceive, isTrue);

      await c.setNotifyOnReceive(false);
      expect(c.notifyOnReceive, isFalse);

      final reloaded = await start();
      expect(reloaded.notifyOnReceive, isFalse);
    });

    test('a writable custom folder is accepted, applied and persisted',
        () async {
      final dir = Directory.systemTemp.createTempSync('huddle_ctrl_');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      final c = await start();
      final ok = await c.setDownloadDirectory(dir.path);
      expect(ok, isTrue);
      expect(c.isCustomDownloadDir, isTrue);
      expect(c.downloadLocation, dir.path);

      // A fresh controller over the same store keeps the chosen folder.
      final reloaded = await start();
      expect(reloaded.isCustomDownloadDir, isTrue);
      expect(reloaded.downloadLocation, dir.path);
    });

    test('an unusable folder is rejected and leaves settings unchanged',
        () async {
      final c = await start();
      // A path under a file (not a directory) can't be created.
      final probe = File(
          '${Directory.systemTemp.path}/huddle_not_a_dir_${DateTime.now().microsecondsSinceEpoch}');
      await probe.writeAsString('x');
      addTearDown(() {
        if (probe.existsSync()) probe.deleteSync();
      });

      final ok = await c.setDownloadDirectory('${probe.path}/sub');
      expect(ok, isFalse);
      expect(c.isCustomDownloadDir, isFalse);
    });
  });
}
