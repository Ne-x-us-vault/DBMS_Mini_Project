/// A shared expense group. `id` is the Firestore document id (the "group code").
class GroupInfo {
  const GroupInfo({
    required this.id,
    required this.name,
    required this.members,
  });

  final String id;
  final String name;
  final List<String> members;
}

/// One entry in the group-wide activity log.
class Activity {
  const Activity({
    required this.by,
    required this.verb,
    required this.title,
    this.amountPaise,
    required this.at,
  });

  final String by;
  final String verb;
  final String title;
  final int? amountPaise;
  final DateTime at;
}

/// One chat message. `senderName` is the "Managing as" name of the sender.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderName,
    required this.text,
    required this.createdAt,
  });

  final String id;
  final String senderName;
  final String text;
  final DateTime createdAt;
}