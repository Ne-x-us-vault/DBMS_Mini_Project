import 'package:flutter/foundation.dart';

import '../models/expense.dart';
import '../utils/money.dart';

class Settlement {
  const Settlement(this.from, this.to, this.amountPaise);

  final String from;
  final String to;
  final int amountPaise;
}

Map<String, int> computeBalances(
  List<String> members,
  List<Expense> expenses,
) {
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

List<Settlement> computeSettlements(
  List<String> members,
  List<Expense> expenses,
) {
  final b = computeBalances(members, expenses);
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

/// Returns a copy of [e] with [member] removed from `sharesPaise`.
///
/// Used when a member leaves a group: their share is stripped out of every
/// expense. Tracking-only expenses (no shares) are returned unchanged.
Expense stripMemberFromShares(Expense e, String member) {
  if (!e.split || !e.sharesPaise.containsKey(member)) return e;
  final shares = Map<String, int>.of(e.sharesPaise)..remove(member);
  return Expense(
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

List<String> diffExpenses(Expense before, Expense after) {
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