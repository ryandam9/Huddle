/// The kind of payload a [ChatMessage] carries.
enum MessageKind { text, photo, system }

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
      };
}
