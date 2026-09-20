import 'package:shared_preferences/shared_preferences.dart';

/// On-device session state. The display (identity) name plus which group is
/// currently open ("Managing as") live here — the groups themselves are in
/// Firestore.
class LocalSession {
  static const _groupIdKey = 'split_chat_group_id';
  static const _managingKey = 'split_chat_managing_as';
  static const _displayNameKey = 'split_chat_display_name';

  String? groupId;
  String managingAs = '';
  String displayName = '';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    groupId = prefs.getString(_groupIdKey);
    managingAs = prefs.getString(_managingKey) ?? '';
    displayName = prefs.getString(_displayNameKey) ?? '';
  }

  Future<void> setDisplayName(String? name) async {
    displayName = name ?? '';
    final prefs = await SharedPreferences.getInstance();
    if (name == null || name.isEmpty) {
      await prefs.remove(_displayNameKey);
    } else {
      await prefs.setString(_displayNameKey, name);
    }
  }

  Future<void> setGroupId(String? id) async {
    groupId = id;
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_groupIdKey);
    } else {
      await prefs.setString(_groupIdKey, id);
    }
  }

  Future<void> setManagingAs(String name) async {
    managingAs = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_managingKey, name);
  }
}