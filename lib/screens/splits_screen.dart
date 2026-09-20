import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../logic/split_logic.dart';
import '../models/expense.dart';
import '../store/app_store.dart';
import '../utils/money.dart';
import 'admin_panel_screen.dart';

class SplitsScreen extends StatelessWidget {
  const SplitsScreen({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => _SplitsView(store: store),
    );
  }
}

class _SplitsView extends StatelessWidget {
  const _SplitsView({required this.store});

  final AppStore store;

  String _shortDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]}';
  }

  String _dateLine(DateTime d) => '${d.day}/${d.month}/${d.year}';

  Future<void> _addExpense(BuildContext context) async {
    if (store.members.isEmpty) {
      _toast(context, 'No users yet. Someone must sign up first.');
      return;
    }
    final e = await showExpenseDialog(context, store: store);
    if (e != null) store.addExpense(e);
  }

  Future<void> _editExpense(BuildContext context, Expense e) async {
    if (!store.canEdit(e)) return;
    final edited = await showExpenseDialog(context, store: store, existing: e);
    if (edited != null) store.replaceExpense(edited);
  }

  Future<void> _confirmDelete(BuildContext context, Expense e) async {
    if (!store.canDelete(e)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete expense?'),
        content: Text('“${e.title}” (${fmtPaise(e.amountPaise)}) will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) store.removeExpense(e.id);
  }

  Future<void> _clearHistory(BuildContext context) async {
    if (store.activity.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text(
            'The activity log will be emptied. Expenses themselves stay untouched.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok == true) store.clearActivity();
  }

  void _openDetail(BuildContext context, Expense e) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            0,
            24,
            24 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: _ExpenseDetailSheet(
            expense: e,
            canEdit: store.canEdit(e),
            dateOf: _dateLine,
            onEdit: () => _editExpense(context, e),
            onDelete: () {
              Navigator.pop(ctx);
              _confirmDelete(context, e);
            },
          ),
        ),
      ),
    );
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final users = store.users;
    final expenses = store.expenses;
    final balances = computeBalances(store.members, expenses);
    final settlements = computeSettlements(store.members, expenses);
    final totalPaise = expenses.fold(0, (sum, e) => sum + e.amountPaise);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shared expenses'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Account',
            icon: const Icon(Icons.account_circle_outlined),
            onSelected: (v) {
              switch (v) {
                case 'admin':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AdminPanelScreen(store: store),
                    ),
                  );
                case 'signout':
                  FirebaseAuth.instance.signOut();
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                enabled: false,
                child: Text(
                  '${store.myName} · ${store.isAdmin ? 'Admin' : 'Member'}',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ),
              const PopupMenuItem(
                value: 'admin',
                child: Text('Manage users & roles'),
              ),
              const PopupMenuItem(value: 'signout', child: Text('Sign out')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeader(
            title: 'Expenses (${expenses.length})',
            icon: Icons.add_circle_outline,
            tooltip: 'Add expense',
            onTap: () => _addExpense(context),
          ),
          const SizedBox(height: 4),
          Text(
            'Total tracked: ${fmtPaise(totalPaise)}',
            style: TextStyle(color: theme.colorScheme.outline, fontSize: 12),
          ),
          const SizedBox(height: 8),
          if (expenses.isEmpty)
            _EmptyCard(text: 'No expenses yet. Tap + to add one.')
          else
            for (final e in expenses)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(
                    e.split ? Icons.receipt_long : Icons.receipt,
                    color: e.split
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                  ),
                  title: Text(e.title),
                  subtitle: Text(
                    e.split
                        ? '${e.paidBy ?? '?'} paid · ${_shortDate(e.date)}'
                        : 'Tracking only · ${_shortDate(e.date)}',
                  ),
                  onTap: () => _openDetail(context, e),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        fmtPaise(e.amountPaise),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      if (store.canEdit(e))
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert, size: 20),
                          onSelected: (v) => v == 'delete'
                              ? _confirmDelete(context, e)
                              : _editExpense(context, e),
                          itemBuilder: (ctx) => const [
                            PopupMenuItem(value: 'edit', child: Text('Edit')),
                            PopupMenuItem(
                                value: 'delete', child: Text('Delete')),
                          ],
                        )
                      else
                        const SizedBox(width: 48),
                    ],
                  ),
                ),
              ),
          const SizedBox(height: 24),
          Card(
            clipBehavior: Clip.antiAlias,
            margin: EdgeInsets.zero,
            child: ExpansionTile(
              title: const Text(
                'History',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                store.activity.isEmpty
                    ? 'No activity yet'
                    : '${store.activity.length} event${store.activity.length == 1 ? '' : 's'}',
                style:
                    TextStyle(color: theme.colorScheme.outline, fontSize: 12),
              ),
              children: [
                if (store.activity.isNotEmpty && store.isAdmin)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => _clearHistory(context),
                        icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                        label: const Text('Clear history'),
                      ),
                    ),
                  ),
                if (store.activity.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Add an expense to get started.',
                      style: TextStyle(color: theme.colorScheme.outline),
                    ),
                  )
                else
                  Column(
                    children: [
                      for (final a in store.activity)
                        ListTile(
                          dense: true,
                          leading: Icon(
                            a.verb == 'added'
                                ? Icons.add_circle_outline
                                : a.verb == 'deleted'
                                    ? Icons.delete_outline
                                    : Icons.edit_outlined,
                            color: a.verb == 'added'
                                ? Colors.green
                                : a.verb == 'deleted'
                                    ? Colors.red
                                    : Colors.amber.shade800,
                          ),
                          title: Text('${a.by} ${a.verb} “${a.title}”'),
                          subtitle: Text(
                            '${a.amountPaise != null ? '${fmtPaise(a.amountPaise!)} · ' : ''}${_shortDate(a.at)}',
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _SectionHeader(
            title: 'People (${users.length})',
            icon: null,
            tooltip: null,
            onTap: null,
          ),
          const SizedBox(height: 8),
          if (users.isEmpty)
            _EmptyCard(text: 'No users yet. Share the app to sign up.')
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final u in users)
                  Chip(
                    avatar: CircleAvatar(child: Text(u.name[0].toUpperCase())),
                    label: Text(
                      u.isAdmin ? '${u.name} (admin)' : u.name,
                    ),
                    onDeleted:
                        store.isAdmin && u.uid != store.myUid
                            ? () => _removeUser(context, u)
                            : null,
                  ),
              ],
            ),
          const SizedBox(height: 24),
          _SectionHeader(
            title: 'Balances (from split expenses)',
            icon: null,
            tooltip: null,
            onTap: null,
          ),
          const SizedBox(height: 8),
          if (users.isEmpty)
            _EmptyCard(text: 'Add people to see balances.')
          else
            Card(
              child: Column(
                children: [
                  for (final m in store.members)
                    ListTile(
                      dense: true,
                      title: Text(m),
                      trailing: Text(
                        fmtPaise(balances[m] ?? 0),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: (balances[m] ?? 0) > 0
                              ? Colors.green
                              : (balances[m] ?? 0) < 0
                                  ? Colors.red
                                  : theme.colorScheme.outline,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 24),
          _SectionHeader(
            title: 'Who owes whom',
            icon: null,
            tooltip: null,
            onTap: null,
          ),
          const SizedBox(height: 8),
          if (settlements.isEmpty)
            _EmptyCard(text: 'All settled up!')
          else
            Card(
              child: Column(
                children: [
                  for (final s in settlements)
                    ListTile(
                      leading: const Icon(Icons.currency_rupee),
                      title: Text('${s.from} pays ${s.to}'),
                      trailing: Text(
                        fmtPaise(s.amountPaise),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _removeUser(BuildContext context, dynamic u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove user?'),
        content: Text(
          '${u.name} will no longer be a group member. Their expenses stay in the history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) store.removeUser(u.uid);
  }
}

class _ExpenseDetailSheet extends StatelessWidget {
  const _ExpenseDetailSheet({
    required this.expense,
    required this.canEdit,
    required this.dateOf,
    required this.onEdit,
    required this.onDelete,
  });

  final Expense expense;
  final bool canEdit;
  final String Function(DateTime) dateOf;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = expense;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(e.title, style: theme.textTheme.titleLarge),
            Text(
              fmtPaise(e.amountPaise),
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _MetaChip(
              icon: e.split ? Icons.group : Icons.receipt_long,
              label: e.split ? 'Split · paid by ${e.paidBy}' : 'Tracking only',
            ),
            _MetaChip(icon: Icons.event, label: dateOf(e.date)),
            _MetaChip(icon: Icons.person_add_alt, label: 'Added by ${e.addedBy}'),
          ],
        ),
        const SizedBox(height: 12),
        if (e.split)
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (final entry in e.sharesPaise.entries)
                  ListTile(
                    dense: true,
                    title: Text(entry.key),
                    trailing: Text(
                      fmtPaise(entry.value),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          )
        else
          Text(
            'This expense only tracks spending — no money was split.',
            style: TextStyle(
              color: theme.colorScheme.outline,
              fontSize: 12,
            ),
          ),
        if (canEdit) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                ),
              ),
            ],
          ),
        ],
        const Divider(height: 24),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text(
            'History',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            '${1 + e.changes.length} event${1 + e.changes.length == 1 ? '' : 's'}',
            style: TextStyle(
              color: theme.colorScheme.outline,
              fontSize: 12,
            ),
          ),
          children: [
            _HistoryLine(
              by: e.addedBy,
              change: 'Added expense',
              at: e.date,
              dateOf: dateOf,
            ),
            for (final c in e.changes)
              _HistoryLine(by: c.by, change: c.change, at: c.at, dateOf: dateOf),
          ],
        ),
      ],
    );
  }
}

class _HistoryLine extends StatelessWidget {
  const _HistoryLine({
    required this.by,
    required this.change,
    required this.at,
    required this.dateOf,
  });

  final String by;
  final String change;
  final DateTime at;
  final String Function(DateTime) dateOf;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            child: Text(by.isEmpty ? '?' : by[0].toUpperCase()),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(by, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(change),
                Text(
                  dateOf(at),
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final String title;
  final IconData? icon;
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        if (icon != null && onTap != null)
          IconButton(icon: Icon(icon), tooltip: tooltip, onPressed: onTap),
      ],
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          text,
          style: TextStyle(color: Theme.of(context).colorScheme.outline),
        ),
      ),
    );
  }
}

