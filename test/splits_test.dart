import 'package:flutter_test/flutter_test.dart';

import 'package:split_chat/logic/split_logic.dart';
import 'package:split_chat/models/expense.dart';
import 'package:split_chat/utils/money.dart';

void main() {
  group('Expense.equalSplit', () {
    test('splits evenly and puts leftover paise on the last member', () {
      final e = Expense.equalSplit(
        id: '1',
        title: 'Lunch',
        amountPaise: 101,
        paidBy: 'A',
        members: ['A', 'B', 'C'],
        date: DateTime(2026, 9, 20),
        addedBy: 'A',
      );

      final total = e.sharesPaise.values.fold(0, (s, v) => s + v);
      expect(total, 101);
      expect(e.sharesPaise['A'], 33);
      expect(e.sharesPaise['B'], 33);
      expect(e.sharesPaise['C'], 35);
      expect(e.isEqualSplit, isTrue);
    });

    test('single member uses the full amount', () {
      final e = Expense.equalSplit(
        id: '2',
        title: 'Snack',
        amountPaise: 500,
        paidBy: 'A',
        members: ['A'],
        date: DateTime(2026, 9, 20),
        addedBy: 'A',
      );
      expect(e.sharesPaise['A'], 500);
    });

    test('toMap/fromMap round-trips fields', () {
      final e = Expense.equalSplit(
        id: 'x',
        title: 'Dinner',
        amountPaise: 101,
        paidBy: 'A',
        members: ['A', 'B'],
        date: DateTime(2026, 9, 20, 14, 30),
        addedBy: 'A',
        ownerId: 'uid-1',
      );
      final copy = Expense.fromMap(e.toMap());
      expect(copy.id, e.id);
      expect(copy.title, e.title);
      expect(copy.amountPaise, e.amountPaise);
      expect(copy.split, e.split);
      expect(copy.paidBy, e.paidBy);
      expect(copy.sharesPaise, e.sharesPaise);
      expect(copy.addedBy, e.addedBy);
      expect(copy.ownerId, e.ownerId);
      expect(copy.date, e.date);
    });
  });

  group('Expense.split flag', () {
    test('tracking-only expense has no paidBy and no shares', () {
      final e = Expense(
        id: '1',
        title: 'Groceries',
        amountPaise: 2000,
        split: false,
        date: DateTime(2026, 9, 20),
        addedBy: 'Meera',
      );
      expect(e.split, isFalse);
      expect(e.paidBy, isNull);
      expect(e.sharesPaise, isEmpty);
    });
  });

  group('computeBalances', () {
    test('equal split: payer gains, others lose share', () {
      final b = computeBalances(
        ['A', 'B'],
        [
          Expense.equalSplit(
            id: '1',
            title: 'Lunch',
            amountPaise: 10000,
            paidBy: 'A',
            members: ['A', 'B'],
            date: DateTime(2026, 9, 20),
            addedBy: 'A',
          ),
        ],
      );
      expect(b['A'], 5000);
      expect(b['B'], -5000);
    });

    test('manual split honours custom shares', () {
      final b = computeBalances(
        ['A', 'B', 'C'],
        [
          Expense(
            id: '1',
            title: 'Dinner',
            amountPaise: 10000,
            split: true,
            paidBy: 'A',
            sharesPaise: {'A': 6000, 'B': 3000, 'C': 1000},
            date: DateTime(2026, 9, 20),
            addedBy: 'A',
          ),
        ],
      );
      expect(b['A'], 4000);
      expect(b['B'], -3000);
      expect(b['C'], -1000);
    });

    test('tracking-only expense does not affect balances', () {
      final b = computeBalances(
        ['A', 'B'],
        [
          Expense(
            id: '1',
            title: 'Groceries',
            amountPaise: 2000,
            split: false,
            date: DateTime(2026, 9, 20),
            addedBy: 'A',
          ),
        ],
      );
      expect(b['A'], 0);
      expect(b['B'], 0);
    });
  });

  group('computeSettlements', () {
    test('nets debts into a minimal set of transfers', () {
      final result = computeSettlements(
        ['A', 'B', 'C'],
        [
          Expense.equalSplit(
            id: '1',
            title: 'Trip',
            amountPaise: 30000,
            paidBy: 'A',
            members: ['A', 'B', 'C'],
            date: DateTime(2026, 9, 20),
            addedBy: 'A',
          ),
        ],
      );
      expect(result.length, 2);
      expect(result[0].from, 'B');
      expect(result[0].to, 'A');
      expect(result[0].amountPaise, 10000);
      expect(result[1].from, 'C');
      expect(result[1].to, 'A');
      expect(result[1].amountPaise, 10000);
    });

    test('no transfers when everyone is settled', () {
      final result = computeSettlements(
        ['A', 'B'],
        [
          Expense.equalSplit(
            id: '1',
            title: 'Lunch',
            amountPaise: 10000,
            paidBy: 'A',
            members: ['A', 'B'],
            date: DateTime(2026, 9, 20),
            addedBy: 'A',
          ),
          Expense.equalSplit(
            id: '2',
            title: 'Snacks',
            amountPaise: 10000,
            paidBy: 'B',
            members: ['A', 'B'],
            date: DateTime(2026, 9, 20),
            addedBy: 'A',
          ),
        ],
      );
      expect(result, isEmpty);
    });

    test('partial payments chain across debtors', () {
      final result = computeSettlements(
        ['A', 'B', 'C', 'D'],
        [
          Expense.equalSplit(
            id: '1',
            title: 'Dinner',
            amountPaise: 10000,
            paidBy: 'A',
            members: ['A', 'B', 'C', 'D'],
            date: DateTime(2026, 9, 20),
            addedBy: 'A',
          ),
          Expense.equalSplit(
            id: '2',
            title: 'Coffee',
            amountPaise: 20000,
            paidBy: 'B',
            members: ['A', 'B', 'C', 'D'],
            date: DateTime(2026, 9, 20),
            addedBy: 'A',
          ),
        ],
      );
      // Balances: A +2500, B +12500, C -7500, D -7500.
      // C pays B 7500; D pays B 5000 then A 2500.
      expect(result.length, 3);
      final total = result.fold(0, (s, r) => s + r.amountPaise);
      expect(total, 15000);
    });
  });

  group('diffExpenses', () {
    Expense base({
      required String id,
      required String title,
      required int amountPaise,
      String? paidBy,
      String date = '2026-09-20',
    }) {
      return Expense.fromMap({
        'id': id,
        'title': title,
        'amountPaise': amountPaise,
        'split': paidBy != null,
        'paidBy': paidBy,
        'sharesPaise': paidBy == null
            ? <String, int>{}
            : {'A': amountPaise ~/ 2, 'B': amountPaise - amountPaise ~/ 2},
        'date': DateTime.parse(date),
        'addedBy': 'A',
        'changes': <Map<String, dynamic>>[],
      });
    }

    test('catches title and amount changes', () {
      final d = diffExpenses(
        base(id: '1', title: 'Lunch', amountPaise: 10000, paidBy: 'A'),
        base(id: '1', title: 'Lunch + extra', amountPaise: 15000, paidBy: 'A'),
      );
      expect(d, contains('Title: “Lunch” → “Lunch + extra”'));
      expect(d, contains('Amount: ₹100.00 → ₹150.00'));
    });

    test('catches paidBy changes', () {
      final d = diffExpenses(
        base(id: '1', title: 'Lunch', amountPaise: 10000, paidBy: 'A'),
        base(id: '1', title: 'Dinner', amountPaise: 10000, paidBy: 'B'),
      );
      expect(d, contains('Paid by: A → B'));
    });

    test('reports no changes for identical expenses', () {
      expect(diffExpenses(
        base(id: '1', title: 'Lunch', amountPaise: 10000, paidBy: 'A'),
        base(id: '1', title: 'Lunch', amountPaise: 10000, paidBy: 'A'),
      ), isEmpty);
    });
  });

  group('money helpers', () {
    test('toPaise rounds fractional rupees correctly', () {
      expect(toPaise(100), 10000);
      expect(toPaise(100.5), 10050);
      expect(toPaise(0.1), 10);
      expect(toPaise(0.1 + 0.2), 30);
    });

    test('fmtPaise formats with symbol and sign', () {
      expect(fmtPaise(0), '₹0.00');
      expect(fmtPaise(10000), '₹100.00');
      expect(fmtPaise(12345), '₹123.45');
      expect(fmtPaise(-5000), '-₹50.00');
    });

    test('paiseToInput gives a two-decimal string', () {
      expect(paiseToInput(12345), '123.45');
      expect(paiseToInput(5), '0.05');
    });
  });
}