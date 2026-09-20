import 'dart:async';

import 'package:split_chat/logic/split_logic.dart';
import 'package:split_chat/models/expense.dart';
import 'package:split_chat/models/models.dart';
import 'package:split_chat/services/group_repository.dart';

/// In-memory [GroupRepository] for unit tests. Mirrors the Firestore
/// semantics: streams emit the latest state after every mutation, expenses
/// are shipped newest-first, activity newest-first (latest 30) and messages
/// newest-first (latest 50).
class InMemoryGroupRepository implements GroupRepository {
  GroupInfo? _group;
  final List<Expense> _expenses = [];
  final List<Activity> _activity = [];
  final List<ChatMessage> _messages = [];

  final _groupCtrl = StreamController<GroupInfo?>.broadcast();
  final _expCtrl = StreamController<List<Expense>>.broadcast();
  final _actCtrl = StreamController<List<Activity>>.broadcast();
  final _msgCtrl = StreamController<List<ChatMessage>>.broadcast();

  int _seq = 0;

  void _emit() {
    _groupCtrl.add(_group);
    final sortedExpenses = [..._expenses]
      ..sort((a, b) => b.date.compareTo(a.date));
    _expCtrl.add(sortedExpenses);
    final sortedActivity = [..._activity]
      ..sort((a, b) => b.at.compareTo(a.at));
    _actCtrl.add(sortedActivity.take(30).toList());
    final sortedMessages = [..._messages]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _msgCtrl.add(sortedMessages.take(50).toList());
  }

  /// The group as currently held, for direct assertions.
  GroupInfo? get group => _group;

  @override
  Future<GroupInfo> createGroup({
    required String name,
    required String member,
  }) async {
    _group = GroupInfo(id: 'g-${_seq++}', name: name, members: [member]);
    _emit();
    return _group!;
  }

  @override
  Future<GroupInfo?> fetchGroup(String groupId) async => _group;

  @override
  Stream<GroupInfo?> watchGroup(String groupId) {
    Future(() => _groupCtrl.add(_group));
    return _groupCtrl.stream;
  }

  @override
  Stream<List<Expense>> watchExpenses(String groupId) {
    Future(() => _expCtrl.add([..._expenses]));
    return _expCtrl.stream;
  }

  @override
  Stream<List<Activity>> watchActivity(String groupId) {
    Future(() => _actCtrl.add([..._activity]));
    return _actCtrl.stream;
  }

  @override
  Stream<List<ChatMessage>> watchMessages(String groupId) {
    Future(() => _msgCtrl.add([..._messages]));
    return _msgCtrl.stream;
  }

  @override
  Future<void> setMembers(String groupId, List<String> members) async {
    _group = GroupInfo(id: _group!.id, name: _group!.name, members: members);
    _emit();
  }

  @override
  Future<void> removeMember(String groupId, String member) async {
    _group = GroupInfo(
      id: _group!.id,
      name: _group!.name,
      members: [..._group!.members]..remove(member),
    );
    for (var i = 0; i < _expenses.length; i++) {
      _expenses[i] = stripMemberFromShares(_expenses[i], member);
    }
    _emit();
  }

  @override
  Future<void> addExpense(String groupId, Expense expense) async {
    _expenses.add(expense);
    _activity.insert(
      0,
      Activity(
        by: expense.addedBy,
        verb: 'added',
        title: expense.title,
        amountPaise: expense.amountPaise,
        at: expense.date,
      ),
    );
    _emit();
  }

  @override
  Future<void> replaceExpense(
    String groupId,
    Expense expense, {
    required String by,
    required List<ExpenseChange> newChanges,
  }) async {
    final idx = _expenses.indexWhere((e) => e.id == expense.id);
    if (idx < 0) return;
    final prev = _expenses[idx];
    _expenses[idx] = Expense(
      id: expense.id,
      title: expense.title,
      amountPaise: expense.amountPaise,
      split: expense.split,
      paidBy: expense.paidBy,
      sharesPaise: expense.sharesPaise,
      date: expense.date,
      addedBy: prev.addedBy,
      changes: [...prev.changes, ...newChanges],
    );
    _activity.insert(
      0,
      Activity(
        by: by,
        verb: 'edited',
        title: expense.title,
        amountPaise: expense.amountPaise,
        at: DateTime.now(),
      ),
    );
    _emit();
  }

  @override
  Future<void> removeExpense(
    String groupId,
    Expense expense, {
    required String by,
  }) async {
    _expenses.removeWhere((e) => e.id == expense.id);
    _activity.insert(
      0,
      Activity(
        by: by,
        verb: 'deleted',
        title: expense.title,
        amountPaise: expense.amountPaise,
        at: DateTime.now(),
      ),
    );
    _emit();
  }

  @override
  Future<void> clearActivity(String groupId) async {
    _activity.clear();
    _emit();
  }

  @override
  Future<void> sendMessage(
    String groupId, {
    required String senderName,
    required String text,
  }) async {
    _messages.insert(
      0,
      ChatMessage(
        id: 'm${_seq++}',
        senderName: senderName,
        text: text,
        createdAt: DateTime.now(),
      ),
    );
    _emit();
  }
}