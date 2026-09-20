import '../models/expense.dart';
import '../models/models.dart';

/// Abstraction over the group data source.
///
/// The production implementation talks to Firestore; a fake in-memory
/// implementation is used in unit tests. Models (dates, timestamps, field
/// names) are already normalized by the time they cross this boundary.
abstract class GroupRepository {
  /// Creates a new group with one initial member. Returns the group
  /// (its `id` is the auto-generated Firestore document id / group code).
  Future<GroupInfo> createGroup({
    required String name,
    required String member,
  });

  /// Reads a group by code. Returns `null` if it does not exist.
  Future<GroupInfo?> fetchGroup(String groupId);

  /// Real-time snapshots of the group document. `null` when deleted.
  Stream<GroupInfo?> watchGroup(String groupId);

  /// Real-time snapshots of expenses, newest first.
  Stream<List<Expense>> watchExpenses(String groupId);

  /// Real-time snapshots of the latest 30 activity events, newest first.
  Stream<List<Activity>> watchActivity(String groupId);

  /// Real-time snapshots of the latest 50 messages, newest first.
  Stream<List<ChatMessage>> watchMessages(String groupId);

  /// Replaces the group's members array.
  Future<void> setMembers(String groupId, List<String> members);

  /// Removes a member from the group and strips them from the shares of
  /// every expense, as one atomic batched write.
  Future<void> removeMember(String groupId, String member);

  /// Adds an expense. Batches the expense document plus its `added`
  /// activity entry into one atomic write.
  Future<void> addExpense(String groupId, Expense expense);

  /// Updates an expense. Batches the field update plus its `edited`
  /// activity entry; the edit history is appended with [newChanges] in
  /// the same atomic write (using `FieldValue.arrayUnion`).
  Future<void> replaceExpense(
    String groupId,
    Expense expense, {
    required String by,
    required List<ExpenseChange> newChanges,
  });

  /// Deletes an expense. Batches the delete plus its `deleted`
  /// activity entry into one atomic write.
  Future<void> removeExpense(
    String groupId,
    Expense expense, {
    required String by,
  });

  /// Empties the group's activity subcollection.
  Future<void> clearActivity(String groupId);

  /// Writes a chat message from [senderName].
  Future<void> sendMessage(
    String groupId, {
    required String senderName,
    required String text,
  });
}