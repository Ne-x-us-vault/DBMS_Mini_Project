import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:split_chat/logic/split_logic.dart';
import 'package:split_chat/models/expense.dart';
import 'package:split_chat/services/local_session.dart';
import 'package:split_chat/store/app_store.dart';
import 'package:split_chat/utils/money.dart';

import 'fake_group_repository.dart';

Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 1));

AppStore makeStore(InMemoryGroupRepository repo, String managingAs) {
  final local = LocalSession()..managingAs = managingAs;
  final store = AppStore(repo: repo, session: local, groupId: repo.group!.id);
  store.init();
  return store;
}

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

    test('toMap/fromMap round-trips fields', () {
      final e = Expense.equalSplit(
        id: 'x',
        title: 'Dinner',
        amountPaise: 101,
        paidBy: 'A',
        members: ['A', 'B'],
        date: DateTime(2026, 9, 20, 14, 30),
        addedBy: 'A',
      );
      final copy = Expense.fromMap(e.toMap());
      expect(copy.id, e.id);
      expect(copy.title, e.title);
      expect(copy.amountPaise, e.amountPaise);
      expect(copy.split, e.split);
      expect(copy.paidBy, e.paidBy);
      expect(copy.sharesPaise, e.sharesPaise);
      expect(copy.addedBy, e.addedBy);
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

  group('stripMemberFromShares', () {
    test('removes the member from shares only in split expenses', () {
      final e = Expense.equalSplit(
        id: '1',
        title: 'Lunch',
        amountPaise: 3000,
        paidBy: 'A',
        members: ['A', 'B'],
        date: DateTime(2026, 9, 20),
        addedBy: 'A',
      );
      final stripped = stripMemberFromShares(e, 'B');
      expect(stripped.sharesPaise, {'A': 1500});
      expect(stripped.title, e.title);
      expect(stripped.amountPaise, e.amountPaise);
    });

    test('tracking-only expenses are returned unchanged', () {
      final e = Expense(
        id: '1',
        title: 'Groceries',
        amountPaise: 2000,
        split: false,
        date: DateTime(2026, 9, 20),
        addedBy: 'A',
      );
      expect(stripMemberFromShares(e, 'B').sharesPaise, isEmpty);
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
  });

  group('diffExpenses', () {
    Expense base({
      required String id,
      required String title,
      required int amountPaise,
      String? paidBy,
    }) {
      return Expense.fromMap({
        'id': id,
        'title': title,
        'amountPaise': amountPaise,
        'split': paidBy != null,
        'paidBy': paidBy,
        'sharesPaise':
            paidBy == null ? <String, int>{} : {'A': amountPaise ~/ 2, 'B': amountPaise - amountPaise ~/ 2},
        'date': DateTime(2026, 9, 20),
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
        base(id: '1', title: 'Lunch', amountPaise: 10000, paidBy: 'B'),
      );
      expect(d, contains('Paid by: A → B'));
    });

    test('reports no changes for identical expenses', () {
      expect(
        diffExpenses(
          base(id: '1', title: 'Lunch', amountPaise: 10000, paidBy: 'A'),
          base(id: '1', title: 'Lunch', amountPaise: 10000, paidBy: 'A'),
        ),
        isEmpty,
      );
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

  group('AppStore with in-memory repository', () {
    late InMemoryGroupRepository repo;
    late AppStore store;

    setUp(() async {
      repo = InMemoryGroupRepository();
      await repo.createGroup(name: 'Roommates', member: 'Aarav');
      await repo.setMembers(repo.group!.id, ['Aarav', 'Meera']);
      store = makeStore(repo, 'Aarav');
      await pump();
    });

    test('streams load members and no expenses', () {
      expect(store.members, ['Aarav', 'Meera']);
      expect(store.expenses, isEmpty);
      expect(store.ready, isTrue);
    });

    test('addExpense stamps the managing-as name and logs added activity',
        () async {
      await store.addExpense(
        Expense.equalSplit(
          id: 'e1',
          title: 'Lunch',
          amountPaise: 10000,
          paidBy: 'Aarav',
          members: ['Aarav', 'Meera'],
          date: DateTime(2026, 9, 20),
          addedBy: 'Whoever',
        ),
      );
      await pump();
      expect(store.expenses.single.addedBy, 'Aarav');
      expect(store.activity.single.verb, 'added');
      expect(store.activity.single.by, 'Aarav');
      expect(store.activity.single.amountPaise, 10000);
    });

    test('balances() and settle() use the live expenses', () async {
      await store.addExpense(
        Expense.equalSplit(
          id: 'e1',
          title: 'Lunch',
          amountPaise: 10000,
          paidBy: 'Aarav',
          members: ['Aarav', 'Meera'],
          date: DateTime(2026, 9, 20),
          addedBy: 'Aarav',
        ),
      );
      await pump();
      expect(store.balances()['Aarav'], 5000);
      expect(store.balances()['Meera'], -5000);
      expect(store.settle().single, isA<Settlement>());
    });

    test('replaceExpense appends history stamped with the editor', () async {
      await store.addExpense(
        Expense.equalSplit(
          id: 'e1',
          title: 'Lunch',
          amountPaise: 10000,
          paidBy: 'Aarav',
          members: ['Aarav', 'Meera'],
          date: DateTime(2026, 9, 20),
          addedBy: 'Aarav',
        ),
      );
      await pump();

      store.setManagingAs('Meera');
      await store.replaceExpense(
        Expense.equalSplit(
          id: 'e1',
          title: 'Lunch + extra',
          amountPaise: 15000,
          paidBy: 'Aarav',
          members: ['Aarav', 'Meera'],
          date: DateTime(2026, 9, 20),
          addedBy: 'Aarav',
        ),
      );
      await pump();

      final saved = store.expenses.single;
      expect(saved.changes, isNotEmpty);
      expect(saved.changes.every((c) => c.by == 'Meera'), isTrue);
      expect(
        saved.changes.map((c) => c.change),
        contains('Title: “Lunch” → “Lunch + extra”'),
      );
      expect(store.activity.first.verb, 'edited');
      expect(store.activity.first.by, 'Meera');
    });

    test('removeExpense logs deleted activity with the acting name', () async {
      await store.addExpense(
        Expense.equalSplit(
          id: 'e1',
          title: 'Lunch',
          amountPaise: 10000,
          paidBy: 'Aarav',
          members: ['Aarav', 'Meera'],
          date: DateTime(2026, 9, 20),
          addedBy: 'Aarav',
        ),
      );
      await pump();

      store.setManagingAs('Meera');
      await store.removeExpense(store.expenses.single);
      await pump();

      expect(store.expenses, isEmpty);
      expect(store.activity.first.verb, 'deleted');
      expect(store.activity.first.by, 'Meera');
      expect(store.activity.first.title, 'Lunch');
    });

    test('removeMember updates members and strips shares in one batch',
        () async {
      await store.addExpense(
        Expense.equalSplit(
          id: 'e1',
          title: 'Lunch',
          amountPaise: 3000,
          paidBy: 'Aarav',
          members: ['Aarav', 'Meera'],
          date: DateTime(2026, 9, 20),
          addedBy: 'Aarav',
        ),
      );
      await pump();

      await store.removeMember('Meera');
      await pump();

      expect(store.members, ['Aarav']);
      expect(store.expenses.single.sharesPaise, {'Aarav': 1500});
    });

    test('sendMessage stamps senderName and messages come oldest-first',
        () async {
      await store.sendMessage('Hello');
      await store.sendMessage('World');
      await pump();

      expect(store.messages.length, 2);
      expect(store.messages.first.senderName, 'Aarav');
      expect(store.messages.first.text, 'Hello');
      expect(store.messages.last.text, 'World');
      expect(
        store.messages.every((m) => m.senderName == store.managingAs),
        isTrue,
      );
    });
  });

  group('memberships', () {
    late InMemoryGroupRepository repo;

    setUp(() => repo = InMemoryGroupRepository());

    test('createGroup records a membership and myGroups lists it', () async {
      await repo.createGroup(name: 'Roommates', member: 'Aarav');
      final list = await repo.myGroups().first;
      expect(list.length, 1);
      expect(list.single.id, repo.group!.id);
      expect(list.single.name, 'Roommates');
      expect(list.single.members, contains('Aarav'));
    });

    test('joinGroup adds the acting name and the membership appears',
        () async {
      final g = await repo.createGroup(name: 'Roommates', member: 'Aarav');
      final joined = await repo.joinGroup(g.id, name: 'Zara');
      expect(joined.members, containsAll(['Aarav', 'Zara']));
      final list = await repo.myGroups().first;
      expect(list.single.members, containsAll(['Aarav', 'Zara']));
    });

    test('joinGroup with an existing name does not duplicate it', () async {
      final g = await repo.createGroup(name: 'Roommates', member: 'Aarav');
      final joined = await repo.joinGroup(g.id, name: 'Aarav');
      final count = joined.members.where((m) => m == 'Aarav').length;
      expect(count, 1);
    });

    test('joinGroup for an unknown code throws', () async {
      await repo.createGroup(name: 'Roommates', member: 'Aarav');
      await expectLater(
        repo.joinGroup('nope', name: 'Aarav'),
        throwsA(isA<Exception>()),
      );
    });

    test('addMember is unique case-insensitively', () async {
      await repo.createGroup(name: 'Roommates', member: 'Aarav');
      final store = makeStore(repo, 'Aarav');
      await pump();
      await store.addMember('MEERA');
      await pump();
      expect(repo.group!.members, contains('MEERA'));
      await store.addMember('Meera');
      await pump();
      expect(
        repo.group!.members.where((m) => m.toLowerCase() == 'meera').length,
        1,
      );
    });

    test('leaveGroup removes the membership and strips the shares', () async {
      final g = await repo.createGroup(name: 'Roommates', member: 'Aarav');
      await repo.joinGroup(g.id, name: 'Zara');
      await repo.setMembers(g.id, ['Aarav', 'Zara']);
      await repo.addExpense(
        g.id,
        Expense.equalSplit(
          id: 'e1',
          title: 'Lunch',
          amountPaise: 10000,
          paidBy: 'Aarav',
          members: ['Aarav', 'Zara'],
          date: DateTime(2026, 9, 20),
          addedBy: 'Aarav',
        ),
      );

      await repo.leaveGroup(g.id, name: 'Zara');

      final list = await repo.myGroups().first;
      expect(list, isEmpty);
      expect(repo.group!.members, ['Aarav']);
      final expenses = await repo.watchExpenses(g.id).first;
      expect(expenses.single.sharesPaise, {'Aarav': 5000});
    });
  });

  group('aggregate queries', () {
    late InMemoryGroupRepository repo;
    String gid = '';

    setUp(() async {
      repo = InMemoryGroupRepository();
      final g = await repo.createGroup(name: 'Roommates', member: 'Aarav');
      gid = g.id;
      await repo.setMembers(gid, ['Aarav', 'Meera']);
      await repo.addExpense(
        gid,
        Expense.equalSplit(
          id: 'e1',
          title: 'Lunch',
          amountPaise: 10000,
          paidBy: 'Aarav',
          members: ['Aarav', 'Meera'],
          date: DateTime(2026, 9, 10),
          addedBy: 'Aarav',
        ),
      );
      await repo.addExpense(
        gid,
        Expense.equalSplit(
          id: 'e2',
          title: 'Dinner',
          amountPaise: 5000,
          paidBy: 'Meera',
          members: ['Aarav', 'Meera'],
          date: DateTime(2026, 9, 20),
          addedBy: 'Meera',
        ),
      );
    });

    test('expenseCount and totalTrackedPaise sum the collection', () async {
      expect(await repo.expenseCount(gid), 2);
      expect(await repo.totalTrackedPaise(gid), 15000);
    });

    test('expenseCountBetween filters by date range', () async {
      expect(
        await repo.expenseCountBetween(
          gid,
          from: DateTime(2026, 9, 1),
          to: DateTime(2026, 9, 11),
        ),
        1,
      );
      expect(
        await repo.expenseCountBetween(
          gid,
          from: DateTime(2026, 9, 1),
          to: DateTime(2026, 9, 21),
        ),
        2,
      );
      expect(
        await repo.expenseCountBetween(
          gid,
          from: DateTime(2026, 10, 1),
          to: DateTime(2026, 10, 31),
        ),
        0,
      );
    });

    test('perMemberPaid groups by paidBy', () async {
      expect(await repo.perMemberPaid(gid), {'Aarav': 10000, 'Meera': 5000});
    });
  });
}