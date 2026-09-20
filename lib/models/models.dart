class UserProfile {
  const UserProfile({
    required this.uid,
    required this.email,
    required this.name,
    required this.role,
  });

  final String uid;
  final String email;
  final String name;
  final String role;

  bool get isAdmin => role == 'admin';
}

class Activity {
  const Activity({
    required this.by,
    required this.byUid,
    required this.verb,
    required this.title,
    this.amountPaise,
    required this.at,
  });

  final String by;
  final String byUid;
  final String verb;
  final String title;
  final int? amountPaise;
  final DateTime at;
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.text,
    required this.by,
    required this.byUid,
    required this.at,
  });

  final String id;
  final String text;
  final String by;
  final String byUid;
  final DateTime at;
}