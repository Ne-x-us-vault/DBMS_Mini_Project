class ExpenseChange {
  const ExpenseChange({required this.by, required this.change, required this.at});

  final String by;
  final String change;
  final DateTime at;

  Map<String, Object?> toMap() => {'by': by, 'change': change, 'at': at};

  factory ExpenseChange.fromMap(Map<String, dynamic> map) => ExpenseChange(
        by: map['by'] as String? ?? '',
        change: map['change'] as String? ?? '',
        at: _toDateTime(map['at']),
      );
}

DateTime _toDateTime(Object? v) {
  if (v is DateTime) return v;
  if (v is String) return DateTime.parse(v).toLocal();
  return DateTime.fromMillisecondsSinceEpoch(0);
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
    this.ownerId = '',
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
    String ownerId = '',
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
      ownerId: ownerId,
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

  /// Firebase Auth uid of the user who created this expense.
  final String ownerId;
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

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'amountPaise': amountPaise,
        'split': split,
        'paidBy': paidBy,
        'sharesPaise': sharesPaise,
        'date': date,
        'addedBy': addedBy,
        'ownerId': ownerId,
        'changes': [for (final c in changes) c.toMap()],
      };

  factory Expense.fromMap(Map<String, dynamic> map) {
    final shares =
        (map['sharesPaise'] as Map?)?.cast<String, int>() ?? const {};
    return Expense(
      id: map['id'] as String,
      title: map['title'] as String? ?? '',
      amountPaise: (map['amountPaise'] as num?)?.toInt() ?? 0,
      split: map['split'] as bool? ?? shares.isNotEmpty,
      paidBy: map['paidBy'] as String?,
      sharesPaise: shares,
      date: _toDateTime(map['date']),
      addedBy: map['addedBy'] as String? ?? '',
      ownerId: map['ownerId'] as String? ?? '',
      changes: [
        for (final c in (map['changes'] as List?) ?? const [])
          ExpenseChange.fromMap((c as Map).cast<String, dynamic>()),
      ],
    );
  }
}