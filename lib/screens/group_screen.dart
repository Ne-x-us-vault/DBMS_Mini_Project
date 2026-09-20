import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/group_repository.dart';

/// First-launch screen: create a new group or join an existing one
/// with its group code (the Firestore document id).
class GroupScreen extends StatefulWidget {
  const GroupScreen({
    super.key,
    required this.repository,
    required this.onJoined,
  });

  final GroupRepository repository;
  final Future<void> Function(String groupId, String managingAs) onJoined;

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {
  bool _busy = false;

  Future<void> _createGroup() async {
    final nameController = TextEditingController();
    final youController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create group'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                    labelText: 'Group name (e.g. Roommates)'),
                autofocus: true,
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
    if (name == null || !name.contains('|')) return;
    final parts = name.split('|');
    final groupName = parts[0];
    final you = parts[1];
    if (groupName.isEmpty || you.isEmpty) return;

    setState(() => _busy = true);
    try {
      final group = await widget.repository.createGroup(name: groupName, member: you);
      if (!mounted) return;
      await widget.onJoined(group.id, you);
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
          decoration: const InputDecoration(
            labelText: 'Group code',
            hintText: 'Paste the code from another phone',
          ),
          autofocus: true,
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
    GroupInfo? group;
    try {
      group = await widget.repository.fetchGroup(code);
    } catch (_) {
      group = null;
    }
    if (!mounted) return;
    setState(() => _busy = false);

    final found = group;
    if (found == null) {
      _toast('No group found with that code.');
      return;
    }
    final name = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            JoinSetupScreen(group: found, repository: widget.repository),
      ),
    );
    if (name == null || name.isEmpty) return;
    await widget.onJoined(found.id, name);
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.groups,
                      size: 56, color: theme.colorScheme.primary),
                  const SizedBox(height: 12),
                  Text(
                    'Split Chat',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Share one group of expenses across several phones. Every phone stays in sync in real time.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.colorScheme.outline),
                  ),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: _busy ? null : _createGroup,
                    icon: const Icon(Icons.add_box_outlined),
                    label: const Text('Create group'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _joinGroup,
                    icon: const Icon(Icons.login_outlined),
                    label: const Text('Join group'),
                  ),
                  if (_busy) ...[
                    const SizedBox(height: 24),
                    const Center(child: CircularProgressIndicator()),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// After confirming a group code: pick your "Managing as" name from the
/// existing members or add your own name.
class JoinSetupScreen extends StatefulWidget {
  const JoinSetupScreen({
    super.key,
    required this.group,
    required this.repository,
  });

  final GroupInfo group;
  final GroupRepository repository;

  @override
  State<JoinSetupScreen> createState() => _JoinSetupScreenState();
}

class _JoinSetupScreenState extends State<JoinSetupScreen> {
  String? _selected;
  bool _addMine = false;
  final TextEditingController _mine = TextEditingController();

  @override
  void dispose() {
    _mine.dispose();
    super.dispose();
  }

  String? get _pick =>
      _addMine ? (_mine.text.trim().isEmpty ? null : _mine.text.trim()) : _selected;

  Future<void> _continue() async {
    final name = _pick;
    if (name == null) return;
    if (_addMine && !widget.group.members.contains(name)) {
      await widget.repository.setMembers(
        widget.group.id,
        [...widget.group.members, name],
      );
    }
    if (!mounted) return;
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final members = widget.group.members;
    return Scaffold(
      appBar: AppBar(title: const Text('Joining group')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '“${widget.group.name}” · You’ll manage expenses, history and chat as one of the members below.',
            style: TextStyle(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 16),
          for (final m in members)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(child: Text(m[0].toUpperCase())),
                title: Text(m),
                trailing: _addMine
                    ? null
                    : Icon(
                        _selected == m
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: _selected == m
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outline,
                      ),
                onTap: () => setState(() {
                  _addMine = false;
                  _selected = m;
                }),
              ),
            ),
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(child: const Icon(Icons.person_add_alt)),
              title: const Text("Add my own name"),
              trailing: Icon(
                _addMine ? Icons.check_circle : Icons.radio_button_unchecked,
                color: _addMine
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
              ),
              onTap: () => setState(() => _addMine = true),
            ),
          ),
          if (_addMine) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _mine,
              decoration: const InputDecoration(
                labelText: 'Your name',
                hintText: 'Will be added as a new member',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _pick == null ? null : _continue,
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }
}