import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../logic/split_logic.dart';
import '../models/expense.dart';
import '../models/models.dart';
import 'group_repository.dart';

/// Firestore-backed [GroupRepository].
///
/// Data layout:
/// - `groups/{groupId}` — `{name, members: [names], createdAt}`
/// - `groups/{groupId}/expenses/{id}` — Expense map, `date` as Timestamp
/// - `groups/{groupId}/activity/{id}` — `{by, verb, title, amountPaise, at}`
/// - `groups/{groupId}/messages/{id}` — `{senderName, text, createdAt}`
/// - `users/{uid}` — `{displayName, email, createdAt}` (owned by AuthRepository)
/// - `users/{uid}/groups/{groupId}` — `{name, joinedAt}` (memberships)
class FirestoreGroupRepository implements GroupRepository {
  FirestoreGroupRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _groups =>
      _db.collection('groups');

  DocumentReference<Map<String, dynamic>> _group(String id) =>
      _groups.doc(id);

  String get _uid {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      throw StateError('Not signed in');
    }
    return u.uid;
  }

  CollectionReference<Map<String, dynamic>> _memberships() =>
      _db.collection('users').doc(_uid).collection('groups');

  DocumentReference<Map<String, dynamic>> _membership(String groupId) =>
      _memberships().doc(groupId);

  CollectionReference<Map<String, dynamic>> _expenses(String groupId) =>
      _group(groupId).collection('expenses');

  CollectionReference<Map<String, dynamic>> _activity(String groupId) =>
      _group(groupId).collection('activity');

  CollectionReference<Map<String, dynamic>> _messages(String groupId) =>
      _group(groupId).collection('messages');

  DateTime _ts(Object? v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.parse(v).toLocal();
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  GroupInfo _groupFromDoc(String id, Map<String, dynamic> data) => GroupInfo(
        id: id,
        name: data['name'] as String? ?? '',
        members: [for (final m in (data['members'] as List?) ?? const []) m as String],
      );

  Expense _expenseFromDoc(String id, Map<String, dynamic> data) {
    final m = Map<String, dynamic>.from(data);
    m['id'] = id;
    m['date'] = _ts(m['date']);
    m['changes'] = [
      for (final c in (data['changes'] as List?) ?? const [])
        {
          'by': (c as Map)['by'],
          'change': c['change'],
          'at': _ts(c['at']),
        },
    ];
    return Expense.fromMap(m);
  }

  Map<String, Object?> _expenseWrite(Expense e) {
    final changes = [
      for (final c in e.changes)
        {'by': c.by, 'change': c.change, 'at': Timestamp.fromDate(c.at)},
    ];
    return {
      'title': e.title,
      'amountPaise': e.amountPaise,
      'split': e.split,
      'paidBy': e.paidBy,
      'sharesPaise': e.sharesPaise,
      'date': Timestamp.fromDate(e.date),
      'addedBy': e.addedBy,
      'changes': changes,
    };
  }

  Map<String, dynamic> _activityWrite({
    required String by,
    required String verb,
    required String title,
    required int? amountPaise,
  }) =>
      {
        'by': by,
        'verb': verb,
        'title': title,
        'amountPaise': amountPaise,
        'at': FieldValue.serverTimestamp(),
      };

  @override
  Future<GroupInfo> createGroup({
    required String name,
    required String member,
  }) async {
    final ref = _groups.doc();
    final batch = _db.batch();
    batch.set(ref, {
      'name': name,
      'members': [member],
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(_membership(ref.id), {
      'name': member,
      'joinedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    return GroupInfo(id: ref.id, name: name, members: [member]);
  }

  @override
  Stream<List<GroupInfo>> myGroups() {
    return _memberships().snapshots().asyncMap((snap) async {
      final groups = <GroupInfo>[];
      for (final m in snap.docs) {
        final g = await _group(m.id).get();
        if (g.exists) {
          groups.add(_groupFromDoc(g.id, g.data()!));
        }
      }
      groups.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return groups;
    });
  }

  @override
  Future<GroupInfo> joinGroup(
    String groupId, {
    required String name,
  }) async {
    final snap = await _group(groupId).get();
    if (!snap.exists) {
      throw Exception('Group $groupId does not exist');
    }
    final batch = _db.batch();
    batch.update(_group(groupId), {
      'members': FieldValue.arrayUnion([name]),
    });
    batch.set(_membership(groupId), {
      'name': name,
      'joinedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    return _groupFromDoc(snap.id, snap.data()!);
  }

  @override
  Future<void> leaveGroup(
    String groupId, {
    required String name,
  }) async {
    final batch = _db.batch();
    final groupSnap = await _group(groupId).get();
    if (groupSnap.exists) {
      batch.update(_group(groupId), {
        'members': FieldValue.arrayRemove([name]),
      });
      final expensesSnap = await _expenses(groupId).get();
      for (final d in expensesSnap.docs) {
        final e = _expenseFromDoc(d.id, d.data());
        final stripped = stripMemberFromShares(e, name);
        batch.update(_expenses(groupId).doc(d.id), {
          'sharesPaise': stripped.sharesPaise,
        });
      }
    }
    batch.delete(_membership(groupId));
    await batch.commit();
  }

  @override
  Future<GroupInfo?> fetchGroup(String groupId) async {
    final snap = await _group(groupId).get();
    if (!snap.exists) return null;
    return _groupFromDoc(snap.id, snap.data()!);
  }

  @override
  Stream<GroupInfo?> watchGroup(String groupId) {
    return _group(groupId).snapshots().map((s) {
      if (!s.exists) return null;
      return _groupFromDoc(s.id, s.data()!);
    });
  }

  @override
  Future<int> expenseCount(String groupId) async {
    final snap = await _expenses(groupId).count().get();
    return snap.count ?? 0;
  }

  @override
  Future<int> expenseCountBetween(
    String groupId, {
    required DateTime from,
    required DateTime to,
  }) async {
    final snap = await _expenses(groupId)
        .where('date', isGreaterThanOrEqualTo: from)
        .where('date', isLessThan: to)
        .count()
        .get();
    return snap.count ?? 0;
  }

  @override
  Future<int> totalTrackedPaise(String groupId) async {
    final snap = await _expenses(groupId)
        .aggregate(sum('amountPaise'))
        .get();
    return snap.getSum('amountPaise')?.toInt() ?? 0;
  }

  @override
  Future<Map<String, int>> perMemberPaid(String groupId) async {
    final snap = await _expenses(groupId).get();
    final totals = <String, int>{};
    for (final d in snap.docs) {
      final data = d.data();
      final paidBy = data['paidBy'] as String?;
      if (paidBy == null || paidBy.isEmpty) continue;
      totals[paidBy] =
          (totals[paidBy] ?? 0) + ((data['amountPaise'] as num?)?.toInt() ?? 0);
    }
    return totals;
  }

  @override
  Stream<List<Expense>> watchExpenses(String groupId) {
    return _expenses(groupId)
        .orderBy('date', descending: true)
        .snapshots()
        .map((snap) => [
              for (final d in snap.docs) _expenseFromDoc(d.id, d.data()),
            ]);
  }

  @override
  Stream<List<Activity>> watchActivity(String groupId) {
    return _activity(groupId)
        .orderBy('at', descending: true)
        .limit(30)
        .snapshots()
        .map((snap) => [
              for (final d in snap.docs)
                Activity(
                  by: d.data()['by'] as String? ?? '',
                  verb: d.data()['verb'] as String? ?? '',
                  title: d.data()['title'] as String? ?? '',
                  amountPaise: (d.data()['amountPaise'] as num?)?.toInt(),
                  at: _ts(d.data()['at']),
                ),
            ]);
  }

  @override
  Stream<List<ChatMessage>> watchMessages(String groupId) {
    return _messages(groupId)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) => [
              for (final d in snap.docs)
                ChatMessage(
                  id: d.id,
                  senderName: d.data()['senderName'] as String? ?? '',
                  text: d.data()['text'] as String? ?? '',
                  createdAt: _ts(d.data()['createdAt']),
                ),
            ]);
  }

  @override
  Future<void> setMembers(String groupId, List<String> members) async {
    await _group(groupId).update({'members': members});
  }

  @override
  Future<void> removeMember(String groupId, String member) async {
    final expensesSnap = await _expenses(groupId).get();
    final batch = _db.batch();
    batch.update(_group(groupId), {
      'members': FieldValue.arrayRemove([member]),
    });
    for (final d in expensesSnap.docs) {
      final e = _expenseFromDoc(d.id, d.data());
      final stripped = stripMemberFromShares(e, member);
      batch.update(_expenses(groupId).doc(d.id), {
        'sharesPaise': stripped.sharesPaise,
      });
    }
    await batch.commit();
  }

  @override
  Future<void> addExpense(String groupId, Expense expense) async {
    final batch = _db.batch();
    batch.set(_expenses(groupId).doc(expense.id), _expenseWrite(expense));
    batch.set(
      _activity(groupId).doc(),
      _activityWrite(
        by: expense.addedBy,
        verb: 'added',
        title: expense.title,
        amountPaise: expense.amountPaise,
      ),
    );
    await batch.commit();
  }

  @override
  Future<void> replaceExpense(
    String groupId,
    Expense expense, {
    required String by,
    required List<ExpenseChange> newChanges,
  }) async {
    final batch = _db.batch();
    batch.update(_expenses(groupId).doc(expense.id), {
      'title': expense.title,
      'amountPaise': expense.amountPaise,
      'split': expense.split,
      'paidBy': expense.paidBy,
      'sharesPaise': expense.sharesPaise,
      'date': Timestamp.fromDate(expense.date),
      'changes': FieldValue.arrayUnion([
        for (final c in newChanges)
          {'by': c.by, 'change': c.change, 'at': Timestamp.fromDate(c.at)},
      ]),
    });
    batch.set(
      _activity(groupId).doc(),
      _activityWrite(
        by: by,
        verb: 'edited',
        title: expense.title,
        amountPaise: expense.amountPaise,
      ),
    );
    await batch.commit();
  }

  @override
  Future<void> removeExpense(
    String groupId,
    Expense expense, {
    required String by,
  }) async {
    final batch = _db.batch();
    batch.delete(_expenses(groupId).doc(expense.id));
    batch.set(
      _activity(groupId).doc(),
      _activityWrite(
        by: by,
        verb: 'deleted',
        title: expense.title,
        amountPaise: expense.amountPaise,
      ),
    );
    await batch.commit();
  }

  @override
  Future<void> clearActivity(String groupId) async {
    final snap = await _activity(groupId).get();
    final batch = _db.batch();
    for (final d in snap.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
  }

  @override
  Future<void> sendMessage(
    String groupId, {
    required String senderName,
    required String text,
  }) async {
    await _messages(groupId).add({
      'senderName': senderName,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}