import 'dart:async';

import 'package:flutter/foundation.dart';

import '../logic/split_logic.dart';
import '../models/expense.dart';
import '../models/models.dart';
import '../services/group_repository.dart';
import '../services/local_session.dart';

/// Holds the live state for one group.
///
/// All data flows from [GroupRepository] real-time streams; every mutation
/// is a single atomic batched write handled by the repository. The store
/// only slices streams into the shapes the UI already knows
/// (`members`, `expenses` newest-first, `activity` newest-first,
/// `messages` oldest-first for chat) and calls `notifyListeners()`.
class AppStore extends ChangeNotifier {
  AppStore({
    required this.groupId,
    required GroupRepository repo,
    LocalSession? session,
  })  : _repository = repo,
        _local = session ?? LocalSession();

  final String groupId;
  final GroupRepository _repository;
  final LocalSession _local;
  final List<StreamSubscription> _subs = [];

  GroupInfo? groupInfo;
  List<Expense> expenses = const [];
  List<Activity> activity = const [];
  List<ChatMessage> messages = const [];

  bool ready = false;

  /// The "Managing as" name — who this device acts as. Stored on-device.
  String get managingAs => _local.managingAs;

  String get groupName => groupInfo?.name ?? '';
  List<String> get members => groupInfo?.members ?? const [];

  /// Whether the group still exists on Firestore.
  bool get groupExists => groupInfo != null;

  Map<String, int> balances() => computeBalances(members, expenses);
  List<Settlement> settle() => computeSettlements(members, expenses);

  void init() {
    _subs.add(_repository.watchGroup(groupId).listen((g) {
      groupInfo = g;
      ready = true;
      notifyListeners();
    }, onError: (_) {}));
    _subs.add(_repository.watchExpenses(groupId).listen((list) {
      expenses = list;
      notifyListeners();
    }, onError: (_) {}));
    _subs.add(_repository.watchActivity(groupId).listen((list) {
      activity = list;
      notifyListeners();
    }, onError: (_) {}));
    _subs.add(_repository.watchMessages(groupId).listen((list) {
      messages = List.of(list.reversed);
      notifyListeners();
    }, onError: (_) {}));
  }

  void setManagingAs(String name) {
    _local.setManagingAs(name);
    notifyListeners();
  }

  Future<void> addMember(String name) async {
    final n = name.trim();
    if (n.isEmpty || members.contains(n)) return;
    await _repository.setMembers(groupId, [...members, n]);
  }

  Future<void> removeMember(String name) {
    return _repository.removeMember(groupId, name);
  }

  Future<void> addExpense(Expense e) async {
    final stamped = Expense(
      id: e.id,
      title: e.title,
      amountPaise: e.amountPaise,
      split: e.split,
      paidBy: e.paidBy,
      sharesPaise: e.sharesPaise,
      date: e.date,
      addedBy: managingAs,
      changes: e.changes,
    );
    await _repository.addExpense(groupId, stamped);
  }

  Future<void> replaceExpense(Expense after) async {
    Expense? before;
    for (final e in expenses) {
      if (e.id == after.id) {
        before = e;
        break;
      }
    }
    if (before == null) return;
    final diffs = diffExpenses(before, after);
    if (diffs.isEmpty) return;
    final newChanges = [
      for (final d in diffs)
        ExpenseChange(by: managingAs, change: d, at: DateTime.now()),
    ];
    await _repository.replaceExpense(
      groupId,
      after,
      by: managingAs,
      newChanges: newChanges,
    );
  }

  Future<void> removeExpense(Expense e) async {
    await _repository.removeExpense(groupId, e, by: managingAs);
  }

  Future<void> clearActivity() {
    return _repository.clearActivity(groupId);
  }

  Future<void> sendMessage(String text) {
    return _repository.sendMessage(groupId, senderName: managingAs, text: text);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}