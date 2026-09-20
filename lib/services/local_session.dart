import 'package:shared_preferences/shared_preferences.dart';

/// On-device session state. Only the joined group id and the
/// "Managing as" name live here — everything else is in Firestore.
class LocalSession {
  static const _groupIdKey = 'split_chat_group_id';
  static const _managingKey = 'split_chat_managing_as';

  String? groupId;
  String managingAs = '';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    groupId = prefs.getString(_groupIdKey);
    managingAs = prefs.getString(_managingKey) ?? '';
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