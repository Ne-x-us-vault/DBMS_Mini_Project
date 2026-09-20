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
  /// The caller's account is also recorded as a member.
  Future<GroupInfo> createGroup({
    required String name,
    required String member,
  });

  /// Real-time list of groups the signed-in account has joined
  /// (via `users/{uid}/groups` memberships). Deleted groups are skipped.
  Stream<List<GroupInfo>> myGroups();

  /// Joins the signed-in account to an existing group, acting as [name].
  /// [name] joins the group's members only if it is not already present.
  /// Throws if the group does not exist.
  Future<GroupInfo> joinGroup(String groupId, {required String name});

  /// Leaves a group: deletes the account's membership, removes [name] from
  /// the group's members and strips it from the shares of every expense in
  /// one atomic batched write.
  Future<void> leaveGroup(String groupId, {required String name});

  /// Reads a group by code. Returns `null` if it does not exist.
  Future<GroupInfo?> fetchGroup(String groupId);

  /// Reports (aggregate) queries — the production implementation runs these
  /// as server-side Firestore `count`/`sum` aggregate queries, which is what
  /// the DBMS demo points at.

  /// Number of expenses in the group (server-side `COUNT(*)`).
  Future<int> expenseCount(String groupId);

  /// Number of expenses whose `date` is in `[from, to)` (range query +
  /// `COUNT(*)`).
  Future<int> expenseCountBetween(
    String groupId, {
    required DateTime from,
    required DateTime to,
  });

  /// Sum of all `amountPaise` in the group (server-side `SUM(amountPaise)`).
  Future<int> totalTrackedPaise(String groupId);

  /// Total amount paid per member (`GROUP BY paidBy, SUM(amountPaise)`).
  Future<Map<String, int>> perMemberPaid(String groupId);

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