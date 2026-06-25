/// The kind of payload a [ChatMessage] carries.
enum MessageKind { text, photo, system }

/// Delivery state of an outgoing message. Incoming and historical messages are
/// always [delivered]; only our own freshly-sent ones pass through [sending]
/// on the way to [delivered] (acknowledged by the peer) and then [read] (the
/// peer opened the conversation), or [failed] if it couldn't be delivered.
enum MessageStatus { sending, delivered, read, failed }

/// A single entry in a conversation with a peer.
///
/// Messages are stored locally (per peer) so history survives restarts.
/// For photos, [filePath] points at the on-disk copy and [fileName] is the
/// original name used for display.
class ChatMessage {
  ChatMessage({
    required this.id,
    required this.peerId,
    required this.mine,
    required this.kind,
    required this.sentAt,
    this.text,
    this.filePath,
    this.fileName,
    this.status = MessageStatus.delivered,
  });

  /// Unique id of the message (also used to de-duplicate on the wire).
  final String id;

  /// The conversation partner this message belongs to.
  final String peerId;

  /// True when this device sent the message; false when received.
  final bool mine;

  final MessageKind kind;
  final DateTime sentAt;

  final String? text;
  final String? filePath;
  final String? fileName;

  /// Delivery state, mutable because it advances after the message is created
  /// (sending → delivered/failed) as acknowledgements arrive.
  MessageStatus status;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      peerId: json['peerId'] as String,
      mine: (json['mine'] as bool?) ?? false,
      kind: MessageKind.values.firstWhere(
        (k) => k.name == json['kind'],
        orElse: () => MessageKind.text,
      ),
      sentAt: DateTime.fromMillisecondsSinceEpoch(
        (json['sentAt'] as int?) ?? 0,
      ),
      text: json['text'] as String?,
      filePath: json['filePath'] as String?,
      fileName: json['fileName'] as String?,
      // Older records (and received messages) have no status → treat as
      // delivered so history never shows a stuck "sending" clock.
      status: MessageStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => MessageStatus.delivered,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'peerId': peerId,
        'mine': mine,
        'kind': kind.name,
        'sentAt': sentAt.millisecondsSinceEpoch,
        'text': text,
        'filePath': filePath,
        'fileName': fileName,
        'status': status.name,
      };
}
