import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/auth_repository.dart';
import '../services/group_repository.dart';
import '../utils/money.dart';

/// Account screen: identity, join date, and per-group stats served by the
/// repository's *aggregate queries* (Firestore `COUNT`/`SUM`).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.user,
    required this.repository,
    required this.auth,
  });

  final AuthUser user;
  final GroupRepository repository;
  final AuthRepository auth;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<GroupInfo> _groups = const [];
  final Map<String, int> _expenseCounts = {};
  final Map<String, int> _totals = {};
  final Map<String, int> _myPaid = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final groups = await widget.repository.myGroups().first;
      final stats = <String, (int, int, int)>{};
      await Future.wait(groups.map((g) async {
        final count = await widget.repository.expenseCount(g.id);
        final total = await widget.repository.totalTrackedPaise(g.id);
        final paid = await widget.repository.perMemberPaid(g.id);
        stats[g.id] = (count, total, paid[widget.user.displayName] ?? 0);
      }));
      if (!mounted) return;
      setState(() {
        _groups = groups;
        for (final e in stats.entries) {
          _expenseCounts[e.key] = e.value.$1;
          _totals[e.key] = e.value.$2;
          _myPaid[e.key] = e.value.$3;
        }
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _logOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You’ll need your email and password to log back in.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.auth.signOut();
    }
  }

  String _joinDate() {
    final t = widget.user.createdAt;
    if (t == null) return '';
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[t.month - 1]} ${t.day}, ${t.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        child: Text(
                          widget.user.displayName.isEmpty
                              ? '?'
                              : widget.user.displayName[0].toUpperCase(),
                          style: theme.textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.user.displayName.isEmpty
                                  ? '(no name)'
                                  : widget.user.displayName,
                              style: theme.textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            if (widget.user.email != null)
                              Text(
                                widget.user.email!,
                                style: TextStyle(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_joinDate().isNotEmpty)
                    Text(
                      'Account created ${_joinDate()}',
                      style: TextStyle(color: theme.colorScheme.outline),
                    ),
                  const SizedBox(height: 24),
                  Text(
                    'My groups · ${_groups.length}',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (_groups.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'You haven’t joined any groups yet — create or join '
                        'one from Home.',
                        style: TextStyle(color: theme.colorScheme.outline),
                      ),
                    )
                  else
                    for (final g in _groups)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Text(
                              g.name.isEmpty ? '?' : g.name[0].toUpperCase(),
                            ),
                          ),
                          title: Text(g.name),
                          subtitle: Text(
                            '${g.members.length} member'
                            '${g.members.length == 1 ? '' : 's'} · '
                            '${_expenseCounts[g.id] ?? 0} expense'
                            '${(_expenseCounts[g.id] ?? 0) == 1 ? '' : 's'} · '
                            'tracked ${fmtPaise(_totals[g.id] ?? 0)}',
                          ),
                          trailing: (_myPaid[g.id] ?? 0) > 0
                              ? Text(
                                  'you paid ${fmtPaise(_myPaid[g.id]!)}',
                                  style: TextStyle(
                                    color: theme.colorScheme.primary,
                                    fontSize: 12,
                                  ),
                                )
                              : null,
                        ),
                      ),
                  const SizedBox(height: 32),
                  OutlinedButton.icon(
                    onPressed: _logOut,
                    icon: const Icon(Icons.logout),
                    label: const Text('Log out'),
                  ),
                ],
              ),
      ),
    );
  }
}