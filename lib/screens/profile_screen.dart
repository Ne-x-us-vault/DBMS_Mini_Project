import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/models.dart';
import '../services/auth_repository.dart';
import '../services/group_repository.dart';
import '../theme/app_theme.dart';
import '../utils/money.dart';
import '../widgets/group_avatar.dart';

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
      // The auth stream swaps the root for the login screen; pop the pushed
      // Account route so we actually see it instead of a stale stack.
      if (mounted) {
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
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
                  _AccountCard(
                    user: widget.user,
                    joinDate: _joinDate(),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Text(
                        'My groups',
                        style: GoogleFonts.manrope(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppPalette.ink,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppPalette.goldSoft,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${_groups.length}',
                          style: GoogleFonts.manrope(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppPalette.gold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_groups.isEmpty)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          'You haven’t joined any groups yet — create or join '
                          'one from Home.',
                          style: GoogleFonts.manrope(
                            fontSize: 13.5,
                            height: 1.5,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  else
                    for (final g in _groups)
                      Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          leading: GroupAvatar(name: g.name, size: 44),
                          title: Text(
                            g.name,
                            style: GoogleFonts.manrope(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                              color: AppPalette.ink,
                            ),
                          ),
                          subtitle: const SizedBox(height: 2),
                          isThreeLine: true,
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const SizedBox(height: 18),
                              if ((_myPaid[g.id] ?? 0) == 0)
                                Text(
                                  'no payments yet',
                                  style: GoogleFonts.manrope(
                                    fontSize: 11,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                )
                              else
                                MoneyText(
                                  'you paid ${fmtPaise(_myPaid[g.id]!)}',
                                  size: 15,
                                  color: AppPalette.gold,
                                ),
                            ],
                          ),
                          onTap: () {
                            ScaffoldMessenger.of(context)
                              ..clearSnackBars()
                              ..showSnackBar(SnackBar(
                                content: Text(
                                  '${g.members.length} member'
                                  '${g.members.length == 1 ? '' : 's'} · '
                                  '${_expenseCounts[g.id] ?? 0} expense'
                                  '${(_expenseCounts[g.id] ?? 0) == 1 ? '' : 's'}'
                                  ' · tracked ${fmtPaise(_totals[g.id] ?? 0)}',
                                ),
                              ));
                          },
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

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.user, required this.joinDate});

  final AuthUser user;
  final String joinDate;

  @override
  Widget build(BuildContext context) {
    final letter =
        user.displayName.isEmpty ? '?' : user.displayName[0].toUpperCase();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppPalette.forest, AppPalette.moss],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x221B4332),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
            child: Text(
              letter,
              style: GoogleFonts.fraunces(
                fontSize: 26,
                fontWeight: FontWeight.w600,
                fontStyle: FontStyle.italic,
                color: AppPalette.goldSoft,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayName.isEmpty ? '(no name)' : user.displayName,
                  style: GoogleFonts.manrope(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                if (user.email != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      user.email!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                if (joinDate.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 12,
                          color: AppPalette.goldSoft,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Account created $joinDate',
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
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