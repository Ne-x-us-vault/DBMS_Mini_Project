import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:split_chat/models/expense.dart';
import 'package:split_chat/store/app_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

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

  group('AppStore.balances', () {
    test('equal split: payer gains, others lose share', () {
      final store = AppStore()
        ..members = ['A', 'B']
        ..expenses = [
          Expense.equalSplit(
            id: '1',
            title: 'Lunch',
            amountPaise: 10000,
            paidBy: 'A',
            members: ['A', 'B'],
            date: DateTime(2026, 9, 20),
            addedBy: 'A',
          ),
        ];

      final b = store.balances();
      expect(b['A'], 5000);
      expect(b['B'], -5000);
    });

    test('manual split honours custom shares', () {
      final store = AppStore()
        ..members = ['A', 'B', 'C']
        ..expenses = [
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
        ];

      final b = store.balances();
      expect(b['A'], 4000);
      expect(b['B'], -3000);
      expect(b['C'], -1000);
      expect(store.expenses.first.isEqualSplit, isFalse);
    });

    test('tracking-only expense does not affect balances', () {
      final store = AppStore()
        ..members = ['A', 'B']
        ..expenses = [
          Expense(
            id: '1',
            title: 'Groceries',
            amountPaise: 2000,
            split: false,
            date: DateTime(2026, 9, 20),
            addedBy: 'A',
          ),
        ];

      expect(store.balances()['A'], 0);
      expect(store.balances()['B'], 0);
      expect(store.settle(), isEmpty);
    });
  });

  group('AppStore.settle', () {
    test('nets debts into a minimal set of transfers', () {
      final store = AppStore()
        ..members = ['A', 'B', 'C']
        ..expenses = [
          Expense.equalSplit(
            id: '1',
            title: 'Trip',
            amountPaise: 30000,
            paidBy: 'A',
            members: ['A', 'B', 'C'],
            date: DateTime(2026, 9, 20),
            addedBy: 'A',
          ),
        ];

      final result = store.settle();
      expect(result.length, 2);
      expect(result[0].from, 'B');
      expect(result[0].to, 'A');
      expect(result[0].amountPaise, 10000);
      expect(result[1].from, 'C');
      expect(result[1].to, 'A');
      expect(result[1].amountPaise, 10000);
    });

    test('no transfers when everyone is settled', () {
      final store = AppStore()
        ..members = ['A', 'B']
        ..expenses = [
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
        ];

      expect(store.settle(), isEmpty);
    });
  });

  group('AppStore history', () {
    test('adding an expense logs who added it', () {
      final store = AppStore();
      store.addExpense(
        Expense.equalSplit(
          id: '1',
          title: 'Lunch',
          amountPaise: 10000,
          paidBy: 'A',
          members: ['A', 'B'],
          date: DateTime(2026, 9, 20),
          addedBy: 'Meera',
        ),
      );

      expect(store.activity.length, 1);
      expect(store.activity.first.by, 'Meera');
      expect(store.activity.first.verb, 'added');
    });

    test('editing records the diff and who edited', () {
      final store = AppStore();
      final original = Expense.equalSplit(
        id: '1',
        title: 'Lunch',
        amountPaise: 10000,
        paidBy: 'A',
        members: ['A', 'B'],
        date: DateTime(2026, 9, 20),
        addedBy: 'A',
      );
      store.addExpense(original);

      final edited = Expense.equalSplit(
        id: '1',
        title: 'Lunch + extra',
        amountPaise: 15000,
        paidBy: 'A',
        members: ['A', 'B'],
        date: DateTime(2026, 9, 20),
        addedBy: 'A',
      );
      store.currentUser = 'B';
      store.replaceExpense(edited);

      final saved = store.expenses.first;
      expect(saved.changes.length, 3); // title, amount, shares
      expect(saved.changes.every((c) => c.by == 'B'), isTrue);
      expect(
        saved.changes.map((c) => c.change),
        contains('Title: “Lunch” → “Lunch + extra”'),
      );
      expect(store.activity.first.verb, 'edited');
      expect(store.activity.first.by, 'B');
    });

    test('deleting an expense leaves an activity record', () {
      final store = AppStore()
        ..members = ['A', 'B']
        ..expenses = [
          Expense.equalSplit(
            id: '1',
            title: 'Lunch',
            amountPaise: 10000,
            paidBy: 'A',
            members: ['A', 'B'],
            date: DateTime(2026, 9, 20),
            addedBy: 'A',
          ),
        ];

      store.currentUser = 'B';
      store.removeExpense('1');

      expect(store.expenses, isEmpty);
      expect(store.activity.first.verb, 'deleted');
      expect(store.activity.first.by, 'B');
      expect(store.activity.first.title, 'Lunch');
    });
  });
}