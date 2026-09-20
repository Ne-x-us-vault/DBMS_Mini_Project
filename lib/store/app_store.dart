import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../logic/split_logic.dart';
import '../models/expense.dart';
import '../models/models.dart';

class AppStore extends ChangeNotifier {
  AppStore({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _auth = auth ?? FirebaseAuth.instance,
        _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final List<StreamSubscription> _subs = [];

  List<UserProfile> users = const [];
  List<Expense> expenses = const [];
  List<Activity> activity = const [];
  List<ChatMessage> messages = const [];

  UserProfile? _profile;

  UserProfile? get profile => _profile;
  String get myUid => _auth.currentUser?.uid ?? '';
  String get myName => _profile?.name ?? _auth.currentUser?.displayName ?? 'Me';
  bool get isAdmin => _profile?.isAdmin ?? false;
  bool get loaded => _profile != null;

  List<String> get members => [for (final u in users) u.name];

  bool canEdit(Expense e) => isAdmin || e.ownerId == myUid;
  bool canDelete(Expense e) => canEdit(e);

  DateTime _ts(Object? v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.parse(v).toLocal();
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  Map<String, dynamic> _readExpenseMap(Map<String, dynamic> raw) {
    final m = Map<String, dynamic>.from(raw);
    m['date'] = _ts(m['date']);
    m['changes'] = [
      for (final c in (raw['changes'] as List?) ?? const [])
        {
          'by': (c as Map)['by'],
          'change': c['change'],
          'at': _ts(c['at']),
        },
    ];
    return m;
  }

  Map<String, Object?> _expenseDoc(Expense e) => {
        ...e.toMap(),
        'date': Timestamp.fromDate(e.date),
        'changes': [
          for (final c in e.changes)
            {
              'by': c.by,
              'change': c.change,
              'at': Timestamp.fromDate(c.at),
            },
        ],
      };

  Future<void> init() async {
    _subs.add(_db.collection('users').snapshots().listen(_onUsers,
        onError: (_) {}));
    _subs.add(_db
        .collection('expenses')
        .orderBy('date', descending: true)
        .snapshots()
        .listen(_onExpenses, onError: (_) {}));
    _subs.add(_db
        .collection('activity')
        .orderBy('at', descending: true)
        .limit(50)
        .snapshots()
        .listen(_onActivity, onError: (_) {}));
    _subs.add(_db
        .collection('messages')
        .orderBy('at', descending: false)
        .snapshots()
        .listen(_onMessages, onError: (_) {}));
  }

  void _onUsers(QuerySnapshot<Map<String, dynamic>> snap) {
    users = [
      for (final d in snap.docs)
        UserProfile(
          uid: d.id,
          email: d.data()['email'] as String? ?? '',
          name: d.data()['name'] as String? ?? '',
          role: d.data()['role'] as String? ?? 'member',
        ),
    ];
    for (final u in users) {
      if (u.uid == myUid) {
        _profile = u;
        break;
      }
    }
    notifyListeners();
  }

  void _onExpenses(QuerySnapshot<Map<String, dynamic>> snap) {
    expenses = [
      for (final d in snap.docs)
        Expense.fromMap(_readExpenseMap(Map.of(d.data()))),
    ];
    notifyListeners();
  }

  void _onActivity(QuerySnapshot<Map<String, dynamic>> snap) {
    activity = [
      for (final d in snap.docs)
        Activity(
          by: d.data()['by'] as String? ?? '',
          byUid: d.data()['byUid'] as String? ?? '',
          verb: d.data()['verb'] as String? ?? '',
          title: d.data()['title'] as String? ?? '',
          amountPaise: (d.data()['amountPaise'] as num?)?.toInt(),
          at: _ts(d.data()['at']),
        ),
    ];
    notifyListeners();
  }

  void _onMessages(QuerySnapshot<Map<String, dynamic>> snap) {
    messages = [
      for (final d in snap.docs)
        ChatMessage(
          id: d.id,
          text: d.data()['text'] as String? ?? '',
          by: d.data()['by'] as String? ?? '',
          byUid: d.data()['byUid'] as String? ?? '',
          at: _ts(d.data()['at']),
        ),
    ];
    notifyListeners();
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
      addedBy: myName,
      ownerId: myUid,
    );
    await _db.collection('expenses').doc(e.id).set(_expenseDoc(stamped));
    await _log('added', stamped.title, stamped.amountPaise);
  }

  Future<void> replaceExpense(Expense e) async {
    final ref = _db.collection('expenses').doc(e.id);
    final snap = await ref.get();
    if (!snap.exists) return;
    final before = Expense.fromMap(_readExpenseMap(snap.data()!));
    final diffs = diffExpenses(before, e);
    final changes = <ExpenseChange>[
      ...before.changes,
      for (final d in diffs)
        ExpenseChange(by: myName, change: d, at: DateTime.now()),
    ];
    final updated = Expense(
      id: e.id,
      title: e.title,
      amountPaise: e.amountPaise,
      split: e.split,
      paidBy: e.paidBy,
      sharesPaise: e.sharesPaise,
      date: e.date,
      addedBy: before.addedBy,
      ownerId: before.ownerId,
      changes: changes,
    );
    await ref.set(_expenseDoc(updated));
    if (diffs.isNotEmpty) {
      await _log('edited', updated.title, updated.amountPaise);
    }
  }

  Future<void> removeExpense(String id) async {
    final ref = _db.collection('expenses').doc(id);
    final snap = await ref.get();
    if (!snap.exists) return;
    final e = Expense.fromMap(_readExpenseMap(snap.data()!));
    if (!canEdit(e)) return;
    await ref.delete();
    await _log('deleted', e.title, e.amountPaise);
  }

  Future<void> clearActivity() async {
    final snap = await _db.collection('activity').get();
    for (final d in snap.docs) {
      await d.reference.delete();
    }
  }

  Future<void> sendMessage(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    await _db.collection('messages').add({
      'text': t,
      'by': myName,
      'byUid': myUid,
      'at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setRole(String uid, String role) async {
    await _db.collection('users').doc(uid).update({'role': role});
  }

  Future<void> removeUser(String uid) async {
    await _db.collection('users').doc(uid).delete();
  }

  Future<void> _log(String verb, String title, int? amount) async {
    await _db.collection('activity').add({
      'by': myName,
      'byUid': myUid,
      'verb': verb,
      'title': title,
      'amountPaise': amount,
      'at': FieldValue.serverTimestamp(),
    });
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}