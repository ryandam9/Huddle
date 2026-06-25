// End-to-end tests driving two real HuddleControllers that talk over loopback
// TCP: the full code-verified pairing handshake plus message/photo exchange and
// unpairing. Discovery is injected (ingestBeacon) so the tests don't depend on
// UDP broadcast delivery.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart' as sembast;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:huddle/models/chat_message.dart';
import 'package:huddle/services/protocol.dart';
import 'package:huddle/state/huddle_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final controllers = <HuddleController>[];

  setUp(() async {
    // path_provider has no plugin in flutter test; point received-photo storage
    // at a temp directory so saveIncomingPhoto works.
    final docs = await Directory.systemTemp.createTemp('huddle_docs');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => docs.path,
    );
  });

  Future<HuddleController> startWith(String id, String name) async {
    // Distinct identities require distinct persisted ids; the mocked prefs
    // store is reset between each controller so they don't share an identity.
    SharedPreferences.setMockInitialValues({
      'huddle.identity.id': id,
      'huddle.identity.name': name,
      'huddle.identity.platform': 'linux',
    });
    final c = HuddleController(databaseFactory: sembast.newDatabaseFactoryMemory());
    await c.init();
    controllers.add(c);
    return c;
  }

  tearDown(() {
    for (final c in controllers) {
      c.dispose();
    }
    controllers.clear();
  });

  /// A and B both ready; A is told where B lives (as discovery would).
  Future<(HuddleController, HuddleController)> twoPeers() async {
    final a = await startWith('AAAA', 'Device A');
    final b = await startWith('BBBB', 'Device B');
    a.ingestBeacon(
      '127.0.0.1',
      Endpoint(
          id: b.identity.id,
          name: b.identity.name,
          platform: b.identity.platform,
          port: b.tcpPort),
    );
    return (a, b);
  }

  Future<void> pair(HuddleController a, HuddleController b) async {
    // B's user "reads" the code shown on A's screen.
    b.onPairRequest = (_) async => a.outgoingPairing?.code;
    a.startPairing(a.deviceFor(b.identity.id)!);
    await _waitFor(
        () => a.isPaired(b.identity.id) && b.isPaired(a.identity.id));
  }

  test('matching code pairs both devices and posts a system message',
      () async {
    final (a, b) = await twoPeers();
    await pair(a, b);

    expect(a.isPaired(b.identity.id), isTrue);
    expect(b.isPaired(a.identity.id), isTrue);
    expect(a.outgoingPairing!.status, PairStatus.success);
    expect(
      a.conversation(b.identity.id).any((m) => m.kind == MessageKind.system),
      isTrue,
    );
    expect(
      b.conversation(a.identity.id).any((m) => m.kind == MessageKind.system),
      isTrue,
    );
  });

  test('declining the request leaves both unpaired', () async {
    final (a, b) = await twoPeers();
    b.onPairRequest = (_) async => null; // declined
    a.startPairing(a.deviceFor(b.identity.id)!);

    await _waitFor(() => a.outgoingPairing!.status == PairStatus.declined);
    expect(a.isPaired(b.identity.id), isFalse);
    expect(b.isPaired(a.identity.id), isFalse);
  });

  test('a wrong code is rejected and pairs nobody', () async {
    final (a, b) = await twoPeers();
    // 7 chars can never equal the 6-digit code → guaranteed mismatch.
    b.onPairRequest = (_) async => '${a.outgoingPairing!.code}0';
    a.startPairing(a.deviceFor(b.identity.id)!);

    await _waitFor(() => a.outgoingPairing!.status == PairStatus.mismatch);
    expect(a.isPaired(b.identity.id), isFalse);
    expect(b.isPaired(a.identity.id), isFalse);
  });

  test('paired peers exchange text and unread is tracked', () async {
    final (a, b) = await twoPeers();
    await pair(a, b);

    final ok = await a.sendText(b.identity.id, 'hello there');
    expect(ok, isTrue);

    await _waitFor(() => b
        .conversation(a.identity.id)
        .any((m) => m.text == 'hello there' && !m.mine));
    expect(b.unreadFor(a.identity.id), greaterThanOrEqualTo(1));

    b.markRead(a.identity.id);
    expect(b.unreadFor(a.identity.id), 0);

    // The sender keeps its own copy too.
    expect(
      a.conversation(b.identity.id).any((m) => m.text == 'hello there' && m.mine),
      isTrue,
    );
  });

  test('paired peers exchange a photo that is saved on the receiver',
      () async {
    final (a, b) = await twoPeers();
    await pair(a, b);

    final src = File(
        '${Directory.systemTemp.path}/huddle_e2e_${DateTime.now().microsecondsSinceEpoch}.png');
    await src.writeAsBytes(_tinyPng);

    final ok = await a.sendPhoto(b.identity.id, src.path);
    expect(ok, isTrue);

    await _waitFor(() => b
        .conversation(a.identity.id)
        .any((m) => m.kind == MessageKind.photo && !m.mine));

    final received = b
        .conversation(a.identity.id)
        .firstWhere((m) => m.kind == MessageKind.photo && !m.mine);
    expect(received.filePath, isNotNull);
    expect(File(received.filePath!).existsSync(), isTrue);
  });

  test('unpairing notifies the other device', () async {
    final (a, b) = await twoPeers();
    await pair(a, b);

    await a.unpair(b.identity.id);
    expect(a.isPaired(b.identity.id), isFalse);
    await _waitFor(() => !b.isPaired(a.identity.id));
  });
}

Future<void> _waitFor(bool Function() cond,
    {Duration timeout = const Duration(seconds: 8)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('Timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

/// A minimal valid 1x1 PNG.
final List<int> _tinyPng = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];
