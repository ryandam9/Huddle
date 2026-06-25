// Widget tests for ChatView's build-time behaviour: mark-read fires when the
// conversation is opened and when new messages arrive — but not on unrelated
// rebuilds (finding #19) — and photo bubbles decode at a bounded thumbnail size
// with an async placeholder instead of a synchronous file check (finding #20).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:huddle/models/chat_message.dart';
import 'package:huddle/models/peer.dart';
import 'package:huddle/services/identity.dart';
import 'package:huddle/screens/chat_screen.dart';
import 'package:huddle/state/huddle_controller.dart';

/// A controller stub that serves a fixed (mutable) conversation and counts
/// mark-read calls, with no networking or storage.
class _FakeChatController extends HuddleController {
  _FakeChatController(this.messages) {
    identity = Identity(id: 'me', name: 'Me', platform: 'android');
    ready = true;
  }

  final List<ChatMessage> messages;
  int markReadCalls = 0;

  /// Forces an unrelated rebuild (as device pruning / transfer progress would).
  void bump() => notifyListeners();

  @override
  Future<void> init() async {}
  @override
  List<ChatMessage> conversation(String id) => List.unmodifiable(messages);
  @override
  int unreadFor(String id) => 0;
  @override
  bool isOnline(String id) => false;
  @override
  TransferProgress? get transfer => null;
  @override
  void markRead(String id) => markReadCalls++;
  @override
  Future<bool> sendText(String id, String text) async => true;
  @override
  bool retryMessage(String peerId, String mid) => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final peer =
      Peer(id: 'p1', name: 'Phone', platform: 'android', pairedAt: DateTime(2026));

  ChatMessage text(String body) => ChatMessage(
        id: body,
        peerId: 'p1',
        mine: false,
        kind: MessageKind.text,
        sentAt: DateTime(2026),
        text: body,
      );

  ChatMessage photo(String? path) => ChatMessage(
        id: 'ph',
        peerId: 'p1',
        mine: false,
        kind: MessageKind.photo,
        sentAt: DateTime(2026),
        filePath: path,
        fileName: 'p.png',
      );

  Future<void> pump(WidgetTester tester, HuddleController c) {
    return tester.pumpWidget(
      ChangeNotifierProvider<HuddleController>.value(
        value: c,
        child: MaterialApp(home: Scaffold(body: ChatView(peer: peer))),
      ),
    );
  }

  testWidgets('marks read on open and on new messages, not on idle rebuilds',
      (tester) async {
    final c = _FakeChatController([text('hi')]);
    addTearDown(c.dispose);

    await pump(tester, c);
    await tester.pumpAndSettle();
    expect(c.markReadCalls, 1); // marked read when the conversation opened

    c.bump(); // an unrelated rebuild — no new messages
    await tester.pumpAndSettle();
    expect(c.markReadCalls, 1); // …so it is NOT re-marked

    c.messages.add(text('and again')); // a message arrives
    c.bump();
    await tester.pumpAndSettle();
    expect(c.markReadCalls, 2); // …now it marks read again
  });

  testWidgets('a photo bubble decodes at a bounded thumbnail size',
      (tester) async {
    final dir = Directory.systemTemp.createTempSync('huddle_chat_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/p.png')..writeAsBytesSync(_tinyPng);

    final c = _FakeChatController([photo(file.path)]);
    addTearDown(c.dispose);

    await pump(tester, c);
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<ResizeImage>());
    final resize = image.image as ResizeImage;
    expect(resize.width, 640);
    expect(resize.height, 520);
  });

  testWidgets('a photo with no file shows the placeholder (no Image widget)',
      (tester) async {
    final c = _FakeChatController([photo(null)]);
    addTearDown(c.dispose);

    await pump(tester, c);
    await tester.pump();

    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(find.byType(Image), findsNothing); // no synchronous file probe
  });
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