Future<Expense?> showExpenseDialog(
  BuildContext context, {
  required AppStore store,
  Expense? existing,
}) async {
  final members = store.members;
  final titleController = TextEditingController(text: existing?.title ?? '');
  final amountController = TextEditingController(
    text: existing == null ? '' : paiseToInput(existing.amountPaise),
  );
  var date = existing?.date ?? DateTime.now();
  var split = existing?.split ?? true;
  var paidBy = existing?.paidBy ?? (members.isNotEmpty ? members.first : null);
  if (paidBy == null || !members.contains(paidBy)) {
    paidBy = members.isNotEmpty ? members.first : null;
  }
  var mode = existing == null || existing.isEqualSplit ? 0 : 1;

  final shareControllers = <String, TextEditingController>{
    for (final m in members)
      m: TextEditingController(
        text: existing == null ? '' : paiseToInput(existing.sharesPaise[m] ?? 0),
      ),
  };

  final result = await showDialog<Expense>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final amountPaise = toPaise(double.tryParse(amountController.text) ?? 0);
        final net = members.fold(
          0,
          (sum, m) => sum + toPaise(double.tryParse(shareControllers[m]!.text) ?? 0),
        );
        final manualOK = !split || mode == 0 || net == amountPaise;
        final valid = amountPaise > 0 &&
            titleController.text.trim().isNotEmpty &&
            manualOK &&
            members.isNotEmpty &&
            (!split || paidBy != null);

        return AlertDialog(
          title: Text(existing == null ? 'Add expense' : 'Edit expense'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'What for?',
                      hintText: 'e.g. Lunch',
                    ),
                  ),
                  TextField(
                    controller: amountController,
                    decoration: const InputDecoration(
                      labelText: 'Amount',
                      prefixText: '₹ ',
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => setLocal(() {}),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event),
                    title: Text('Date: ${date.day}/${date.month}/${date.year}'),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: date,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) setLocal(() => date = picked);
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Split this expense'),
                    subtitle: const Text('Share the cost among people'),
                    value: split,
                    onChanged: (v) => setLocal(() => split = v),
                  ),
                  if (split) ...[
                    DropdownButtonFormField<String>(
                      initialValue: paidBy,
                      decoration: const InputDecoration(labelText: 'Paid by'),
                      items: [
                        for (final m in members)
                          DropdownMenuItem(value: m, child: Text(m)),
                      ],
                      onChanged: (v) => setLocal(() => paidBy = v),
                    ),
                    const Divider(),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 0, label: Text('Split equally')),
                        ButtonSegment(value: 1, label: Text('Manual')),
                      ],
                      selected: {mode},
                      onSelectionChanged: (s) {
                        final newMode = s.first;
                        setLocal(() {
                          mode = newMode;
                          if (newMode == 1) {
                            for (final m in members) {
                              final v = toPaise(
                                    double.tryParse(amountController.text) ?? 0,
                                  ) ~/
                                  members.length;
                              shareControllers[m]!.text = paiseToInput(v);
                            }
                          } else {
                            for (final c in shareControllers.values) {
                              c.clear();
                            }
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    if (mode == 1)
                      for (final m in members)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: TextField(
                            controller: shareControllers[m],
                            decoration: InputDecoration(
                              labelText: '$m pays',
                              prefixText: '₹ ',
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setLocal(() {}),
                          ),
                        ),
                    if (mode == 1 && !manualOK)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Shares add up to ${fmtPaise(net)}, but the bill is ${fmtPaise(amountPaise)}.',
                          style: TextStyle(
                            color: Theme.of(ctx).colorScheme.error,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ] else
                    Text(
                      'Just tracking this expense — no money split.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(ctx).colorScheme.outline,
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: valid
                  ? () {
                      final id = existing?.id ??
                          DateTime.now().microsecondsSinceEpoch.toString();
                      final baseTitle = titleController.text.trim();
                      final addedBy = existing?.addedBy ?? store.myName;
                      Expense exp;
                      if (!split) {
                        exp = Expense(
                          id: id,
                          title: baseTitle,
                          amountPaise: amountPaise,
                          split: false,
                          date: date,
                          addedBy: addedBy,
                        );
                      } else if (mode == 0) {
                        exp = Expense.equalSplit(
                          id: id,
                          title: baseTitle,
                          amountPaise: amountPaise,
                          paidBy: paidBy!,
                          members: members,
                          date: date,
                          addedBy: addedBy,
                        );
                      } else {
                        exp = Expense(
                          id: id,
                          title: baseTitle,
                          amountPaise: amountPaise,
                          split: true,
                          paidBy: paidBy,
                          sharesPaise: {
                            for (final m in members)
                              m: toPaise(
                                double.tryParse(shareControllers[m]!.text) ?? 0,
                              ),
                          },
                          date: date,
                          addedBy: addedBy,
                        );
                      }
                      Navigator.pop(ctx, exp);
                    }
                  : null,
              child: Text(existing == null ? 'Add' : 'Save'),
            ),
          ],
        );
      },
    ),
  );

  titleController.dispose();
  amountController.dispose();
  for (final c in shareControllers.values) {
    c.dispose();
  }
  return result;
}