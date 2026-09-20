import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/auth_repository.dart';
import '../services/group_repository.dart';
import '../services/local_session.dart';
import 'group_detail_screen.dart';
import 'group_screen.dart';
import 'profile_screen.dart';

/// Home: lists every group the account has joined. When there are no groups
/// yet it offers "Create group" / "Join group" buttons; once groups exist the
/// create action becomes the floating + button in the bottom-right corner.
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.auth,
    required this.user,
    required this.repository,
    required this.local,
  });

  final AuthRepository auth;
  final AuthUser user;
  final GroupRepository repository;
  final LocalSession local;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<GroupInfo> _groups = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.repository.myGroups().listen(
      (groups) {
        if (!mounted) return;
        setState(() {
          _groups
            ..clear()
            ..addAll(groups);
          _loading = false;
          _busy = false;
        });
      },
      onError: (Object _) {
        if (!mounted) return;
        setState(() => _loading = false);
      },
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  void _openGroup(GroupInfo g) {
    widget.local.setGroupId(g.id);
    if (widget.local.managingAs.isEmpty) {
      widget.local.setManagingAs(widget.local.displayName);
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GroupDetailScreen(
          groupId: g.id,
          repository: widget.repository,
          local: widget.local,
        ),
      ),
    );
  }

  void _openProfile() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfileScreen(
          user: widget.user,
          repository: widget.repository,
          auth: widget.auth,
        ),
      ),
    );
  }

  Future<void> _confirmLogOut() async {
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

  void _showCreateJoinSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_box_outlined),
              title: const Text('Create group'),
              onTap: () {
                Navigator.pop(ctx);
                _createGroup();
              },
            ),
            ListTile(
              leading: const Icon(Icons.login_outlined),
              title: const Text('Join group'),
              onTap: () {
                Navigator.pop(ctx);
                _joinGroup();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _createGroup() async {
    final nameController = TextEditingController();
    final youController =
        TextEditingController(text: widget.local.displayName);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create group'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Group name (e.g. Trip Rome)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: youController,
                decoration: const InputDecoration(labelText: 'Your name'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              ctx,
              '${nameController.text.trim()}|${youController.text.trim()}',
            ),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (result == null || !result.contains('|')) return;
    final parts = result.split('|');
    final groupName = parts[0];
    final you = parts[1];
    if (groupName.isEmpty || you.isEmpty) return;

    setState(() => _busy = true);
    try {
      final group = await widget.repository.createGroup(
        name: groupName,
        member: you,
      );
      if (!mounted) return;
      _openGroup(group);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast('Could not create the group. Check your connection.');
    }
  }

  Future<void> _joinGroup() async {
    final codeController = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Join group'),
        content: TextField(
          controller: codeController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Group code',
            hintText: 'Paste the code from another phone',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, codeController.text.trim()),
            child: const Text('Check code'),
          ),
        ],
      ),
    );
    if (code == null || code.isEmpty) return;

    setState(() => _busy = true);
    GroupInfo? found;
    try {
      found = await widget.repository.fetchGroup(code);
    } catch (_) {
      found = null;
    }
    if (!mounted) return;
    setState(() => _busy = false);

    if (found == null) {
      _toast('No group found with that code.');
      return;
    }
    final name = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => JoinSetupScreen(group: found!, repository: widget.repository),
      ),
    );
    if (name == null || name.isEmpty) return;

    setState(() => _busy = true);
    try {
      final group = await widget.repository.joinGroup(code, name: name);
      if (!mounted) return;
      _openGroup(group);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast('Could not join the group. Check your connection.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My groups'),
        actions: [
          IconButton(
            tooltip: 'Account',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: _openProfile,
          ),
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: _confirmLogOut,
          ),
        ],
      ),
      floatingActionButton:
          _groups.isEmpty ? null : FloatingActionButton(
        tooltip: 'Create or join',
        onPressed: _busy ? null : _showCreateJoinSheet,
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _groups.isEmpty
                ? _EmptyHome(
                    onCreate: _createGroup,
                    onJoin: _joinGroup,
                    busy: _busy,
                  )
                : _GroupList(
                    groups: _groups,
                    busy: _busy,
                    onOpen: _openGroup,
                  ),
      ),
    );
  }
}

class _EmptyHome extends StatelessWidget {
  const _EmptyHome({
    required this.onCreate,
    required this.onJoin,
    required this.busy,
  });

  final VoidCallback onCreate;
  final VoidCallback onJoin;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.groups, size: 56, color: theme.colorScheme.primary),
              const SizedBox(height: 12),
              Text(
                'Start sharing expenses',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Create a group and its code for friends, or join one with a '
                'code you received. Groups you join show up here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.outline),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: busy ? null : onCreate,
                icon: const Icon(Icons.add_box_outlined),
                label: const Text('Create group'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: busy ? null : onJoin,
                icon: const Icon(Icons.login_outlined),
                label: const Text('Join group'),
              ),
              if (busy) ...[
                const SizedBox(height: 24),
                const Center(child: CircularProgressIndicator()),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupList extends StatelessWidget {
  const _GroupList({
    required this.groups,
    required this.busy,
    required this.onOpen,
  });

  final List<GroupInfo> groups;
  final bool busy;
  final void Function(GroupInfo) onOpen;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: groups.length,
        itemBuilder: (context, i) {
          final g = groups[i];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: ListTile(
              leading: CircleAvatar(
                child: Text(
                  g.name.isEmpty ? '?' : g.name[0].toUpperCase(),
                ),
              ),
              title: Text(g.name),
              subtitle: Text(
                '${g.members.length} member${g.members.length == 1 ? '' : 's'}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: busy ? null : () => onOpen(g),
            ),
          );
        },
    );
  }
}