import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/expense.dart';
import '../utils/money.dart';

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

class Settlement {
  const Settlement(this.from, this.to, this.amountPaise);

  final String from;
  final String to;
  final int amountPaise;
}

class AppStore extends ChangeNotifier {
  static const _key = 'split_chat_store';

  List<String> members = [];
  List<Expense> expenses = [];
  List<Activity> activity = [];
  String currentUser = 'Aarav';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) {
      members = ['Aarav', 'Meera'];
      currentUser = 'Aarav';
      await save();
      return;
    }
    final data = jsonDecode(raw) as Map<String, dynamic>;
    members = (data['members'] as List).cast<String>();
    expenses = [
      for (final e in (data['expenses'] as List))
        Expense.fromJson((e as Map).cast<String, Object?>()),
    ];
    currentUser = (data['currentUser'] as String?) ?? '';
    if (!members.contains(currentUser) && members.isNotEmpty) {
      currentUser = members.first;
    }
    if (currentUser.isEmpty) currentUser = 'Aarav';
    activity = [
      for (final a in (data['activity'] as List?) ?? const [])
        Activity(
          by: (a as Map)['by'] as String,
          verb: a['verb'] as String,
          title: a['title'] as String,
          amountPaise: a['amountPaise'] as int?,
          at: DateTime.parse(a['at'] as String),
        ),
    ];
    notifyListeners();
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'members': members,
        'expenses': [for (final e in expenses) e.toJson()],
        'currentUser': currentUser,
        'activity': [
          for (final a in activity)
            {
              'by': a.by,
              'verb': a.verb,
              'title': a.title,
              'amountPaise': a.amountPaise,
              'at': a.at.toIso8601String(),
            },
        ],
      }),
    );
  }

  void setCurrentUser(String name) {
    if (name == currentUser) return;
    currentUser = name;
    _commit();
  }

  void addMember(String name) {
    if (name.isEmpty || members.contains(name)) return;
    members.add(name);
    _commit();
  }

  void removeMember(String name) {
    members.remove(name);
    for (var i = 0; i < expenses.length; i++) {
      final e = expenses[i];
      final shares = {...e.sharesPaise}..remove(name);
      if (shares.length != e.sharesPaise.length) {
        expenses[i] = Expense(
          id: e.id,
          title: e.title,
          amountPaise: e.amountPaise,
          split: e.split,
          paidBy: e.paidBy,
          sharesPaise: shares,
          date: e.date,
          addedBy: e.addedBy,
          changes: e.changes,
        );
      }
    }
    _commit();
  }

  void addExpense(Expense e) {
    expenses.add(e);
    activity.insert(
      0,
      Activity(
        by: e.addedBy,
        verb: 'added',
        title: e.title,
        amountPaise: e.amountPaise,
        at: DateTime.now(),
      ),
    );
    _commit();
  }

  void replaceExpense(Expense e) {
    final i = expenses.indexWhere((x) => x.id == e.id);
    if (i == -1) return;
    final before = expenses[i];
    final diffs = _diff(before, e);
    final changes = <ExpenseChange>[
      ...before.changes,
      for (final d in diffs)
        ExpenseChange(by: currentUser, change: d, at: DateTime.now()),
    ];
    expenses[i] = Expense(
      id: e.id,
      title: e.title,
      amountPaise: e.amountPaise,
      split: e.split,
      paidBy: e.paidBy,
      sharesPaise: e.sharesPaise,
      date: e.date,
      addedBy: e.addedBy,
      changes: changes,
    );
    if (diffs.isNotEmpty) {
      activity.insert(
        0,
        Activity(
          by: currentUser,
          verb: 'edited',
          title: e.title,
          amountPaise: e.amountPaise,
          at: DateTime.now(),
        ),
      );
    }
    _commit();
  }

  void removeExpense(String id) {
    final i = expenses.indexWhere((e) => e.id == id);
    if (i == -1) return;
    final e = expenses.removeAt(i);
    activity.insert(
      0,
      Activity(
        by: currentUser,
        verb: 'deleted',
        title: e.title,
        amountPaise: e.amountPaise,
        at: DateTime.now(),
      ),
    );
    _commit();
  }

  void clearActivity() {
    if (activity.isEmpty) return;
    activity.clear();
    _commit();
  }

  List<String> _diff(Expense before, Expense after) {
    final d = <String>[];
    if (before.split != after.split) {
      d.add(after.split ? 'Expense is now split' : 'Expense is no longer split');
    }
    if (before.title != after.title) {
      d.add('Title: “${before.title}” → “${after.title}”');
    }
    if (before.amountPaise != after.amountPaise) {
      d.add(
        'Amount: ${fmtPaise(before.amountPaise)} → ${fmtPaise(after.amountPaise)}',
      );
    }
    if (before.split && after.split && before.paidBy != after.paidBy) {
      d.add('Paid by: ${before.paidBy ?? '-'} → ${after.paidBy ?? '-'}');
    }
    final bShares =
        before.sharesPaise.entries.map((e) => '${e.key}:${e.value}').toList()
          ..sort();
    final aShares =
        after.sharesPaise.entries.map((e) => '${e.key}:${e.value}').toList()
          ..sort();
    if (!listEquals(bShares, aShares)) {
      d.add(
        'Shares: ${fmtShares(before.sharesPaise)} → ${fmtShares(after.sharesPaise)}',
      );
    }
    final bd = before.date;
    final ad = after.date;
    if (bd.year != ad.year || bd.month != ad.month || bd.day != ad.day) {
      d.add(
        'Date: ${bd.day}/${bd.month}/${bd.year} → ${ad.day}/${ad.month}/${ad.year}',
      );
    }
    return d;
  }

  void _commit() {
    notifyListeners();
    save();
  }

  Map<String, int> balances() {
    final b = <String, int>{for (final m in members) m: 0};
    for (final e in expenses) {
      if (!e.split) continue;
      final payer = e.paidBy;
      if (payer != null) b[payer] = (b[payer] ?? 0) + e.amountPaise;
      e.sharesPaise.forEach((m, share) {
        b[m] = (b[m] ?? 0) - share;
      });
    }
    return b;
  }

  List<Settlement> settle() {
    final b = balances();
    final debtors = b.entries.where((e) => e.value < 0).toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final creditors = b.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final out = <Settlement>[];
    var ci = 0;
    for (final d in debtors) {
      var rest = -d.value;
      while (rest > 0 && ci < creditors.length) {
        final creditor = creditors[ci];
        final available = creditor.value;
        final pay = rest < available ? rest : available;
        out.add(Settlement(d.key, creditor.key, pay));
        creditors[ci] = MapEntry(creditor.key, available - pay);
        rest -= pay;
        if (available - pay == 0) ci++;
      }
    }
    return out;
  }
}