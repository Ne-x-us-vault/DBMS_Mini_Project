class ExpenseChange {
  const ExpenseChange({required this.by, required this.change, required this.at});

  final String by;
  final String change;
  final DateTime at;
}

class Expense {
  Expense({
    required this.id,
    required this.title,
    required this.amountPaise,
    required this.split,
    this.paidBy,
    this.sharesPaise = const {},
    required this.date,
    required this.addedBy,
    this.changes = const [],
  });

  factory Expense.equalSplit({
    required String id,
    required String title,
    required int amountPaise,
    required String paidBy,
    required List<String> members,
    required DateTime date,
    required String addedBy,
  }) {
    final n = members.length;
    final share = n == 0 ? amountPaise : amountPaise ~/ n;
    final shares = <String, int>{for (final m in members) m: share};
    if (n > 0) {
      final remainder = amountPaise - share * n;
      shares[members.last] = share + remainder;
    }
    return Expense(
      id: id,
      title: title,
      amountPaise: amountPaise,
      split: true,
      paidBy: paidBy,
      sharesPaise: shares,
      date: date,
      addedBy: addedBy,
    );
  }

  final String id;
  final String title;
  final int amountPaise;
  final bool split;
  final String? paidBy;
  final Map<String, int> sharesPaise;
  final DateTime date;
  final String addedBy;
  final List<ExpenseChange> changes;

  bool get isEqualSplit {
    if (sharesPaise.isEmpty) return true;
    final values = sharesPaise.values.toList();
    final n = values.length;
    var min = values.first;
    var max = values.first;
    for (final v in values) {
      if (v < min) min = v;
      if (v > max) max = v;
    }
    return max - min <= amountPaise % n;
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'amountPaise': amountPaise,
        'split': split,
        'paidBy': paidBy,
        'sharesPaise': sharesPaise,
        'date': date.toIso8601String(),
        'addedBy': addedBy,
        'changes': [
          for (final c in changes)
            {'by': c.by, 'change': c.change, 'at': c.at.toIso8601String()},
        ],
      };

  factory Expense.fromJson(Map<String, Object?> json) {
    final shares =
        (json['sharesPaise'] as Map?)?.cast<String, int>() ?? const {};
    return Expense(
      id: json['id'] as String,
      title: json['title'] as String,
      amountPaise: json['amountPaise'] as int,
      split: json['split'] as bool? ?? shares.isNotEmpty,
      paidBy: json['paidBy'] as String?,
      sharesPaise: shares,
      date: DateTime.parse(json['date'] as String),
      addedBy: json['addedBy'] as String? ?? '',
      changes: [
        for (final c in (json['changes'] as List?) ?? const [])
          ExpenseChange(
            by: (c as Map)['by'] as String,
            change: c['change'] as String,
            at: DateTime.parse(c['at'] as String),
          ),
      ],
    );
  }
}